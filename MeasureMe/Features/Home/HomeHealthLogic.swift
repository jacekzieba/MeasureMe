import Foundation

extension HomeView {
    /// Thin wrapper that delegates to `HomeViewModel.fetchHealthKitData`.
    /// The ViewModel owns the resulting `latestBodyFat` / `latestLeanMass` state.
    func fetchHealthKitData() {
        viewModel.fetchHealthKitData(isSyncEnabled: isSyncEnabled, effects: effects)
    }
}
