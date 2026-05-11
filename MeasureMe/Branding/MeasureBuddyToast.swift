import SwiftUI

extension Notification.Name {
    /// Wysyłane po pomyślnym zapisie pomiaru przez QuickAdd lub similar flow.
    /// Wartość `userInfo["title"]` (opcjonalna) nadpisuje domyślny tekst toastu.
    static let measureBuddyDidSaveMeasurement = Notification.Name("measureBuddyDidSaveMeasurement")
}

/// Globalny toast „Miary" pokazywany po zapisie pomiaru. Subskrybuje
/// `Notification.Name.measureBuddyDidSaveMeasurement` i auto‑hide po 1.6 s.
struct MeasureBuddyToastOverlay: ViewModifier {
    @State private var isVisible = false
    @State private var message: String = ""
    @State private var dismissTask: Task<Void, Never>?

    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isVisible {
                    HStack(spacing: 12) {
                        MeasureBuddyView(pose: .success, size: 48, idleAnimation: false)
                        Text(message)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColorRoles.surfaceInteractive)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.appAccent.opacity(0.32), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    )
                    .padding(.bottom, 28)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(message)
                }
            }
            .animation(shouldAnimate ? AppMotion.toastIn : .none, value: isVisible)
            .onReceive(NotificationCenter.default.publisher(for: .measureBuddyDidSaveMeasurement)) { note in
                let custom = note.userInfo?["title"] as? String
                show(message: custom ?? defaultMessage)
            }
    }

    private var defaultMessage: String {
        let template = AppLocalization.systemString("Saved! — %@")
        return String(format: template, MeasureBuddyName.display)
    }

    private func show(message: String) {
        dismissTask?.cancel()
        self.message = message
        isVisible = true

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            isVisible = false
        }
    }
}

extension View {
    /// Montuje globalny toast „Miary" reagujący na
    /// `Notification.Name.measureBuddyDidSaveMeasurement`.
    func measureBuddyToast() -> some View {
        modifier(MeasureBuddyToastOverlay())
    }
}
