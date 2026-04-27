import SwiftUI

struct HomeDashboardBoard<Content: View>: View {
    let items: [HomeModuleLayoutItem]
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let content: (HomeModuleLayoutItem) -> Content

    init(
        items: [HomeModuleLayoutItem],
        columns: Int,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping (HomeModuleLayoutItem) -> Content
    ) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HomeDashboardBoardLayout(items: items, columns: columns, spacing: spacing) {
            ForEach(items) { item in
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .layoutValue(key: HomeDashboardItemKey.self, value: item)
            }
        }
    }
}

private struct HomeDashboardItemKey: LayoutValueKey {
    static let defaultValue = HomeModuleLayoutItem(
        kind: .summaryHero,
        isVisible: true,
        size: .small,
        row: 0,
        column: 0
    )
}

private struct HomeDashboardBoardLayout: Layout {
    let items: [HomeModuleLayoutItem]
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let width = proposal.width, width > 0 else { return .zero }
        let resolved = resolvedLayout(for: width, subviews: subviews)
        return CGSize(width: width, height: resolved.contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let resolved = resolvedLayout(for: bounds.width, subviews: subviews)

        for (index, subview) in subviews.enumerated() where index < items.count {
            let item = items[index]
            guard let frame = resolved.frames[item.id] else { continue }
            let placedOrigin = CGPoint(
                x: bounds.minX + frame.minX,
                y: bounds.minY + frame.minY
            )
            subview.place(
                at: placedOrigin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func dashboardMetrics(for width: CGFloat) -> DashboardMetrics {
        let totalSpacing = CGFloat(max(columns - 1, 0)) * spacing
        let cellWidth = (width - totalSpacing) / CGFloat(columns)
        let rowHeight = min(max(cellWidth * 0.78, 120), 156)
        return DashboardMetrics(cellWidth: cellWidth, rowHeight: rowHeight)
    }

    private func resolvedLayout(for width: CGFloat, subviews: Subviews) -> ResolvedLayout {
        let metrics = dashboardMetrics(for: width)
        let normalizedItems = items.map { item in
            var next = item
            next.size = item.size.normalized(for: columns)
            return next
        }
        let rowCount = max(
            normalizedItems.map { $0.row + $0.size.rowSpan }.max() ?? 0,
            1
        )
        var rowHeights = Array(repeating: metrics.rowHeight, count: rowCount)

        for (index, item) in normalizedItems.enumerated() where index < subviews.count {
            let endRow = min(item.row + item.size.rowSpan, rowHeights.count)
            guard item.row < endRow else { continue }
            let frameWidth = frameWidth(for: item.size, metrics: metrics)
            let measuredHeight = max(
                ceil(
                    subviews[index]
                        .sizeThatFits(ProposedViewSize(width: frameWidth, height: nil))
                        .height
                ),
                minimumHeight(for: item, metrics: metrics)
            )
            let currentHeight = totalHeight(
                rows: item.row..<endRow,
                rowHeights: rowHeights
            )

            if measuredHeight > currentHeight {
                rowHeights[endRow - 1] += measuredHeight - currentHeight
            }
        }

        var rowOrigins = Array(repeating: CGFloat.zero, count: rowHeights.count + 1)
        for index in 1..<rowOrigins.count {
            rowOrigins[index] = rowOrigins[index - 1] + rowHeights[index - 1] + spacing
        }

        let frames = Dictionary(uniqueKeysWithValues: normalizedItems.map { item in
            let endRow = min(item.row + item.size.rowSpan, rowHeights.count)
            let width = frameWidth(for: item.size, metrics: metrics)
            let minX = CGFloat(item.column) * (metrics.cellWidth + spacing)
            let minY = rowOrigins[item.row]
            let height = max(rowOrigins[endRow] - rowOrigins[item.row] - spacing, 0)
            return (item.kind, CGRect(x: minX, y: minY, width: width, height: height))
        })

        let contentHeight = frames.values.map(\.maxY).max() ?? 0
        return ResolvedLayout(frames: frames, contentHeight: contentHeight)
    }

    private func minimumHeight(for item: HomeModuleLayoutItem, metrics: DashboardMetrics) -> CGFloat {
        let nominalHeight = totalHeight(
            rows: 0..<item.size.rowSpan,
            rowHeights: Array(repeating: metrics.rowHeight, count: max(item.size.rowSpan, 1))
        )

        switch item.kind {
        case .summaryHero:
            return max(nominalHeight, columns > 2 ? 176 : 188)
        case .quickActions:
            return nominalHeight
        case .keyMetrics:
            return max(nominalHeight, columns > 2 ? 252 : 274)
        case .recentPhotos:
            return max(nominalHeight, columns > 2 ? 240 : 268)
        case .healthSummary:
            return max(nominalHeight, columns > 2 ? 168 : 180)
        case .activationHub:
            return max(nominalHeight, columns > 2 ? 190 : 210)
        case .setupChecklist:
            return max(nominalHeight, columns > 2 ? 176 : 188)
        }
    }

    private func frameWidth(for size: HomeModuleSize, metrics: DashboardMetrics) -> CGFloat {
        CGFloat(size.columnSpan) * metrics.cellWidth + CGFloat(size.columnSpan - 1) * spacing
    }

    private func totalHeight(rows: Range<Int>, rowHeights: [CGFloat]) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        let height = rowHeights[rows].reduce(0, +)
        let internalSpacing = CGFloat(max(rows.count - 1, 0)) * spacing
        return height + internalSpacing
    }

    private struct DashboardMetrics {
        let cellWidth: CGFloat
        let rowHeight: CGFloat
    }

    private struct ResolvedLayout {
        let frames: [HomeModuleKind: CGRect]
        let contentHeight: CGFloat
    }
}

struct HomeWidgetCard<Content: View>: View {
    let tint: Color
    let depth: AppGlassDepth
    let contentPadding: CGFloat
    let accessibilityIdentifier: String?
    @ViewBuilder let content: Content

    init(
        tint: Color = FeatureTheme.home.softTint,
        depth: AppGlassDepth = .elevated,
        contentPadding: CGFloat = 14,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.depth = depth
        self.contentPadding = contentPadding
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        AppGlassCard(
            depth: depth,
            cornerRadius: 24,
            tint: tint,
            contentPadding: contentPadding
        ) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let accessibilityIdentifier {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityIdentifier(accessibilityIdentifier)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct HomeQuickActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(AppTypography.iconLarge)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                ClaudeLightStyle.directionalGradient(
                                    colors: colorScheme == .dark
                                        ? [
                                            tint.opacity(0.24),
                                            tint.opacity(0.12)
                                        ]
                                        : [
                                            Color(hex: "#F2F5F7").opacity(0.98),
                                            Color(hex: "#EAEFF3").opacity(0.96),
                                            Color(hex: "#E1E7EC").opacity(0.92)
                                        ],
                                    colorScheme: colorScheme,
                                    lightColor: AppColorRoles.surfaceSecondary
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        colorScheme == .dark
                                            ? Color.white.opacity(0.14)
                                            : AppColorRoles.borderSubtle,
                                        lineWidth: 1
                                    )
                            )
                    )

                Text(title)
                    .font(AppTypography.buttonLabel)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .minimumScaleFactor(0.85)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? AnyShapeStyle(AppColorRoles.surfaceInteractive)
                            : AnyShapeStyle(
                                AppColorRoles.surfacePrimary
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? AnyShapeStyle(
                                        RadialGradient(
                                            colors: [
                                                tint.opacity(0.10),
                                                .clear
                                            ],
                                            center: .topLeading,
                                            startRadius: 8,
                                            endRadius: 110
                                        )
                                    )
                                    : AnyShapeStyle(Color.white.opacity(0.18))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableTileStyle())
    }
}
