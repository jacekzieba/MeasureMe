import SwiftUI

struct IndicatorsSettingsSection: View {
    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showWHROnHome: Bool
    @Binding var showWaistRiskOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showABSIOnHome: Bool
    @Binding var showBodyShapeScoreOnHome: Bool
    @Binding var showCentralFatRiskOnHome: Bool
    @Binding var showPhysiqueSWR: Bool
    @Binding var showPhysiqueCWR: Bool
    @Binding var showPhysiqueSHR: Bool
    @Binding var showPhysiqueHWR: Bool
    @Binding var showPhysiqueBWR: Bool
    @Binding var showPhysiqueWHtR: Bool
    @Binding var showPhysiqueBodyFat: Bool
    @Binding var showPhysiqueRFM: Bool

    @State private var isHealthExpanded: Bool = false
    @State private var isPhysiqueExpanded: Bool = false

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Indicators"), systemImage: "slider.horizontal.3")

                disclosureRow(
                    title: AppLocalization.string("Health indicators"),
                    isExpanded: $isHealthExpanded
                ) {
                    healthIndicatorsContent
                }

                SettingsRowDivider()

                disclosureRow(
                    title: AppLocalization.string("Physique indicators"),
                    isExpanded: $isPhysiqueExpanded
                ) {
                    physiqueIndicatorsContent
                }
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private func disclosureRow<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.wrappedValue.toggle()
                Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                        .foregroundStyle(.white)
                }
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.top, 2)
            }
        }
    }

    private var healthIndicatorsContent: some View {
        Group {
            metricsGroupTitle("Core indicators")
            healthMetricToggle(AppLocalization.string("WHtR (Waist-to-Height Ratio)"), isOn: $showWHtROnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("RFM (Relative Fat Mass)"), isOn: $showRFMOnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("BMI (Body Mass Index)"), isOn: $showBMIOnHome)

            metricsGroupTitle("Body composition")
            healthMetricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showBodyFatOnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("Lean Body Mass"), isOn: $showLeanMassOnHome)

            metricsGroupTitle("Fat distribution")
            healthMetricToggle(AppLocalization.string("Waist-to-Hip Ratio"), isOn: $showWHROnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("Waist circumference"), isOn: $showWaistRiskOnHome)

            metricsGroupTitle("Risk signals")
            healthMetricToggle(AppLocalization.string("ABSI (technical)"), isOn: $showABSIOnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("Body Shape Risk"), isOn: $showBodyShapeScoreOnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("Central Fat Risk"), isOn: $showCentralFatRiskOnHome)
        }
    }

    private var physiqueIndicatorsContent: some View {
        Group {
            metricsGroupTitle("Proportion ratios")
            physiqueMetricToggle(AppLocalization.string("Shoulder-to-Waist Ratio"), isOn: $showPhysiqueSWR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Chest-to-Waist Ratio"), isOn: $showPhysiqueCWR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Hip-to-Waist Ratio"), isOn: $showPhysiqueHWR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Bust-to-Waist Ratio"), isOn: $showPhysiqueBWR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Shoulder-to-Hip Ratio"), isOn: $showPhysiqueSHR)

            metricsGroupTitle("Hybrid metrics")
            physiqueMetricToggle(AppLocalization.string("Waist-Height Ratio"), isOn: $showPhysiqueWHtR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showPhysiqueBodyFat)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Relative Fat Mass"), isOn: $showPhysiqueRFM)
        }
    }

    private func metricsGroupTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func healthMetricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color.appAccent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private func physiqueMetricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color(hex: "#14B8A6"))
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
}

struct HealthIndicatorsSettingsSection: View {
    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showWHROnHome: Bool
    @Binding var showWaistRiskOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showABSIOnHome: Bool
    @Binding var showBodyShapeScoreOnHome: Bool
    @Binding var showCentralFatRiskOnHome: Bool

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Health indicators"), systemImage: "heart.text.square.fill")
                VStack(spacing: 0) {
                    metricsGroupTitle("Core indicators")
                    metricToggle(AppLocalization.string("WHtR (Waist-to-Height Ratio)"), isOn: $showWHtROnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("RFM (Relative Fat Mass)"), isOn: $showRFMOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("BMI (Body Mass Index)"), isOn: $showBMIOnHome)

                    metricsGroupTitle("Body composition")
                    metricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showBodyFatOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Lean Body Mass"), isOn: $showLeanMassOnHome)

                    metricsGroupTitle("Fat distribution")
                    metricToggle(AppLocalization.string("Waist-to-Hip Ratio"), isOn: $showWHROnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Waist circumference"), isOn: $showWaistRiskOnHome)

                    metricsGroupTitle("Risk signals")
                    metricToggle(AppLocalization.string("ABSI (technical)"), isOn: $showABSIOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Body Shape Risk"), isOn: $showBodyShapeScoreOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Central Fat Risk"), isOn: $showCentralFatRiskOnHome)
                }
                .padding(.top, 6)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private func metricsGroupTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color.appAccent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
}

struct PhysiqueIndicatorsSettingsSection: View {
    @Binding var showPhysiqueSWR: Bool
    @Binding var showPhysiqueCWR: Bool
    @Binding var showPhysiqueSHR: Bool
    @Binding var showPhysiqueHWR: Bool
    @Binding var showPhysiqueBWR: Bool
    @Binding var showPhysiqueWHtR: Bool
    @Binding var showPhysiqueBodyFat: Bool
    @Binding var showPhysiqueRFM: Bool

    var body: some View {
        Section {
            SettingsCard(tint: Color(hex: "#14B8A6").opacity(0.16)) {
                SettingsCardHeader(title: AppLocalization.string("Physique indicators"), systemImage: "figure.strengthtraining.traditional")
                VStack(spacing: 0) {
                    metricsGroupTitle("Proportion ratios")
                    metricToggle(AppLocalization.string("Shoulder-to-Waist Ratio"), isOn: $showPhysiqueSWR)
                    rowDivider
                    metricToggle(AppLocalization.string("Chest-to-Waist Ratio"), isOn: $showPhysiqueCWR)
                    rowDivider
                    metricToggle(AppLocalization.string("Hip-to-Waist Ratio"), isOn: $showPhysiqueHWR)
                    rowDivider
                    metricToggle(AppLocalization.string("Bust-to-Waist Ratio"), isOn: $showPhysiqueBWR)
                    rowDivider
                    metricToggle(AppLocalization.string("Shoulder-to-Hip Ratio"), isOn: $showPhysiqueSHR)

                    metricsGroupTitle("Hybrid metrics")
                    metricToggle(AppLocalization.string("Waist-Height Ratio"), isOn: $showPhysiqueWHtR)
                    rowDivider
                    metricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showPhysiqueBodyFat)
                    rowDivider
                    metricToggle(AppLocalization.string("Relative Fat Mass"), isOn: $showPhysiqueRFM)
                }
                .padding(.top, 6)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private func metricsGroupTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color(hex: "#14B8A6"))
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
}
