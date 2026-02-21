import SwiftUI

/// Podstawowy styl przycisku akcentowego dla glownej akcji na ekranie.
struct AppPrimaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        AppSecondaryButtonStyle(cornerRadius: cornerRadius).makeBody(configuration: configuration)
    }
}

/// Pelny styl przycisku akcentowego dla kontrastowych akcji glownych.
struct AppAccentButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        AppCTAButtonStyle(size: .large, cornerRadius: cornerRadius).makeBody(configuration: configuration)
    }
}
