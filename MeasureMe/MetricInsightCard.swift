import SwiftUI

struct MetricInsightCard: View {
    let text: String
    let compact: Bool
    let isLoading: Bool
    var onRefresh: (() -> Void)? = nil

    @State private var shimmerPhase: CGFloat = 0
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let collapsedLineLimit = 4
    private var minimumCompactHeight: CGFloat? {
        compact ? 74 : nil
    }

    private var compactLineLimit: Int? {
        guard compact, !dynamicTypeSize.isAccessibilitySize else { return nil }
        return 2
    }

    private var canExpand: Bool {
        !compact && !isLoading && text.count > 220
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(compact ? AppTypography.iconSmall : AppTypography.iconSmall)
                .foregroundStyle(AppColorRoles.accentPrimary)
                .padding(8)
                .background(AppColorRoles.accentPrimary.opacity(0.12))
                .clipShape(Circle())
                .symbolEffect(.pulse, isActive: isLoading)

            VStack(alignment: .leading, spacing: 4) {
                if isLoading {
                    shimmerBlock(width: .infinity, height: compact ? 12 : 14)
                    shimmerBlock(width: 180, height: compact ? 12 : 14)
                    if !compact {
                        shimmerBlock(width: 140, height: 14)
                    }
                } else {
                    Text(text)
                        .font(compact ? AppTypography.microEmphasis : AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(compactLineLimit ?? (canExpand && !isExpanded ? collapsedLineLimit : nil))
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(compact ? "insight.card.text.compact" : "insight.card.text.detail")

                    if canExpand {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Text(AppLocalization.aiString(isExpanded ? "Show less" : "Show more"))
                                .font(AppTypography.microEmphasis)
                                .foregroundStyle(AppColorRoles.accentPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("insight.card.expand")
                    }
                }

                HStack {
                    Text(isLoading
                         ? AppLocalization.aiString("Generating insight...")
                         : AppLocalization.aiString("AI generated"))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)

                    if let onRefresh, !isLoading {
                        Spacer()
                        Button {
                            onRefresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }
                        .accessibilityLabel(AppLocalization.aiString("Refresh insight"))
                        .accessibilityIdentifier("insight.card.refresh")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minimumCompactHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .fill(AppColorRoles.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .stroke(
                    colorScheme == .dark
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    AppColorRoles.borderStrong,
                                    AppColorRoles.borderSubtle
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(AppColorRoles.borderSubtle),
                    lineWidth: 1
                )
        )
        .shadow(color: (colorScheme == .dark ? Color.black : AppColorRoles.shadowSoft).opacity(colorScheme == .dark ? 0.16 : 0.10), radius: 10, x: 0, y: 4)
        .onChange(of: isLoading) {
            if isLoading {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    shimmerPhase = 1
                }
            } else {
                shimmerPhase = 0
            }
        }
        .onAppear {
            if isLoading {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    shimmerPhase = 1
                }
            }
        }
        .onChange(of: text) { _, _ in
            isExpanded = false
        }
    }

    @ViewBuilder
    private func shimmerBlock(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppColorRoles.textSecondary.opacity(0.08 + 0.08 * shimmerPhase))
            .frame(maxWidth: width == .infinity ? .infinity : width, alignment: .leading)
            .frame(height: height)
    }
}
