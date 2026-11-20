import Foundation
import Security

/// Reads the Google sign-in that the Antigravity app keeps in the login
/// keychain (service "gemini", account "antigravity") and hands `GoogleUsage` a
/// usable access token for its requests. Notch never writes to that keychain
/// item: it reads the stored token, uses it while it is still valid, and when
/// it has expired exchanges the item's refresh token for a fresh access token
/// that it holds in memory only (never written back to the keychain or to
/// disk). The first read prompts macOS for keychain access, which the user
/// allows once.
///
/// The refresh needs the OAuth client Antigravity itself uses. Rather than ship
/// that client's id and secret inside Notch, `GoogleAuth` discovers them at run
/// time from the Antigravity binary on this Mac (`GoogleCredentials`) and tries
/// the pairs until Google accepts one, which it then keeps in memory. So no
/// Google credential — the token or the client — is ever stored in Notch or in
/// its source. Nothing here may log or report the access token, the refresh
/// token, the client secret, the keychain blob, or any part of them.
@MainActor
final class GoogleAuth {
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// The keychain item Antigravity stores its token in.
    private static let keychainService = "gemini"
    private static let keychainAccount = "antigravity"
    /// `go-keyring` (the library Antigravity uses) base64-wraps values over a size.
    private static let base64Prefix = "go-keyring-base64:"
    /// Refresh this long before the token's own expiry, so a token never goes
    /// stale mid-request.
    private static let expiryMargin: TimeInterval = 120

    /// Shared with `GoogleUsage` for its calls to the same host family.
    let session: URLSession
    /// The last access token and when it expires; kept only in memory.
    private var cached: (token: String, expiry: Date)?
    /// The client id and secret Google accepted (from the Antigravity binary),
    /// kept in memory so later refreshes skip the scan and the other pairs.
    private var credential: (clientID: String, clientSecret: String)?

    init(session: URLSession = GoogleAuth.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = UsageClient.requestTimeout
        configuration.timeoutIntervalForResource = UsageClient.resourceTimeout
        return URLSession(configuration: configuration)
    }

    /// A valid bearer token: the in-memory one while it lasts, else the keychain
    /// item's while it lasts, else a fresh one from a refresh. Throws
    /// `.signedOut` when Antigravity is not signed in (no item, or no refresh token).
    func accessToken(now: Date = Date()) async throws(UsageFetchError) -> String {
        if let cached, cached.expiry > now.addingTimeInterval(Self.expiryMargin) {
            return cached.token
        }
        let stored = try readStoredToken()
        if let token = stored.accessToken, let expiry = stored.expiry,
           expiry > now.addingTimeInterval(Self.expiryMargin) {
            cached = (token, expiry)
            return token
        }
        guard let refreshToken = stored.refreshToken else { throw .signedOut }
        let refreshed = try await refresh(refreshToken: refreshToken, now: now)
        cached = refreshed
        return refreshed.token
    }

    /// Drops the in-memory token, so the next read goes back to the keychain and
    /// (if needed) a refresh. Called after a request is rejected, in case the
    /// Antigravity sign-in changed under us. The discovered client is kept: it
    /// does not change when the user signs in again.
    func forget() {
        cached = nil
    }

    // MARK: Keychain

    struct StoredToken: Equatable {
        var accessToken: String?
        var refreshToken: String?
        var expiry: Date?
    }

    /// The token Antigravity stored, or `.signedOut` when the item is missing.
    /// A present-but-unreadable item (denied, or a format we do not recognize)
    /// also reads as signed out, so Notch only ever says "not signed in", never
    /// anything about the token itself.
    private func readStoredToken() throws(UsageFetchError) -> StoredToken {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { throw .signedOut }
        return Self.parse(data) ?? StoredToken()
    }

