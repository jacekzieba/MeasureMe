import SwiftUI

struct ExperienceSettingsDetailView: View {
    @Binding var animationsEnabled: Bool
    @Binding var hapticsEnabled: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.white.opacity(0.08)) {
                        SettingsCardHeader(title: AppLocalization.string("Animations and haptics"), systemImage: "apple.haptics.and.music.note")
                        Toggle(isOn: $animationsEnabled) {
                            Text(AppLocalization.string("Animations"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: animationsEnabled) { _, _ in Haptics.selection() }
                        .frame(minHeight: 44)

                        SettingsRowDivider()

                        Toggle(isOn: $hapticsEnabled) {
                            Text(AppLocalization.string("Haptics"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: hapticsEnabled) { _, _ in Haptics.selection() }
                        .frame(minHeight: 44)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Animations and haptics"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
