import SwiftUI
import SwiftData

struct HomeCompareChooserOnDemandSheet: View {
    let initialOlderPhoto: PhotoEntry?
    let initialNewerPhoto: PhotoEntry?
    let onCompareSelected: (PhotoEntry, PhotoEntry) -> Void

    @Query(sort: [SortDescriptor(\PhotoEntry.date, order: .reverse)])
    private var photos: [PhotoEntry]

    var body: some View {
        HomeCompareChooserSheet(
            photos: photos,
            initialOlderPhoto: initialOlderPhoto,
            initialNewerPhoto: initialNewerPhoto,
            onCompareSelected: onCompareSelected
        )
    }
}

struct HomeCompareChooserSheet: View {
    @Environment(\.dismiss) private var dismiss

    let photos: [PhotoEntry]
    let initialOlderPhoto: PhotoEntry?
    let initialNewerPhoto: PhotoEntry?
    let preferredSlot: CompareChooserSlot
    let onSelectionChanged: ((PhotoEntry, PhotoEntry) -> Void)?
    let onCompareSelected: (PhotoEntry, PhotoEntry) -> Void

    @State private var selectedOlderPhoto: PhotoEntry?
    @State private var selectedNewerPhoto: PhotoEntry?
    @State private var focusedSlot: CompareChooserSlot
    @State private var selectedRange: DateRange = .all
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
    @State private var customEndDate: Date = AppClock.now
    @State private var selectedTags: Set<PhotoTag> = []
    @State private var hasUserModifiedSelection = false

    private let photosTheme = FeatureTheme.photos
    private let isUITestMode = UITestArgument.isPresent(.mode)

    private var availableRanges: [DateRange] {
        [.all, .last30Days, .last90Days, .custom]
    }

    private var filteredPhotos: [PhotoEntry] {
        photos.filter { photo in
            guard let start = selectedRange.startDate(customStart: customStartDate),
                  let end = selectedRange.endDate(customEnd: customEndDate) else {
                return matchesTags(photo)
            }
            return photo.date >= start && photo.date <= end && matchesTags(photo)
        }
    }

    private var availableTags: [PhotoTag] {
        let tags = Set(photos.flatMap(\.tags))
        return PhotoTag.allCases.filter { tags.contains($0) }
    }

    private var suggestedPair: PhotoComparePairSuggestion? {
        suggestedPhotoComparePair(from: filteredPhotos)
    }

    private var compareEnabled: Bool {
        selectedOlderPhoto != nil && selectedNewerPhoto != nil
    }

    private var selectionSummary: String {
        guard let older = selectedOlderPhoto, let newer = selectedNewerPhoto else {
            return AppLocalization.string("Photos make progress easier to notice.")
        }
        let days = max(Calendar.current.dateComponents([.day], from: older.date, to: newer.date).day ?? 0, 0)
        return AppLocalization.plural("compare.days.apart", days)
    }

    init(
        photos: [PhotoEntry],
        initialOlderPhoto: PhotoEntry? = nil,
        initialNewerPhoto: PhotoEntry? = nil,
        preferredSlot: CompareChooserSlot = .newer,
        onSelectionChanged: ((PhotoEntry, PhotoEntry) -> Void)? = nil,
        onCompareSelected: @escaping (PhotoEntry, PhotoEntry) -> Void
    ) {
        self.photos = photos
        self.initialOlderPhoto = initialOlderPhoto
        self.initialNewerPhoto = initialNewerPhoto
        self.preferredSlot = preferredSlot
        self.onSelectionChanged = onSelectionChanged
        self.onCompareSelected = onCompareSelected
        _focusedSlot = State(initialValue: preferredSlot)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(topHeight: 320, tint: photosTheme.strongTint, showsSpotlight: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("\(filteredPhotos.count)")
                            .font(.system(size: 1))
                            .accessibilityIdentifier("home.compare.filteredCount")
                            .frame(width: 1, height: 1)
                            .opacity(0.001)

                        if isUITestMode {
                            Button(AppLocalization.string("home.compare.chooser.uihook")) {
                                guard let suggestedPair else { return }
                                onCompareSelected(suggestedPair.older, suggestedPair.newer)
                                dismiss()
                            }
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .frame(width: 1, height: 1)
                            .clipped()
                            .accessibilityIdentifier("home.compare.selectTwoHook")
                        }

                        pairHeader

                        Button {
                            confirmCompare()
                        } label: {
                            Text(AppLocalization.string("Compare"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                        .disabled(!compareEnabled)
                        .accessibilityIdentifier("home.compare.confirm")

                        filterSection
                        photoGrid
                    }
                    .padding(16)
                }
            }
            .navigationTitle(AppLocalization.string("home.compare.chooser.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColorRoles.surfaceChrome, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let initialOlderPhoto, let initialNewerPhoto {
                    selectedOlderPhoto = initialOlderPhoto
                    selectedNewerPhoto = initialNewerPhoto
                } else if let suggestedPair {
                    selectedOlderPhoto = suggestedPair.older
                    selectedNewerPhoto = suggestedPair.newer
                }
            }
            .onChange(of: selectedRange) { _, _ in
                sanitizeSelection()
            }
            .onChange(of: customStartDate) { _, _ in
                sanitizeSelection()
            }
            .onChange(of: customEndDate) { _, _ in
                sanitizeSelection()
            }
            .onChange(of: selectedTags) { _, _ in
                sanitizeSelection()
            }
            .onChange(of: selectedOlderPhoto?.persistentModelID) { _, _ in
                publishSelectionChange()
            }
            .onChange(of: selectedNewerPhoto?.persistentModelID) { _, _ in
                publishSelectionChange()
            }
        }
    }

