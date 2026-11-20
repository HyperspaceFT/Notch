import Foundation

/// Reads the user's Gemini usage in Antigravity by running Antigravity's own
/// command-line tool: `agy -p /usage --output-format json`. That is a built-in,
/// non-interactive command the tool answers locally from the usage it already
/// knows — it starts no conversation, spends no quota, and returns at once
/// (verified: `num_turns` 0, `total_tokens` 0). The tool reads its own sign-in,
/// so Notch needs no Google credentials of its own: it touches no keychain, no
/// token, and no OAuth client, and keeps nothing from the run.
///
/// Its output is undocumented and may change; a failed read only shows as such.
/// Nothing here may log or report the command's raw output.
@MainActor
enum GoogleUsage {
    /// Where the Antigravity CLI usually sits.
    nonisolated static let searchPaths = ["~/.local/bin/agy", "~/.local/bin/antigravity"]
    /// A hard ceiling on the run, in case the tool ever hangs.
    nonisolated static let timeout: TimeInterval = 25
    /// The five-hour and weekly windows Antigravity reports for Gemini.
    nonisolated static let fiveHourDuration: TimeInterval = 5 * 3600
    nonisolated static let weeklyDuration: TimeInterval = 7 * 86400

    static func fetch(now: Date = Date()) async throws(UsageFetchError) -> UsageReport {
        let result = await Task.detached(priority: .utility) { runUsageCommand() }.value
        if Task.isCancelled { throw .cancelled }
        let data: Data
        switch result {
        case .success(let output): data = output
        case .failure(let error): throw error
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw .failed(.formatChanged) }
        return try parse(json, now: now)
    }

    /// The first readable Antigravity CLI among `searchPaths`.
    nonisolated static func binaryURL(fileManager: FileManager = .default) -> URL? {
        for path in searchPaths {
            let expanded = (path as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return nil
    }

    /// Runs the command and returns its stdout. The binary being absent, or the
    /// tool exiting non-zero (its answer when Antigravity is not signed in),
    /// reads as signed out — Notch only ever says "not signed in", never more.
    nonisolated static func runUsageCommand() -> Result<Data, UsageFetchError> {
        guard let binary = binaryURL() else { return .failure(.signedOut) }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["-p", "/usage", "--output-format", "json", "--print-timeout", "20s"]
        // A neutral directory, so the tool does not pick up a project from the cwd.
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return .failure(.signedOut)
        }
        // Don't let a hung tool keep the process alive forever.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return .failure(.signedOut) }
        return .success(data)
    }

    /// Turns the command's JSON into the Gemini windows: the five-hour and
    /// weekly limits that the "Gemini Models" buckets report (`id` starting
    /// `gemini`, the `3p` Claude/GPT buckets left out), shortest first, with the
    /// separate Argon weekly bucket, when any is used, shown as a part of the
    /// weekly window.
    static func parse(_ json: Any, now: Date) throws(UsageFetchError) -> UsageReport {
        guard let root = json as? [String: Any] else { throw .failed(.formatChanged) }
        // A non-success run (most often: Antigravity not signed in).
        if let status = root["status"] as? String, status != "SUCCESS" { throw .signedOut }
        guard let command = root["command"] as? [String: Any],
              let data = command["data"] as? [String: Any],
              let groups = data["groups"] as? [[String: Any]]
        else { throw .failed(.formatChanged) }

        var fiveHour: UsageWindow?
        var weekly: UsageWindow?
        var argonPercent: Double?
        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let id = bucket["id"] as? String, id.hasPrefix("gemini") else { continue }
                let remaining = UsageJSON.number(bucket["remaining_fraction"])
                guard remaining.isFinite else { continue }
                let percent = max(0, (1 - remaining) * 100)
                let resetsAt = UsageJSON.date(bucket["reset_time"])
                let window = bucket["window"] as? String
                if id.contains("argon") {
                    argonPercent = percent
                } else if id == "gemini-5h" || window == "5h" {
                    fiveHour = UsageWindow(duration: fiveHourDuration, percent: percent, resetsAt: resetsAt)
                } else if id == "gemini-weekly" || window == "weekly" {
                    weekly = UsageWindow(duration: weeklyDuration, percent: percent, resetsAt: resetsAt)
                }
            }
        }

        var windows: [UsageWindow] = []
        if let fiveHour { windows.append(fiveHour) }
        if var weekly {
            if let argonPercent, argonPercent > 0 {
                weekly.scoped = [UsageScope(label: "Argon", percent: argonPercent, resetsAt: nil)]
            }
            windows.append(weekly)
        }
        guard !windows.isEmpty else { throw .failed(.formatChanged) }
        return UsageReport(plan: "", windows: windows)
    }
}
