import SwiftUI

struct WhyItMattersItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

struct WhyItMattersCard: View {
    let items: [WhyItMattersItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Why It Matters"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.icon)
                            .foregroundStyle(Color(hex: "#FCA311"))
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(.white)
                            Text(item.description)
                                .font(AppTypography.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
