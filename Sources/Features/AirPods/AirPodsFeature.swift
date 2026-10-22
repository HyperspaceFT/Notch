import IOBluetooth
import NotchKit
import NotchUI
import Observation
import SwiftUI

/// Shows a short activity with the battery level when AirPods connect, and, while
/// they stay connected, a tab left of the notch with their battery levels, volume,
/// and noise-control mode. Needs Bluetooth access; without it the tab stays hidden.
@MainActor
public final class AirPodsFeature: NotchFeature {
    public let id = "airpods"
    public var title: String { model.connection?.name ?? localized(en: "AirPods", zh: "AirPods") }
    public var symbol: String { model.connection?.product.symbol ?? "airpods" }
    public let tabPlacement = NotchTabPlacement.leading
    public var isTabAvailable: Bool { model.connection != nil }

    /// How long the connection activity stays visible.
    static let activityDuration: TimeInterval = 4

    private let model = AirPodsModel()
    private let authorizer = BluetoothAuthorizer()
    private var monitor: AirPodsMonitor?
    private weak var context: (any NotchContext)?

    public init() {}

    public func activate(context: any NotchContext) {
        self.context = context
        if BluetoothAuthorizer.isGranted {
            startMonitoring()
        } else if BluetoothAuthorizer.isUndecided {
            authorizer.request { [weak self] in
                // Cancelled in `deactivate`, so this only runs while active.
                self?.startMonitoring()
            }
        }
        // Denied or restricted: nothing to do; the tab stays hidden.
    }

    public func deactivate() {
        authorizer.cancel()
        monitor?.stop()
        monitor = nil
        if model.connection != nil {
            context?.dismiss(activityID: "connected")
        }
        model.disconnect()
        context = nil
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(AirPodsExpandedView(model: model))
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        let monitor = AirPodsMonitor { [weak self] device, isNewConnection in
            self?.currentDeviceChanged(device, isNewConnection: isNewConnection)
        }
        self.monitor = monitor
        monitor.start()
    }

    private func currentDeviceChanged(_ device: IOBluetoothDevice?, isNewConnection: Bool) {
        let previousAddress = model.connection?.address
        guard let device, let product = device.airPodsProduct else {
            context?.dismiss(activityID: "connected")
            model.disconnect()
            return
        }
        guard isNewConnection || device.addressString != previousAddress else { return }
        // The notice belongs to the AirPods that connected; another pair taking
        // over (the newest one disconnected) gets none.
        context?.dismiss(activityID: "connected")
        model.connect(device, product: product)
        guard isNewConnection else { return }
        context?.present(NotchActivity(
            id: "connected",
            priority: .high,
            duration: Self.activityDuration
        ) {
            Image(systemName: product.symbol)
        } trailing: { [model] in
            AirPodsActivityTrailing(model: model)
        })
    }
}

/// The connected AirPods and what the panel shows about them.
@MainActor
@Observable
final class AirPodsModel {
    struct Connection: Equatable {
        let address: String?
        let name: String?
        let product: AirPodsProduct
    }

    /// How long and how often battery levels are read after a connection; the
    /// AirPods report them a few seconds after the link comes up.
    static let connectPollCount = 10
    static let pollInterval: Duration = .seconds(1)

    private(set) var connection: Connection?
    private(set) var battery = AirPodsBattery()
    /// 0…1; `nil` while the audio device is missing or has no settable volume.
    var volume: Float?
    private(set) var supportedModes: [ListeningMode] = []
    /// `nil` for Off and unknown values.
    private(set) var listeningMode: ListeningMode?

    /// While the slider is dragged, refreshes leave `volume` alone.
    @ObservationIgnored var isEditingVolume = false
    @ObservationIgnored private var device: IOBluetoothDevice?
    @ObservationIgnored private var audio: AirPodsAudioDevice?
    @ObservationIgnored private var connectPoll: Task<Void, Never>?
    @ObservationIgnored private var viewPoll: Task<Void, Never>?

    func connect(_ device: IOBluetoothDevice, product: AirPodsProduct) {
        // The view poll keeps running: when another pair takes over, the tab stays
        // on screen without a new onAppear, and the poll reads the new device.
        connectPoll?.cancel()
        connectPoll = nil
        isEditingVolume = false
        self.device = device
        connection = Connection(address: device.addressString, name: device.name, product: product)
        battery = AirPodsBattery()
        volume = nil
        supportedModes = []
        listeningMode = nil
        audio = nil
        refresh()
        startConnectPoll()
    }

    func disconnect() {
        stopPolling()
        device = nil
        audio = nil
        connection = nil
        battery = AirPodsBattery()
        volume = nil
        supportedModes = []
        listeningMode = nil
        isEditingVolume = false
    }

    /// Reads battery, volume, and noise control again.
    func refresh() {
        guard let device, let connection else { return }
        battery = device.airPodsBattery(for: connection.product)

        audio = AirPodsAudioDevice.find(address: connection.address, name: connection.name)
        if let audio, audio.canSetVolume, let level = audio.volume {
            // A slider that left the screen mid-drag may never report the drag's end.
            if !isEditingVolume || volume == nil {
                volume = level
            }
        } else {
            volume = nil
        }
        if let audio, audio.canSetListeningMode, let mask = audio.supportedListeningModeMask {
            supportedModes = ListeningMode.supported(mask: mask)
            listeningMode = audio.listeningModeRawValue.flatMap(ListeningMode.init(rawValue:))
        } else {
            supportedModes = []
            listeningMode = nil
        }
    }

