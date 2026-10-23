import AppKit
import NotchKit
import NotchUI
import SwiftUI

/// The weather module at the size Home gives it: compact (a summary over three
/// columns) at its narrowest, a summary beside more columns once wide enough
/// (see `WeatherArrangement`). What it summarizes follows the time of day: the
/// next hours, today, or tomorrow, as `WeatherSettings` schedules them.
struct WeatherModuleView: View {
    let model: WeatherModel
    let size: CGSize

    /// How often the module checks whether the report needs a refresh.
    static let checkInterval: Duration = .seconds(60)

    var body: some View {
        // Redrawn every minute, so the hours move on and the shown period
        // changes on time.
        TimelineView(.everyMinute) { context in
            let forecast = forecast(at: context.date)
            let summary = forecast?.summary
            // Tinted by the sky the summary shows.
            NotchCard(tint: summary.flatMap { $0.condition.tint(isDay: $0.isDay) }) {
                content(forecast)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

    /// What the module shows at `date`, once a report is ready.
    private func forecast(at date: Date) -> WeatherForecast? {
        guard model.status == .ready, let report = model.report else { return nil }
        return WeatherForecast(
            report: report,
            mode: WeatherSettings.shared.schedule.mode(at: date, calendar: .current),
            now: date
        )
    }

    @ViewBuilder
    private func content(_ forecast: WeatherForecast?) -> some View {
        switch model.status {
        case .ready:
            if let forecast {
                WeatherReportView(forecast: forecast, arrangement: .forWidth(size.width))
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

/// What one display mode shows: a summary and the readings for the columns.
/// Today and tomorrow fall back to the next hours when the report lacks that day.
@MainActor
struct WeatherForecast {
    /// The summary's parts.
    struct Summary {
        /// "Now", "Today", or "Tomorrow".
        let title: String
        let condition: WeatherCondition
        let isDay: Bool
        /// The current temperature, or the day's high.
        let temperature: Double
        /// The day's low, shown after the high; `nil` for the current conditions.
        let low: Double?
        /// The line under the temperature.
        let detail: String?
    }

    let summary: Summary
    /// Readings for the columns, in order, as many as `columns(_:)` is asked for.
    private let readings: (Int) -> [WeatherReport.Reading]
    /// Readings before this time are dimmed (a day's hours already past).
    let pastBefore: Date?

    init(report: WeatherReport, mode: WeatherDisplayMode, now: Date) {
        let day: WeatherReport.Day? = switch mode {
        case .today: report.today
        case .tomorrow: report.tomorrow
        case .upcoming: nil
        }
        if let day {
            summary = Summary(
                title: mode == .today
                    ? localized(en: "Today", zh: "今天")
                    : localized(en: "Tomorrow", zh: "明天"),
                condition: day.condition,
                isDay: true,
                temperature: day.high,
                low: day.low,
                detail: day.precipitationChance.map { chance in
                    localized(en: "Rain \(chance)%", zh: "降水概率 \(chance)%")
                }
            )
            readings = { report.hours(on: day, count: $0) }
            pastBefore = mode == .today ? now : nil
        } else {
            let current = report.current
            summary = Summary(
                title: localized(en: "Now", zh: "现在"),
                condition: current.condition,
                isDay: current.isDay,
                temperature: current.temperature,
                low: nil,
                detail: report.today.map { today in
                    let high = temperatureText(today.high)
                    let low = temperatureText(today.low)
                    return localized(en: "H:\(high) L:\(low)", zh: "最高 \(high) 最低 \(low)")
                }
            )
            readings = { Array(report.upcomingHours(after: now).prefix($0)) }
            pastBefore = nil
        }
    }

    func columns(_ count: Int) -> [WeatherReport.Reading] {
        readings(count)
    }
}

/// Lays out a forecast. Both arrangements share one set of rows, so labels,
/// symbols, and temperatures line up across the summary and the columns.
private struct WeatherReportView: View {
    let forecast: WeatherForecast
    let arrangement: WeatherArrangement

    /// Heights of the three rows: labels, symbols, temperatures.
    static let labelRow: CGFloat = 14
    static let symbolRow: CGFloat = 34
    static let valueRow: CGFloat = 16
    static let rowSpacing: CGFloat = 5

    var body: some View {
        let columns = forecast.columns(arrangement.hourCount)
        switch arrangement {
        case .compact:
            compact(columns: columns)
        case .wide:
            wide(columns: columns)
        }
    }

    private func compact(columns: [WeatherReport.Reading]) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ConditionSymbol(condition: forecast.summary.condition, isDay: forecast.summary.isDay, size: 24)
                // The label goes under the temperature: beside it, it does not fit
                // a module a third of the row wide.
                VStack(alignment: .leading, spacing: 0) {
                    SummaryTemperature(summary: forecast.summary, size: 24)
                    Text("\(forecast.summary.title) · \(forecast.summary.condition.label(in: Localization.shared.language))")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(spacing: WeatherArrangement.hourSpacing) {
                ForEach(columns, id: \.time) { reading in
                    HourColumn(reading: reading, isPast: isPast(reading), labelSize: 10, symbolSize: 15, temperatureSize: 12)
                }
            }
        }
    }

    private func wide(columns: [WeatherReport.Reading]) -> some View {
        HStack(spacing: 0) {
            summaryColumn
                .frame(width: WeatherArrangement.currentPanelWidth, alignment: .leading)
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: Self.labelRow + Self.symbolRow + Self.valueRow + Self.rowSpacing * 2)
                .frame(width: WeatherArrangement.panelGap)
            HStack(spacing: WeatherArrangement.hourSpacing) {
                ForEach(columns, id: \.time) { reading in
                    HourColumn(
                        reading: reading,
                        isPast: isPast(reading),
                        labelSize: 11,
                        symbolSize: 18,
                        temperatureSize: 13,
                        rowHeights: (Self.labelRow, Self.symbolRow, Self.valueRow),
                        rowSpacing: Self.rowSpacing
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The summary in the same three rows as the columns: title and condition,
    /// symbol and temperature, then the detail line.
    private var summaryColumn: some View {
        let summary = forecast.summary
        return VStack(alignment: .leading, spacing: Self.rowSpacing) {
            HStack(spacing: 4) {
                Text(summary.title)
                    .font(.system(size: 11, weight: .semibold))
                Text(summary.condition.label(in: Localization.shared.language))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: Self.labelRow)
            HStack(spacing: 5) {
                ConditionSymbol(condition: summary.condition, isDay: summary.isDay, size: 22)
                SummaryTemperature(summary: summary, size: 28)
            }
            .frame(height: Self.symbolRow)
            Text(summary.detail ?? "")
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: Self.valueRow)
        }
    }

    private func isPast(_ reading: WeatherReport.Reading) -> Bool {
        forecast.pastBefore.map { reading.time < $0 } ?? false
    }
}

/// The summary's temperature: the current one, or a day's high with its low after it.
private struct SummaryTemperature: View {
    let summary: WeatherForecast.Summary
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(temperatureText(summary.temperature))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.headline())
            if let low = summary.low {
                Text("/" + temperatureText(low))
                    .font(.system(size: size * 0.55, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct HourColumn: View {
    let reading: WeatherReport.Reading
    let isPast: Bool
    let labelSize: CGFloat
    let symbolSize: CGFloat
    let temperatureSize: CGFloat
    /// Fixed row heights, so the rows line up with the summary's; `nil` sizes to fit.
    var rowHeights: (label: CGFloat, symbol: CGFloat, value: CGFloat)?
    var rowSpacing: CGFloat = 4

    var body: some View {
        VStack(spacing: rowSpacing) {
            Text(WeatherFormat.hourLabel(reading.time, calendar: .current, language: Localization.shared.language))
                .font(.system(size: labelSize))
                .foregroundStyle(NotchTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: rowHeights?.label)
            ConditionSymbol(condition: reading.condition, isDay: reading.isDay, size: symbolSize)
                .frame(height: rowHeights?.symbol)
            Text(temperatureText(reading.temperature))
                .font(.system(size: temperatureSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: rowHeights?.value)
        }
        .frame(maxWidth: .infinity)
        .opacity(isPast ? 0.4 : 1)
    }
}

private struct ConditionSymbol: View {
    let condition: WeatherCondition
    let isDay: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: condition.symbol(isDay: isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .frame(height: size * 1.1)
    }
}

private extension WeatherCondition {
    /// The weather card's tint: warm sun, a night sky, rain, snow, or storm; none
    /// for gray skies.
    func tint(isDay: Bool) -> Color? {
        switch self {
        case .clear, .mostlyClear, .partlyCloudy: isDay ? .orange : .indigo
        case .cloudy, .fog, .unknown: nil
        case .drizzle, .lightRain, .rain, .heavyRain, .showers, .heavyShowers: .blue
        case .freezingDrizzle, .freezingRain, .lightSnow, .snow, .heavySnow, .snowGrains, .snowShowers: .cyan
        case .thunderstorms, .thunderstormsWithHail: .purple
        }
    }
}

/// In the unit the user's region uses for weather, read at draw time.
@MainActor
private func temperatureText(_ celsius: Double) -> String {
    WeatherFormat.temperature(celsius, in: UnitTemperature(forLocale: .current, usage: .weather))
}