    /// Reads go-keyring's stored value: a base64-wrapped JSON object
    /// `{ "token": { "access_token", "refresh_token", "expiry" } }`.
    static func parse(_ data: Data) -> StoredToken? {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix(base64Prefix) {
            guard let decoded = Data(base64Encoded: String(text.dropFirst(base64Prefix.count))) else { return nil }
            text = String(decoding: decoded, as: UTF8.self)
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let token = (object as? [String: Any])?["token"] as? [String: Any]
        else { return nil }
        return StoredToken(
            accessToken: token["access_token"] as? String,
            refreshToken: token["refresh_token"] as? String,
            expiry: UsageJSON.date(token["expiry"])
        )
    }

    // MARK: Refresh

    /// What one token request came to, so the caller knows whether to try the
    /// next client pair, stop, or give up.
    private enum Attempt {
        case success(token: String, expiry: Date)
        /// The client was accepted but the refresh token was not: sign in again.
        case invalidGrant
        /// This client pair is not the right one; try another.
        case wrongClient
        /// The network failed, or the request was cancelled: stop trying.
        case stop(UsageFetchError)
    }

    /// A fresh access token, with the client Google accepts. Tries the client
    /// kept from before, then the ones found in the Antigravity binary.
    private func refresh(refreshToken: String, now: Date) async throws(UsageFetchError) -> (token: String, expiry: Date) {
        if let credential {
            switch await attempt(credential, refreshToken: refreshToken, now: now) {
            case .success(let token, let expiry): return (token, expiry)
            case .invalidGrant: throw .signedOut
            case .stop(let error): throw error
            // The stored client stopped working (rare): rediscover below.
            case .wrongClient: self.credential = nil
            }
        }

        let candidates = await Task.detached(priority: .utility) { GoogleCredentials.scan() }.value
        // No binary, or none of its strings look like a client: Antigravity is
        // not installed here, so there is nothing to refresh with.
        guard !candidates.isEmpty else { throw .signedOut }

        var sawInvalidGrant = false
        for clientID in candidates.clientIDs {
            for clientSecret in candidates.secrets {
                switch await attempt((clientID, clientSecret), refreshToken: refreshToken, now: now) {
                case .success(let token, let expiry):
                    credential = (clientID, clientSecret)
                    return (token, expiry)
                case .invalidGrant:
                    // This client is the right one; the refresh token is stale.
                    sawInvalidGrant = true
                case .wrongClient:
                    continue
                case .stop(let error):
                    throw error
                }
            }
        }
        // A right client with a stale token means sign in again; otherwise the
        // binary did not yield the client Antigravity uses.
        throw sawInvalidGrant ? .signedOut : .failed(.formatChanged)
    }

    /// Posts one refresh with a given client pair and classifies the answer.
    private func attempt(
        _ credential: (clientID: String, clientSecret: String),
        refreshToken: String,
        now: Date
    ) async -> Attempt {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.form([
            "client_id": credential.clientID,
            "client_secret": credential.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            return .stop(.cancelled)
        } catch is CancellationError {
            return .stop(.cancelled)
        } catch {
            return .stop(Task.isCancelled ? .cancelled : .failed(.network))
        }
        guard let http = response as? HTTPURLResponse else { return .stop(.failed(.network)) }
        if (200..<300).contains(http.statusCode) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["access_token"] as? String, !token.isEmpty
            else { return .stop(.failed(.formatChanged)) }
            let lifetime = UsageJSON.numberOrZero(object["expires_in"])
            return .success(token: token, expiry: now.addingTimeInterval(lifetime > 0 ? lifetime : 3600))
        }
        // 400/401 carry an OAuth error: a bad token (invalid_grant) means sign
        // in again; a bad client (invalid_client) means try the next pair.
        if http.statusCode == 400 || http.statusCode == 401 {
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            return error == "invalid_grant" ? .invalidGrant : .wrongClient
        }
        return .stop(.failed(.status(http.statusCode)))
    }

    /// `application/x-www-form-urlencoded` body, each value percent-encoded.
    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = fields.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
