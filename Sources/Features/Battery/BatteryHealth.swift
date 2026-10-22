import Foundation

/// Battery wear as System Settings shows it. macOS derives the maximum capacity
/// from data IOKit does not publish (the raw capacities there give a different
/// figure), so this reads `system_profiler`, which reports the same numbers.
struct BatteryHealth: Equatable, Sendable {
    /// Percent of the design capacity, e.g. 91.
    var maximumCapacity: Int?
    var cycleCount: Int?
    /// `false` when macOS recommends service; `nil` when it did not say.
    var isNormal: Bool?

    /// Runs `system_profiler SPPowerDataType -json` (a few hundred milliseconds)
    /// on a background queue. `nil` when it fails or reports no battery.
    static func read() async -> BatteryHealth? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: readBlocking())
            }
        }
    }

    private static func readBlocking() -> BatteryHealth? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain before waiting: a full pipe would otherwise block the child forever.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }

    private static func parse(_ data: Data) -> BatteryHealth? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPPowerDataType"] as? [[String: Any]],
            let info = sections.lazy.compactMap({ $0["sppower_battery_health_info"] as? [String: Any] }).first
        else { return nil }

        return BatteryHealth(
            // Reported as a string such as "91%".
            maximumCapacity: (info["sppower_battery_health_maximum_capacity"] as? String)
                .flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) },
            cycleCount: info["sppower_battery_cycle_count"] as? Int,
            // "Good" is what System Settings shows as "Normal"; anything else recommends service.
            isNormal: (info["sppower_battery_health"] as? String).map { $0 == "Good" }
        )
    }
}
