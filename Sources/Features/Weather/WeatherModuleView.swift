import AppKit
import NotchKit
import NotchUI
import SwiftUI

/// The weather module at the size Home gives it: compact (current conditions
/// over three hours) at its narrowest, current conditions beside more hours once
/// wide enough (see `WeatherArrangement`).
struct WeatherModuleView: View {
    let model: WeatherModel
    let size: CGSize

    /// How often the module checks whether the report needs a refresh.
    static let checkInterval: Duration = .seconds(60)

    var body: some View {
        NotchCard {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        // SwiftUI cancels this when the module leaves the screen, such as when the
        // panel collapses.
        .task {
            while !Task.isCancelled {
                model.refreshIfNeeded()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .ready:
            if let report = model.report {
                WeatherReportView(report: report, arrangement: .forWidth(size.width))
            }
        case .loading:
            StatusView {
                ProgressView()
                    .controlSize(.small)
            } text: {
                localized(en: "Getting weather…", zh: "正在获取天气…")
            }
        case .locationNotAllowed:
            VStack(spacing: 6) {
                StatusView {
                    Image(systemName: "location.slash")
                        .font(.system(size: 18))
                        .foregroundStyle(NotchTheme.secondaryText)
                } text: {
                    localized(en: "Location access needed", zh: "需要定位权限")
                }
                GlassCapsuleButton(localized(en: "Open Settings", zh: "打开设置"), symbol: "gear") {
                    let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
                    if let url = URL(string: url) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .failed:
            StatusView {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(NotchTheme.secondaryText)
            } text: {
                localized(en: "Weather unavailable", zh: "暂时无法获取天气")
            }
        }
    }
}

/// An icon over a short line, for the states without a report.
private struct StatusView<Icon: View>: View {
    @ViewBuilder let icon: Icon
    let text: () -> String

    var body: some View {
        VStack(spacing: 6) {
            icon
            Text(text())
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct WeatherReportView: View {
    let report: WeatherReport
    let arrangement: WeatherArrangement

    var body: some View {
        // Drawn from the time of drawing, so the hours move on while the report ages.
        let hours = Array(report.upcomingHours(after: Date()).prefix(arrangement.hourCount))
        switch arrangement {
        case .compact:
            compact(hours: hours)
        case .wide:
            wide(hours: hours)
        }
    }

    private func compact(hours: [WeatherReport.Reading]) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ConditionSymbol(reading: report.current, size: 24)
                // The label goes under the temperature: beside it, it does not fit
                // a module a third of the row wide.
                VStack(alignment: .leading, spacing: 0) {
                    Text(temperatureText(report.current.temperature))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(report.current.condition.label(in: Localization.shared.language))
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(hours, id: \.time) { hour in
                    HourColumn(reading: hour, labelSize: 10, symbolSize: 15, temperatureSize: 12)
                }
            }
        }
    }

    private func wide(hours: [WeatherReport.Reading]) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    ConditionSymbol(reading: report.current, size: 22)
                    Text(temperatureText(report.current.temperature))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(report.current.condition.label(in: Localization.shared.language))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let high = report.todayHigh, let low = report.todayLow {
                    let high = temperatureText(high)
                    let low = temperatureText(low)
                    Text(localized(en: "H:\(high) L:\(low)", zh: "最高 \(high) 最低 \(low)"))
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: WeatherArrangement.currentPanelWidth, alignment: .leading)
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 6)
                .frame(width: WeatherArrangement.panelGap)
            HStack(spacing: WeatherArrangement.hourSpacing) {
                ForEach(hours, id: \.time) { hour in
                    HourColumn(reading: hour, labelSize: 11, symbolSize: 16, temperatureSize: 13)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct HourColumn: View {
    let reading: WeatherReport.Reading
    let labelSize: CGFloat
    let symbolSize: CGFloat
    let temperatureSize: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Text(WeatherFormat.hourLabel(reading.time, calendar: .current, language: Localization.shared.language))
                .font(.system(size: labelSize))
                .foregroundStyle(NotchTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ConditionSymbol(reading: reading, size: symbolSize)
            Text(temperatureText(reading.temperature))
                .font(.system(size: temperatureSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ConditionSymbol: View {
    let reading: WeatherReport.Reading
    let size: CGFloat

    var body: some View {
        Image(systemName: reading.condition.symbol(isDay: reading.isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .frame(height: size * 1.1)
    }
}

/// In the unit the user's region uses for weather, read at draw time.
private func temperatureText(_ celsius: Double) -> String {
    WeatherFormat.temperature(celsius, in: UnitTemperature(forLocale: .current, usage: .weather))
}
