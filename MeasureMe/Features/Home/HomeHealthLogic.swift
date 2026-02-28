import Foundation

extension HomeView {
    func fetchHealthKitData() {
        guard isSyncEnabled else {
            latestBodyFat = nil
            latestLeanMass = nil
            return
        }

        Task {
            do {
                let composition = try await HealthKitManager.shared.fetchLatestBodyCompositionCached()
                await MainActor.run {
                    latestBodyFat = composition.bodyFat
                    latestLeanMass = composition.leanMass
                }
            } catch {
                AppLog.debug("⚠️ Error fetching HealthKit data: \(error.localizedDescription)")
                await MainActor.run {
                    latestBodyFat = nil
                    latestLeanMass = nil
                }
            }
        }
    }
}
