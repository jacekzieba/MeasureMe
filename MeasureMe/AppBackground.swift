// AppBackground.swift
//
// **AppBackground**
// Root background layer painted behind every screen in the app.
//
// **Responsibilities:**
// - Solid surface canvas using the active color-role token
// - Dark-mode-only diagonal gradient (navy → black) for visual depth
//
// **Why a separate view, not a `.background()` modifier on RootView:**
// The gradient is app-wide and used by Home, Settings, Onboarding, etc. Wrapping
// it in its own view keeps `RootView` focused on routing and makes it trivial to
// swap the background during a redesign without touching every screen.
//
import SwiftUI

/// Full-bleed background used as the bottom layer of every screen.
///
/// In dark mode a diagonal gradient is layered on top of the surface canvas to
/// create depth; in light mode the canvas alone is used (no gradient overlay).
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Base surface — the lowest visual layer, always painted.
            AppColorRoles.surfaceCanvas
                .ignoresSafeArea()

            // Dark-mode-only accent gradient. The app intentionally keeps
            // a flat appearance in light mode for readability and contrast.
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color.appNavy,
                        Color.appBlack
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }
}
