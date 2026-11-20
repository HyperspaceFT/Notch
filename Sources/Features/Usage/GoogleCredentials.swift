import Foundation

/// Finds the OAuth client that the Antigravity app uses, by scanning the
/// Antigravity CLI binary on this Mac for the client id(s) and secret(s) it
/// ships. `GoogleAuth` needs them only to refresh the token Antigravity already
/// obtained; Notch reads the binary, keeps nothing from it on disk, and never
/// writes to it. An installed-application client secret is not confidential —
/// it ships inside every copy of the app, and only names the client to Google's
/// token endpoint.
///
/// Reusing the binary's own credentials (rather than a value baked into Notch)
/// keeps every Gemini credential on the user's machine: if Antigravity is not
/// installed there is no token to refresh anyway. Nothing here may log or
/// report a secret.
enum GoogleCredentials: Sendable {
    /// The client ids and secrets found in the binary, each kept in the order
    /// seen. `GoogleAuth` tries the pairs until Google accepts one.
    struct Candidates: Sendable, Equatable {
        var clientIDs: [String]
        var secrets: [String]

        var isEmpty: Bool { clientIDs.isEmpty || secrets.isEmpty }
    }

    /// Where the Antigravity CLI binary usually sits.
    static let searchPaths = ["~/.local/bin/agy", "~/.local/bin/antigravity"]
    /// Don't map anything absurd; the real binary is a few hundred MB.
    static let maximumBinarySize = 1_000_000_000
    /// Enough of each to cover a client rotation; more would only be tried in vain.
    static let maximumEach = 16

    /// The first readable Antigravity binary among `searchPaths`.
    static func binaryURL(fileManager: FileManager = .default) -> URL? {
        for path in searchPaths {
            let expanded = (path as NSString).expandingTildeInPath
            if fileManager.isReadableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return nil
    }

    /// Scans the Antigravity binary (memory-mapped, so it is not read whole into
    /// RAM) for its embedded credentials; empty when the binary is absent,
    /// unreadable, or too large. Runs off the main actor (it is `nonisolated`
    /// and touches only the file), since the scan takes a moment on a large binary.
    static func scan(fileManager: FileManager = .default) -> Candidates {
        guard let url = binaryURL(fileManager: fileManager) else { return Candidates(clientIDs: [], secrets: []) }
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let size, size > 0, size <= maximumBinarySize,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return Candidates(clientIDs: [], secrets: []) }
        return data.withUnsafeBytes { extract($0) }
    }

    /// The scan over an in-memory copy, for tests.
    static func extract(_ bytes: [UInt8]) -> Candidates {
        bytes.withUnsafeBytes { extract($0) }
    }

    /// `GOCSPX-` followed by exactly 28 of `[A-Za-z0-9_-]` is a client secret;
    /// `<id>.apps.googleusercontent.com`, its `<id>` of `[a-z0-9-]` with a dash
    /// and a leading digit, is a client id. First-byte gated, so the pass over
    /// the whole binary stays cheap.
    static func extract(_ raw: UnsafeRawBufferPointer) -> Candidates {
        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
            return Candidates(clientIDs: [], secrets: [])
        }
        let count = raw.count
        let secretPrefix = Array("GOCSPX-".utf8)
        let idSuffix = Array(".apps.googleusercontent.com".utf8)
        let secretLength = 28

        var secrets: [String] = []
        var ids: [String] = []
        var seenSecrets = Set<String>()
        var seenIDs = Set<String>()

        func isSecretChar(_ byte: UInt8) -> Bool {
            (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                || (0x30...0x39).contains(byte) || byte == 0x2D || byte == 0x5F
        }
        func isIDChar(_ byte: UInt8) -> Bool {
            (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x2D
        }
        func matches(_ at: Int, _ literal: [UInt8]) -> Bool {
            for (offset, byte) in literal.enumerated() where base[at + offset] != byte { return false }
            return true
        }

        var i = 0
        while i < count {
            let byte = base[i]
            if byte == 0x47, i + secretPrefix.count + secretLength <= count, matches(i, secretPrefix) {
                let start = i + secretPrefix.count
                var end = start
                while end < start + secretLength, isSecretChar(base[end]) { end += 1 }
                if end - start == secretLength {
                    let suffix = String(decoding: UnsafeBufferPointer(start: base + start, count: secretLength), as: UTF8.self)
                    let secret = "GOCSPX-" + suffix
                    if seenSecrets.insert(secret).inserted { secrets.append(secret) }
                }
            } else if byte == 0x2E, i + idSuffix.count <= count, matches(i, idSuffix) {
                var start = i
                while start > 0, isIDChar(base[start - 1]) { start -= 1 }
                let prefixLength = i - start
                if prefixLength >= 8 {
                    let prefix = String(decoding: UnsafeBufferPointer(start: base + start, count: prefixLength), as: UTF8.self)
                    if prefix.contains("-"), prefix.first?.isNumber == true {
                        let id = prefix + ".apps.googleusercontent.com"
                        if seenIDs.insert(id).inserted { ids.append(id) }
                    }
                }
            }
            if secrets.count >= maximumEach, ids.count >= maximumEach { break }
            i += 1
        }
        return Candidates(clientIDs: ids, secrets: secrets)
    }
}
