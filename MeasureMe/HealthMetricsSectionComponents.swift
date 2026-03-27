import SwiftUI

struct HealthMetricsSectionCard<Content: View>: View {
    private let healthAccent = HealthIndicatorPalette.accent
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Nagłówek sekcji
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(healthAccent)
                
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }
            
            // Metryki
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColorRoles.surfacePrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [healthAccent.opacity(0.20), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(healthAccent.opacity(0.24), lineWidth: 1)
        )
    }
}

// MARK: - Health Metric Row

struct HealthMetricRow<Destination: View>: View {
    private let rowFill = HealthIndicatorPalette.rowBackground
    let title: String
    let value: String
    let category: String
    let categoryColor: String
    let destination: Destination
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                // Lewa strona - tytuł
                    VStack(alignment: .leading, spacing: 4) {
                        ViewThatFits(in: .vertical) {
                            Text(title)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .lineLimit(1)
                            Text(title)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    
                    Text(category)
                        .font(AppTypography.micro)
                        .foregroundStyle(Color.bestAccessibleTextColor(onHex: categoryColor))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: categoryColor), in: RoundedRectangle(cornerRadius: 4))
                }
                
                Spacer()
                
                // Prawa strona - wartość
                HStack(spacing: 4) {
                    Text(value)
                        .font(AppTypography.metricValue)
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textPrimary)
                    
                    Image(systemName: "chevron.right")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textTertiary)
                }
            }
            .frame(minHeight: 44)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Health Metrics - Complete") {
    NavigationStack {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    HealthMetricsSection(
                        latestWaist: 85.0,
                        latestHeight: 180.0,
                        latestWeight: 75.0,
                        latestBodyFat: 18.5,
                        latestLeanMass: 61.1
                    )
                }
                .padding()
            }
        }
    }
    .onAppear {
        AppSettingsStore.shared.set(\.profile.userAge, 30)
        AppSettingsStore.shared.set(\.profile.userGender, "male")
    }
}

#Preview("Health Metrics - Missing Data") {
    NavigationStack {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    HealthMetricsSection(
                        latestWaist: nil,
                        latestHeight: 180.0,
                        latestWeight: nil,
                        latestBodyFat: nil,
                        latestLeanMass: nil
                    )
                }
                .padding()
            }
        }
    }
}

#Preview("Health Metrics - No Metrics Enabled") {
    NavigationStack {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    HealthMetricsSection(
                        latestWaist: 85.0,
                        latestHeight: 180.0,
                        latestWeight: 75.0,
                        latestBodyFat: 18.5,
                        latestLeanMass: 61.1
                    )
                }
                .padding()
            }
        }
    }
    .onAppear {
        AppSettingsStore.shared.set(\.indicators.showBMIOnHome, false)
        AppSettingsStore.shared.set(\.indicators.showWHtROnHome, false)
        AppSettingsStore.shared.set(\.indicators.showRFMOnHome, false)
        AppSettingsStore.shared.set(\.indicators.showBodyFatOnHome, false)
        AppSettingsStore.shared.set(\.indicators.showLeanMassOnHome, false)
        AppSettingsStore.shared.set(\.indicators.showABSIOnHome, false)
        AppSettingsStore.shared.set(\.indicators.showBodyShapeScoreOnHome, false)
        AppSettingsStore.shared.set(\.indicators.showCentralFatRiskOnHome, false)
        AppSettingsStore.shared.set(\.indicators.showWHROnHome, false)
        AppSettingsStore.shared.set(\.indicators.showWaistRiskOnHome, false)
    }
}
