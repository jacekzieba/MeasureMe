import SwiftUI

// MARK: - Settings Section
 struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            VStack(spacing: 0) {
                content
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
}
