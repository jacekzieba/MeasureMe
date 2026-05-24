import SwiftUI
import UIKit

struct ExperienceSettingsDetailView: View {
    @Binding var appAppearance: String
    @Binding var animationsEnabled: Bool
    @Binding var hapticsEnabled: Bool
    private let theme = FeatureTheme.settings

    @State private var currentIconName: String? = UIApplication.shared.alternateIconName

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Appearance, animations and haptics"), theme: .settings) {
            Section {
                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("Appearance"), systemImage: "circle.lefthalf.filled.inverse")

                    Picker(AppLocalization.string("Appearance"), selection: $appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .glassSegmentedControl(tint: theme.accent)

                    SettingsRowDivider()

                    SettingsCardHeader(title: AppLocalization.string("App icon"), systemImage: "app.badge")
                    HStack(spacing: 12) {
                        appIconOption(
                            title: AppLocalization.string("Default"),
                            previewAsset: "AppIconDefaultPreview",
                            iconName: nil
                        )
                        appIconOption(
                            title: AppLocalization.string("Old"),
                            previewAsset: "AppIconOldPreview",
                            iconName: "AppIconFrame1"
                        )
                    }

                    SettingsRowDivider()

                    SettingsCardHeader(title: AppLocalization.string("Animations and haptics"), systemImage: "apple.haptics.and.music.note")
                    SettingsToggleRow(isOn: $animationsEnabled, accent: theme.accent) {
                        Text(AppLocalization.string("Animations"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }

                    SettingsRowDivider()

                    SettingsToggleRow(isOn: $hapticsEnabled, accent: theme.accent) {
                        Text(AppLocalization.string("Haptics"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)
        }
        .onAppear {
            currentIconName = UIApplication.shared.alternateIconName
        }
    }

    @ViewBuilder
    private func appIconOption(title: String, previewAsset: String, iconName: String?) -> some View {
        let isSelected = currentIconName == iconName
        Button {
            setAppIcon(iconName)
        } label: {
            VStack(spacing: 8) {
                iconPreview(previewAsset: previewAsset, iconName: iconName)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(isSelected ? theme.accent : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                    )
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func iconPreview(previewAsset: String, iconName: String?) -> some View {
        if let image = UIImage(named: previewAsset) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let iconName, let image = UIImage(named: iconName) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Rectangle().fill(AppColorRoles.surfacePrimary)
        }
    }

    private func setAppIcon(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if error == nil {
                if hapticsEnabled { Haptics.light() }
                Task { @MainActor in
                    currentIconName = UIApplication.shared.alternateIconName
                }
            }
        }
        currentIconName = name
    }
}
