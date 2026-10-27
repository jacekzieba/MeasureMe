import SwiftUI

extension View {
    /// An invisible 1×1 element UI tests can find by `identifier`, for state that has no visible
    /// control of its own (which detail is open, which layout is active). Adds nothing outside
    /// test runs.
    @ViewBuilder
    func uiTestMarker(_ identifier: String) -> some View {
        if UITestArgument.isAnyTestMode {
            overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier(identifier)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}
