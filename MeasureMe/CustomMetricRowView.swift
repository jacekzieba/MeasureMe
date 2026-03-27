import SwiftUI

struct CustomMetricRowView: View {
    let definition: CustomMetricDefinition
    let isOn: Binding<Bool>
    private let iconTint = AppColorRoles.textPrimary.opacity(0.82)
    private let measurementsTheme = FeatureTheme.measurements

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: definition.sfSymbolName)
                .font(.body)
                .foregroundStyle(iconTint)
                .frame(width: MetricsLayout.iconWidth)

            VStack(alignment: .leading, spacing: 1) {
                Text(definition.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(definition.unitLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .accessibilityLabel(definition.name)
                .frame(width: 52, alignment: .trailing)
                .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, minHeight: MetricsLayout.rowHeight, alignment: .leading)
        .padding(.horizontal, MetricsLayout.horizontalPadding)
        .padding(.vertical, 6)
        .background(
            AppGlassBackground(
                depth: .base,
                cornerRadius: AppRadius.md,
                tint: measurementsTheme.softTint
            )
        )
        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }
}
