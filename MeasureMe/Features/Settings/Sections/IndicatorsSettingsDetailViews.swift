import SwiftUI

struct IndicatorsSettingsDetailView: View {
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

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                IndicatorsSettingsSection(
                    showWHtROnHome: $showWHtROnHome,
                    showRFMOnHome: $showRFMOnHome,
                    showBMIOnHome: $showBMIOnHome,
                    showWHROnHome: $showWHROnHome,
                    showWaistRiskOnHome: $showWaistRiskOnHome,
                    showBodyFatOnHome: $showBodyFatOnHome,
                    showLeanMassOnHome: $showLeanMassOnHome,
                    showABSIOnHome: $showABSIOnHome,
                    showBodyShapeScoreOnHome: $showBodyShapeScoreOnHome,
                    showCentralFatRiskOnHome: $showCentralFatRiskOnHome,
                    showPhysiqueSWR: $showPhysiqueSWR,
                    showPhysiqueCWR: $showPhysiqueCWR,
                    showPhysiqueSHR: $showPhysiqueSHR,
                    showPhysiqueHWR: $showPhysiqueHWR,
                    showPhysiqueBWR: $showPhysiqueBWR,
                    showPhysiqueWHtR: $showPhysiqueWHtR,
                    showPhysiqueBodyFat: $showPhysiqueBodyFat,
                    showPhysiqueRFM: $showPhysiqueRFM
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Indicators"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct HealthIndicatorsSettingsDetailView: View {
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
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                HealthIndicatorsSettingsSection(
                    showWHtROnHome: $showWHtROnHome,
                    showRFMOnHome: $showRFMOnHome,
                    showBMIOnHome: $showBMIOnHome,
                    showWHROnHome: $showWHROnHome,
                    showWaistRiskOnHome: $showWaistRiskOnHome,
                    showBodyFatOnHome: $showBodyFatOnHome,
                    showLeanMassOnHome: $showLeanMassOnHome,
                    showABSIOnHome: $showABSIOnHome,
                    showBodyShapeScoreOnHome: $showBodyShapeScoreOnHome,
                    showCentralFatRiskOnHome: $showCentralFatRiskOnHome
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Health indicators"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct PhysiqueIndicatorsSettingsDetailView: View {
    @Binding var showPhysiqueSWR: Bool
    @Binding var showPhysiqueCWR: Bool
    @Binding var showPhysiqueSHR: Bool
    @Binding var showPhysiqueHWR: Bool
    @Binding var showPhysiqueBWR: Bool
    @Binding var showPhysiqueWHtR: Bool
    @Binding var showPhysiqueBodyFat: Bool
    @Binding var showPhysiqueRFM: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                PhysiqueIndicatorsSettingsSection(
                    showPhysiqueSWR: $showPhysiqueSWR,
                    showPhysiqueCWR: $showPhysiqueCWR,
                    showPhysiqueSHR: $showPhysiqueSHR,
                    showPhysiqueHWR: $showPhysiqueHWR,
                    showPhysiqueBWR: $showPhysiqueBWR,
                    showPhysiqueWHtR: $showPhysiqueWHtR,
                    showPhysiqueBodyFat: $showPhysiqueBodyFat,
                    showPhysiqueRFM: $showPhysiqueRFM
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Physique indicators"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
