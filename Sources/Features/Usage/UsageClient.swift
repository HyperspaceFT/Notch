import Foundation

/// What kind of answer a request expects.
enum UsageResponseKind: Sendable {
    case json
    case grpcWeb

    /// Whether a `Content-Type` is this kind's.
    func matches(contentType: String?) -> Bool {
        let type = contentType?.lowercased() ?? ""
        switch self {
        case .json: return type.contains("json")
        case .grpcWeb: return type.contains("grpc")
        }
    }

    /// What an answer with `status` and `contentType` means when it is not a
    /// usable one; `nil` when it is. Redirects are never followed, so a 3xx (a
    /// login page's) means signed out; 401, or 403 in the expected type, too.
    /// Any other type, at any status, is a page in place of data: most likely a
    /// Cloudflare challenge, which the sign-in window passes.
    func problem(status: Int, contentType: String?) -> UsageFetchError? {
        let isExpected = matches(contentType: contentType)
        if (300..<400).contains(status) || status == 401 || (status == 403 && isExpected) {
            return .signedOut
        }
        guard isExpected else { return .needsVerification }
        guard (200..<300).contains(status) else { return .failed(.status(status)) }
        return nil
    }
}

/// Never follows a redirect, so the 3xx itself comes back (and counts as
/// signed out) instead of a request with the cookies to wherever it points.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

/// Sends the usage requests: only to the providers' fixed origins, with the
/// sign-in's cookies from `UsageWebSession` and nothing else of the user's.
/// Nothing here may log or report cookies, tokens, headers, or bodies.
@MainActor
final class UsageClient {
    /// How long a request may wait for the server's next bytes.
    static let requestTimeout: TimeInterval = 15
    /// How long a whole request may take.
    static let resourceTimeout: TimeInterval = 30
    /// The largest answer read. The hosts are fixed and first-party, so checking
    /// after the download, with the resource timeout bounding it, is enough.
    static let maximumBodySize = 1_000_000

    private let webSession: UsageWebSession
    private let session: URLSession

    init(webSession: UsageWebSession) {
        self.webSession = webSession
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // The cookies come from the web data store, one request at a time.
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        session = URLSession(configuration: configuration)
    }

    /// GETs `url`, or POSTs `body` as JSON, and decodes the JSON answer.
    func json(
        _ url: URL,
        for provider: UsageProvider,
        headers: [String: String] = [:],
        body: [String: String]? = nil
    ) async throws(UsageFetchError) -> Any {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, _) = try await send(request, for: provider, expecting: .json)
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw .failed(.formatChanged)
        }
        return object
    }

    /// POSTs a gRPC-web request and returns the answer's message.
    func grpcWeb(_ url: URL, for provider: UsageProvider, body: [UInt8] = GrpcWeb.emptyRequest) async throws(UsageFetchError) -> [UInt8] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Grpc-Web")
        request.httpBody = Data(body)
        let (data, headers) = try await send(request, for: provider, expecting: .grpcWeb)
        return try GrpcWeb.message(from: [UInt8](data), headers: headers)
    }

    /// Sends `request` with the cookies that match it and returns a usable
    /// answer's body and headers, or throws what the answer means.
    private func send(
        _ request: URLRequest,
        for provider: UsageProvider,
        expecting kind: UsageResponseKind
    ) async throws(UsageFetchError) -> (Data, [String: String]) {
        guard let url = request.url, url.scheme == "https", url.host() == provider.origin.host() else {
            assertionFailure("A usage request may only go to its provider's origin")
            throw .failed(.network)
        }
        var request = request
        request.timeoutInterval = Self.requestTimeout
        if let cookies = await webSession.cookieHeader(for: url) {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
        }
        if let userAgent = webSession.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.httpMethod == "POST" {
            // What the site's own page sends with its calls.
            request.setValue(provider.origin.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue(provider.origin.absoluteString + "/", forHTTPHeaderField: "Referer")
        }
        guard !Task.isCancelled else { throw .cancelled }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectBlocker())
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw Task.isCancelled ? .cancelled : .failed(.network)
        }
        guard !Task.isCancelled else { throw .cancelled }
        guard let http = response as? HTTPURLResponse else { throw .failed(.network) }

        var headers: [String: String] = [:]
        for case let (name as String, value as String) in http.allHeaderFields {
            headers[name] = value
        }
        await webSession.store(responseHeaders: headers, for: url)
        // A sign-out may have cancelled this meanwhile; nothing of the answer counts then.
        guard !Task.isCancelled else { throw .cancelled }

        if let problem = kind.problem(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type")) {
            throw problem
        }
        guard data.count <= Self.maximumBodySize else { throw .failed(.formatChanged) }
        return (data, headers)
    }
}
