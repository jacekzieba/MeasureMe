import SwiftUI

struct PhotoFormTagsSection: View {
    let title: String
    let tags: [PhotoTag]
    let accessibilityPrefix: String
    let tagBinding: (PhotoTag) -> Binding<Bool>
    @State private var showsAdvancedTags = false

    var body: some View {
        AppGlassCard(depth: .base) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)

                tagFlow(for: primaryTags)

                if !advancedTags.isEmpty {
                    DisclosureGroup(isExpanded: $showsAdvancedTags) {
                        tagFlow(for: advancedTags)
                            .padding(.top, AppSpacing.xs)
                    } label: {
                        Text(AppLocalization.string("Advanced area tags"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                    .tint(AppColorRoles.textSecondary)
                }
            }
        }
    }

    private var primaryTags: [PhotoTag] {
        let availablePrimary = tags.filter(\.isPrimaryPose)
        let resolvedPrimary = availablePrimary.isEmpty ? PhotoTag.primaryPoseTags : availablePrimary
        guard tags.contains(.wholeBody) else { return resolvedPrimary }
        return resolvedPrimary + [.wholeBody]
    }

    private var advancedTags: [PhotoTag] {
        tags.filter { $0.isLegacyAreaTag && $0 != .wholeBody }
    }

    private func tagFlow(for tags: [PhotoTag]) -> some View {
        FlowLayout(spacing: AppSpacing.xs) {
            ForEach(tags) { tag in
                Toggle(isOn: tagBinding(tag)) {
                    HStack(spacing: AppSpacing.xxs) {
                        if let kind = tag.metricKind {
                            kind.iconView(size: 14)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: tag.systemImage)
                                .font(AppTypography.captionEmphasis)
                                .frame(width: 14, height: 14)
                        }
                        Text(tag.title)
                    }
                }
                .toggleStyle(PhotoTagChipToggleStyle())
                .accessibilityIdentifier("\(accessibilityPrefix).tagToggle.\(tag.rawValue)")
            }
        }
    }
}

struct PhotoFormDateSection: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        AppGlassCard(depth: .base) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label(title, systemImage: "calendar.badge.clock")
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)

                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.appAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(title)
            }
        }
    }
}

struct CollapsibleMeasurementsSection<Content: View>: View {
    let title: String
    let filledCount: Int
    @Binding var isExpanded: Bool
    let toggleAccessibilityIdentifier: String
    let contentAccessibilityIdentifier: String
    let filledCountAccessibilityIdentifier: String
    @ViewBuilder let content: Content

    init(
        title: String,
        filledCount: Int,
        isExpanded: Binding<Bool>,
        toggleAccessibilityIdentifier: String,
        contentAccessibilityIdentifier: String,
        filledCountAccessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.filledCount = filledCount
        self._isExpanded = isExpanded
        self.toggleAccessibilityIdentifier = toggleAccessibilityIdentifier
        self.contentAccessibilityIdentifier = contentAccessibilityIdentifier
        self.filledCountAccessibilityIdentifier = filledCountAccessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        AppGlassCard(depth: .base) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Button {
                    withAnimation(AppMotion.standard) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(title)
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)

                            if filledCount > 0 {
                                Text(AppLocalization.string("photo.measurements.filled", filledCount))
                                    .font(AppTypography.microEmphasis)
                                    .foregroundStyle(Color.appAccent)
                                    .accessibilityIdentifier(filledCountAccessibilityIdentifier)
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.down")
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(AppMotion.standard, value: isExpanded)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(toggleAccessibilityIdentifier)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        content
                    }
                    .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(contentAccessibilityIdentifier)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
