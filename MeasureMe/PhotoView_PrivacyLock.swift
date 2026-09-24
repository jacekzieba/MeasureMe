import SwiftUI
import SwiftData
import UIKit

// MARK: - Privacy locked overlay

struct PhotoPrivacyLockedView: View {
    let onUnlock: () -> Void

    var body: some View {
        AppGlassCard(
            depth: .floating,
            cornerRadius: 18,
            tint: FeatureTheme.photos.strongTint,
            contentPadding: 18
        ) {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FeatureTheme.photos.accent)

                Text(AppLocalization.string("Photos locked"))
                    .font(AppTypography.headlineEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string("Unlock to view progress photos."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: onUnlock) {
                    Label(AppLocalization.string("Unlock photos"), systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                .accessibilityIdentifier("photos.privacy.unlock")
            }
        }
    }
}

// MARK: - Privacy guard for presented photo screens

/// Covers a presented photo screen (detail, full screen, compare, chooser, transformation card)
/// while the photo lock is on and the gate is locked.
///
/// The grid and the Home card blur their own tiles, but these screens are opened from them and
/// showed photos regardless: Home's Compare button sat outside the blurred area, and a sheet left
/// open when the app went to the background came back — and appeared in the app switcher — unlocked.
private struct PhotoPrivacyGuardModifier: ViewModifier {
    @ObservedObject private var photoPrivacyGate = PhotoPrivacyGate.shared
    @AppSetting(\.privacy.requireBiometricForPhotos) private var requireBiometricForPhotos: Bool = false
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .overlay {
                if !photoPrivacyGate.canDisplayPhotos(requireBiometric: requireBiometricForPhotos) {
                    ZStack(alignment: .topTrailing) {
                        AppColorRoles.surfaceCanvas
                            .ignoresSafeArea()

                        PhotoPrivacyLockedView {
                            Task { await photoPrivacyGate.unlock() }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // A full-screen cover cannot be swiped away, so there must be a way out
                        // that does not depend on unlocking.
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(AppLocalization.string("Close"))
                        .padding(8)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                photoPrivacyGate.lock()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                photoPrivacyGate.lock()
            }
    }
}

extension View {
    func photoPrivacyGuard() -> some View {
        modifier(PhotoPrivacyGuardModifier())
    }
}