    private var pairHeader: some View {
        AppGlassCard(
            depth: .floating,
            cornerRadius: 24,
            tint: photosTheme.strongTint,
            contentPadding: 18
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string("Compare photos"))
                            .font(AppTypography.displaySection)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(selectionSummary)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                    Spacer()
                    if let suggestedPair {
                        Button(AppLocalization.string("Compare")) {
                            selectedOlderPhoto = suggestedPair.older
                            selectedNewerPhoto = suggestedPair.newer
                        }
                        .buttonStyle(.plain)
                        .font(AppTypography.sectionAction)
                        .foregroundStyle(photosTheme.accent)
                    }
                }

                HStack(spacing: 12) {
                    selectionSlot(
                        title: AppLocalization.string("Earlier"),
                        photo: selectedOlderPhoto,
                        fallbackSymbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        isFocused: focusedSlot == .older,
                        action: { focusedSlot = .older }
                    )
                    selectionSlot(
                        title: AppLocalization.string("Now"),
                        photo: selectedNewerPhoto,
                        fallbackSymbol: "sparkles",
                        isFocused: focusedSlot == .newer,
                        action: { focusedSlot = .newer }
                    )
                }
            }
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppLocalization.string("home.compare.filter.title"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(photosTheme.accent)
                Spacer()
                Text(AppLocalization.string("home.compare.filter.count", filteredPhotos.count))
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(availableRanges, id: \.self) { range in
                    Button {
                        Haptics.selection()
                        selectedRange = range
                    } label: {
                        Text(range.title)
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(selectedRange == range ? AppColorRoles.textOnAccent : AppColorRoles.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(
                                Group {
                                    if selectedRange == range {
                                        LinearGradient(
                                            colors: [photosTheme.accent.opacity(0.92), Color.appAmber.opacity(0.72)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    } else {
                                        LinearGradient(
                                            colors: [AppColorRoles.surfaceInteractive, AppColorRoles.surfacePrimary],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    }
                                }
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(selectedRange == range ? photosTheme.accent.opacity(0.22) : AppColorRoles.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.compare.filter.\(range.rawValue)")
                }
            }
            .padding(.horizontal, 16)

            if selectedRange == .custom {
                HStack(spacing: 12) {
                    DatePicker(
                        AppLocalization.string("From"),
                        selection: $customStartDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .accessibilityLabel(AppLocalization.string("From"))
                    .accessibilityHint(AppLocalization.string("Select the first date for photo comparison."))
                    .accessibilityIdentifier("home.compare.custom.from")

                    DatePicker(
                        AppLocalization.string("To"),
                        selection: $customEndDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .accessibilityLabel(AppLocalization.string("To"))
                    .accessibilityHint(AppLocalization.string("Select the last date for photo comparison."))
                    .accessibilityIdentifier("home.compare.custom.to")
                }
            }

            if !availableTags.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(AppLocalization.string("Tags"))
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(photosTheme.accent)
                        Spacer()
                        if !selectedTags.isEmpty {
                            Button(AppLocalization.string("Show Less")) {
                                selectedTags.removeAll()
                            }
                            .buttonStyle(.plain)
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(AppColorRoles.textSecondary)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableTags, id: \.self) { tag in
                                Button {
                                    toggleTag(tag)
                                } label: {
                                    HStack(spacing: 4) {
                                        if selectedTags.contains(tag) {
                                            Image(systemName: "checkmark")
                                                .font(AppTypography.micro)
                                        }
                                        Text(tag.title)
                                    }
                                    .font(AppTypography.captionEmphasis)
                                    .foregroundStyle(selectedTags.contains(tag) ? AppColorRoles.textOnAccent : AppColorRoles.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Group {
                                            if selectedTags.contains(tag) {
                                                LinearGradient(
                                                    colors: [photosTheme.accent.opacity(0.92), Color.appAmber.opacity(0.72)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            } else {
                                                LinearGradient(
                                                    colors: [AppColorRoles.surfaceInteractive, AppColorRoles.surfacePrimary],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            }
                                        }
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(selectedTags.contains(tag) ? photosTheme.accent.opacity(0.22) : AppColorRoles.borderSubtle, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var photoGrid: some View {
        if filteredPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string("home.compare.filter.empty"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Text(AppLocalization.string("home.compare.filter.empty.detail"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColorRoles.surfacePrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [photosTheme.softTint, .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 12
            ) {
                ForEach(Array(filteredPhotos.enumerated()), id: \.element.persistentModelID) { index, photo in
                    Button {
                        toggleSelection(for: photo)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                PhotoGridThumb(
                                    photo: photo,
                                    size: 104,
                                    cacheID: String(describing: photo.persistentModelID)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selectionBorderColor(for: photo), lineWidth: selectionBorderWidth(for: photo))
                                }

                                if markerText(for: photo) != nil {
                                    Text(markerText(for: photo) ?? "")
                                        .font(AppTypography.microEmphasis.monospacedDigit())
                                        .foregroundStyle(.black)
                                        .frame(width: 22, height: 22)
                                        .background(photosTheme.accent)
                                        .clipShape(Circle())
                                        .padding(6)
                                }
                            }

                            Text(photo.date.formatted(date: .abbreviated, time: .omitted))
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .lineLimit(1)

                            if !photo.tags.isEmpty {
                                Text(photo.tags.prefix(2).map(\.title).joined(separator: " • "))
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.compare.photo.\(index)")
                }
            }
        }
    }

    private func selectionSlot(
        title: String,
        photo: PhotoEntry?,
        fallbackSymbol: String,
        isFocused: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(AppColorRoles.textTertiary)

                if let photo {
                    PhotoGridThumb(
                        photo: photo,
                        size: 120,
                        cacheID: String(describing: photo.persistentModelID)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive)
                        .frame(width: 120, height: 120)
                        .overlay {
                            Image(systemName: fallbackSymbol)
                                .font(.title3)
                                .foregroundStyle(AppColorRoles.textTertiary)
                        }
                }

                Text(photo?.date.formatted(date: .abbreviated, time: .omitted) ?? AppLocalization.string("Select Date"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isFocused ? photosTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func sanitizeSelection() {
        let visibleIDs = Set(filteredPhotos.map(\.persistentModelID))

        if let selectedOlderPhoto, !visibleIDs.contains(selectedOlderPhoto.persistentModelID) {
            self.selectedOlderPhoto = nil
        }

        if let selectedNewerPhoto, !visibleIDs.contains(selectedNewerPhoto.persistentModelID) {
            self.selectedNewerPhoto = nil
        }

        if selectedOlderPhoto == nil || selectedNewerPhoto == nil {
            if let initialOlderPhoto, let initialNewerPhoto,
               visibleIDs.contains(initialOlderPhoto.persistentModelID),
               visibleIDs.contains(initialNewerPhoto.persistentModelID) {
                selectedOlderPhoto = initialOlderPhoto
                selectedNewerPhoto = initialNewerPhoto
            } else if let suggestedPair {
                selectedOlderPhoto = suggestedPair.older
                selectedNewerPhoto = suggestedPair.newer
            }
        }
    }

    private func toggleSelection(for photo: PhotoEntry) {
        Haptics.selection()
        hasUserModifiedSelection = true

        switch focusedSlot {
        case .older:
            selectedOlderPhoto = photo
            if let selectedNewerPhoto, photo.date > selectedNewerPhoto.date {
                self.selectedNewerPhoto = photo
                self.selectedOlderPhoto = selectedNewerPhoto
            }
            focusedSlot = .newer
        case .newer:
            selectedNewerPhoto = photo
            if let selectedOlderPhoto, photo.date < selectedOlderPhoto.date {
                self.selectedOlderPhoto = photo
                self.selectedNewerPhoto = selectedOlderPhoto
            }
            focusedSlot = .older
        }
    }

    private func markerText(for photo: PhotoEntry) -> String? {
        if selectedOlderPhoto?.persistentModelID == photo.persistentModelID {
            return "1"
        }
        if selectedNewerPhoto?.persistentModelID == photo.persistentModelID {
            return "2"
        }
        return nil
    }

    private func selectionBorderColor(for photo: PhotoEntry) -> Color {
        markerText(for: photo) == nil ? AppColorRoles.borderSubtle : photosTheme.accent
    }

    private func selectionBorderWidth(for photo: PhotoEntry) -> CGFloat {
        markerText(for: photo) == nil ? 1 : 2
    }

    private func confirmCompare() {
        guard let selectedOlderPhoto, let selectedNewerPhoto else { return }
        let sorted = [selectedOlderPhoto, selectedNewerPhoto].sorted { $0.date < $1.date }
        onCompareSelected(sorted[0], sorted[1])
        dismiss()
    }

    private func toggleTag(_ tag: PhotoTag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func matchesTags(_ photo: PhotoEntry) -> Bool {
        guard !selectedTags.isEmpty else { return true }
        return !Set(photo.tags).isDisjoint(with: selectedTags)
    }

    private func publishSelectionChange() {
        guard hasUserModifiedSelection else { return }
        guard let selectedOlderPhoto, let selectedNewerPhoto else { return }
        let sorted = [selectedOlderPhoto, selectedNewerPhoto].sorted { $0.date < $1.date }
        onSelectionChanged?(sorted[0], sorted[1])
    }
}
