import SwiftUI

/// Maskotka aplikacji — „Miara". Jedna postać w 10 pozach, mapowanych
/// semantycznie do momentów emocjonalnych w UI.
enum MeasureBuddy: String, CaseIterable, Sendable {
    case welcome
    case ai
    case reminder
    case streak
    case thumbs
    case settings
    case summary
    case goals
    case celebration
    case success

    var assetName: String { "mb_\(rawValue)" }
}

/// Imię maskotki używane w copy. Trzymane w jednym miejscu, by łatwo zmienić.
enum MeasureBuddyName {
    static let display = "Miara"
}

// MARK: - Widok pojedynczej maskotki

struct MeasureBuddyView: View {
    let pose: MeasureBuddy
    var size: CGFloat = 96
    var idleAnimation: Bool = true

    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathingActive = false

    private var shouldAnimate: Bool {
        idleAnimation && AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    var body: some View {
        Image(pose.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(breathingActive ? 1.02 : 1.0)
            .rotationEffect(.degrees(breathingActive ? 1 : -1))
            .accessibilityHidden(true)
            .onAppear {
                guard shouldAnimate else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    breathingActive = true
                }
            }
            .onChange(of: shouldAnimate) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                        breathingActive = true
                    }
                } else {
                    withAnimation(.linear(duration: 0)) {
                        breathingActive = false
                    }
                }
            }
    }
}

// MARK: - Speech bubble (maskotka po lewej + dymek po prawej)

struct MeasureBuddySpeechBubble<Content: View>: View {
    let pose: MeasureBuddy
    var buddySize: CGFloat = 88
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MeasureBuddyView(pose: pose, size: buddySize)

            content()
                .padding(.vertical, 12)
                .padding(.horizontal, AppSpacing.smmd)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Pomocnicze mapowanie sygnałów Home → poza

extension MeasureBuddy {
    /// Mapowanie kontekstów Home hero pulse → poza maskotki.
    /// Zwraca `nil` dla codziennych sygnałów, by nie zaszumiać UI.
    static func forHeroSignal(_ kind: HeroPulseSignalKind) -> MeasureBuddy? {
        switch kind {
        case .streakMilestone: return .streak
        case .goalAchieved: return .celebration
        case .goalNearComplete: return .goals
        case .returnNudge: return .reminder
        case .fresh, .streakActive, .streakRisk, .trendHighlight: return nil
        }
    }
}
