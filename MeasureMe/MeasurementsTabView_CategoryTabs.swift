import SwiftUI

// MARK: - MeasurementsCategoryTabs

struct MeasurementsCategoryTabs: View {
    @Namespace private var selectedPillNamespace
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: MeasurementsTabView.MeasurementsTab
    let tabs: [MeasurementsTabView.MeasurementsTab]
    let activeTint: Color
    let animateSelection: Bool

    private func selectedGradient(for tab: MeasurementsTabView.MeasurementsTab) -> LinearGradient {
        switch tab {
        case .metrics:
            return ClaudeLightStyle.directionalGradient(
                colors: [
                    Color.dynamic(light: Color(hex: "#5B7CFF"), dark: Color(hex: "#7DB5FF")),
                    Color.dynamic(light: Color(hex: "#2F56D9"), dark: Color(hex: "#3B82F6"))
                ],
                colorScheme: colorScheme,
                lightColor: AppColorRoles.surfaceInteractive
            )
        case .health:
            return ClaudeLightStyle.directionalGradient(
                colors: [
                    Color.dynamic(light: Color(hex: "#1FAF9F"), dark: Color(hex: "#7BF0DA")),
                    Color.dynamic(light: Color(hex: "#0F766E"), dark: Color(hex: "#27B7A7"))
                ],
                colorScheme: colorScheme,
                lightColor: AppColorRoles.surfaceInteractive
            )
        case .physique:
            return ClaudeLightStyle.directionalGradient(
                colors: [
                    Color.dynamic(light: Color(hex: "#7667FF"), dark: Color(hex: "#C1B6FF")),
                    Color.dynamic(light: Color(hex: "#4F46E5"), dark: Color(hex: "#7C6DFF"))
                ],
                colorScheme: colorScheme,
                lightColor: AppColorRoles.surfaceInteractive
            )
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button {
                    if animateSelection {
                        withAnimation(AppMotion.standard) {
                            selectedTab = tab
                        }
                    } else {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selectedGradient(for: tab))
                                .matchedGeometryEffect(id: "measurements-selected-pill", in: selectedPillNamespace)
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.clear)
                        }

                        Text(tab.title)
                            .font(AppTypography.captionEmphasis)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.74)
                            .foregroundStyle(selectedTab == tab ? (colorScheme == .dark ? Color.white.opacity(0.96) : AppColorRoles.textPrimary) : AppColorRoles.textPrimary)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selectedTab == tab ? AppColorRoles.borderStrong : AppColorRoles.borderSubtle, lineWidth: selectedTab == tab ? 0.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityID)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColorRoles.surfaceChrome)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            ClaudeLightStyle.directionalGradient(
                                colors: [
                                    activeTint.opacity(colorScheme == .dark ? 0.10 : 0.08),
                                    .clear
                                ],
                                colorScheme: colorScheme,
                                lightColor: activeTint.opacity(0.04)
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColorRoles.borderStrong, lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .inset(by: 0.5)
                        .stroke(AppColorRoles.surfaceCanvas.opacity(0.32), lineWidth: 0.6)
                )
        )
        .frame(minHeight: 64)
        .fixedSize(horizontal: false, vertical: true)
        .animation(animateSelection ? AppMotion.standard : nil, value: selectedTab)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("measurements.tab.segmented")
    }
}