    func setVolume(_ level: Float) {
        volume = level
        audio?.setVolume(level)
    }

    /// Shows the mode right away; the next refresh reads it back, so a mode the
    /// AirPods reject reverts on screen.
    func setListeningMode(_ mode: ListeningMode) {
        guard audio?.setListeningMode(mode) == true else { return }
        listeningMode = mode
    }

    /// Refreshes every second while the expanded panel holds the AirPods view,
    /// selected or not: the panel keeps every visible tab's view in place.
    func startViewPoll() {
        guard viewPoll == nil, device != nil else { return }
        refresh()
        viewPoll = Task { [weak self] in
            while true {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                refresh()
            }
        }
    }

    func stopViewPoll() {
        viewPoll?.cancel()
        viewPoll = nil
        isEditingVolume = false
    }

    private func startConnectPoll() {
        connectPoll = Task { [weak self] in
            for _ in 0..<Self.connectPollCount {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                refresh()
                if hasBudLevels { break }
            }
            self?.connectPoll = nil
        }
    }

    private var hasBudLevels: Bool {
        guard let connection else { return true }
        if connection.product.hasSingleBattery { return battery.single != nil }
        return battery.left != nil && battery.right != nil
    }

    private func stopPolling() {
        connectPoll?.cancel()
        connectPoll = nil
        stopViewPoll()
    }
}

@MainActor
private func levelTint(_ level: Int?) -> Color {
    guard let level, level <= 20 else { return NotchTheme.primaryText }
    return .red
}

/// The lowest battery level, filled in once the AirPods report it.
private struct AirPodsActivityTrailing: View {
    let model: AirPodsModel

    var body: some View {
        let level = model.battery.lowestLevel
        Text(level.map { "\($0)%" } ?? "—")
            .monospacedDigit()
            .foregroundStyle(level == nil ? NotchTheme.secondaryText : levelTint(level))
            .contentTransition(.numericText())
            .animation(.smooth, value: level)
    }
}

private struct AirPodsExpandedView: View {
    let model: AirPodsModel

    var body: some View {
        HStack(spacing: 10) {
            NotchCard(title: model.connection?.name ?? localized(en: "AirPods", zh: "AirPods")) {
                AirPodsBatteryView(model: model)
            }
            .frame(width: 190)
            NotchCard(title: localized(en: "Controls", zh: "控制")) {
                AirPodsControlsView(model: model)
            }
        }
        .onAppear { model.startViewPoll() }
        .onDisappear { model.stopViewPoll() }
    }
}

private struct AirPodsBatteryView: View {
    let model: AirPodsModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.connection?.product.symbol ?? "airpods")
                .font(.system(size: 30))
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                if model.connection?.product.hasSingleBattery == true {
                    row(localized(en: "Battery", zh: "电量"), model.battery.single)
                } else {
                    row(localized(en: "Left", zh: "左"), model.battery.left)
                    row(localized(en: "Right", zh: "右"), model.battery.right)
                    row(localized(en: "Case", zh: "充电盒"), model.battery.chargingCase)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ label: String, _ level: Int?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.secondaryText)
            Spacer(minLength: 6)
            Text(level.map { "\($0)%" } ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(level == nil ? NotchTheme.secondaryText : levelTint(level))
        }
    }
}

private struct AirPodsControlsView: View {
    let model: AirPodsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.volume != nil {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchTheme.secondaryText)
                    Slider(
                        value: Binding(
                            get: { model.volume ?? 0 },
                            set: { model.setVolume($0) }
                        ),
                        in: 0...1,
                        onEditingChanged: { model.isEditingVolume = $0 }
                    )
                    .tint(.white)
                    .controlSize(.small)
                }
            }
            if !model.supportedModes.isEmpty {
                ListeningModePicker(
                    modes: model.supportedModes,
                    selection: model.listeningMode,
                    select: { model.setListeningMode($0) }
                )
            }
            if model.volume == nil && model.supportedModes.isEmpty {
                Text(localized(en: "No controls available", zh: "没有可用的控制"))
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        }
    }
}

/// Glass capsules, one per supported mode; the selected one is tinted like a
/// selected `GlassIconButton`.
private struct ListeningModePicker: View {
    let modes: [ListeningMode]
    let selection: ListeningMode?
    let select: (ListeningMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(modes, id: \.self) { mode in
                let isSelected = mode == selection
                Button {
                    select(mode)
                } label: {
                    Text(mode.label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? NotchTheme.primaryText : NotchTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    isSelected ? .regular.tint(.white.opacity(0.18)).interactive() : .regular.interactive(),
                    in: .capsule
                )
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

@MainActor
private extension ListeningMode {
    var label: String {
        switch self {
        case .noiseCancellation: localized(en: "Noise Cancel", zh: "降噪")
        case .transparency: localized(en: "Transparency", zh: "通透")
        case .adaptive: localized(en: "Adaptive", zh: "自适应")
        }
    }
}
