import SwiftUI
import WidgetKit

struct ComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var kind: WatchMetricKind {
        entry.configuration.metric.watchMetricKind
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    // MARK: - Circular

    private var circularView: some View {
        VStack(spacing: 1) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 12, weight: .semibold))

            Text(shortValueText)
                .font(.system(size: 13, design: .rounded).weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .widgetAccentable()
    }

    // MARK: - Inline

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
            Text(inlineValueText)
        }
    }

    // MARK: - Helpers

    private var shortValueText: String {
        guard let data = entry.data,
              let val = data.latestDisplayValue(for: kind) else { return "—" }
        return String(format: "%.1f", val)
    }

    private var inlineValueText: String {
        guard let data = entry.data else { return "\(kind.displayName): —" }
        return "\(kind.shortName) \(data.formattedValue(for: kind))"
    }
}
