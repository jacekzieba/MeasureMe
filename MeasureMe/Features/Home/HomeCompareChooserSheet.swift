import SwiftUI
import SwiftData

struct HomeCompareChooserSheet: View {
    @Environment(\.dismiss) private var dismiss

    let photos: [PhotoEntry]
    let onCompareSelected: (PhotoEntry, PhotoEntry) -> Void

    @State private var selectedPhotos: [PhotoEntry] = []
    @State private var selectedRange: DateRange = .all
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
    @State private var customEndDate: Date = AppClock.now

    private let isUITestMode = ProcessInfo.processInfo.arguments.contains("-uiTestMode")

    private var availableRanges: [DateRange] {
        [.all, .last30Days, .last90Days, .custom]
    }

    private var filteredPhotos: [PhotoEntry] {
        photos.filter { photo in
            guard let start = selectedRange.startDate(customStart: customStartDate),
                  let end = selectedRange.endDate(customEnd: customEndDate) else {
                return true
            }
            return photo.date >= start && photo.date <= end
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                filterSection

                Text("\(filteredPhotos.count)")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.compare.filteredCount")
                    .frame(width: 1, height: 1)
                    .clipped()

                if isUITestMode {
                    Button(AppLocalization.string("home.compare.chooser.uihook")) {
                        guard filteredPhotos.count >= 2 else { return }
                        openCompare(using: Array(filteredPhotos.prefix(2)))
                    }
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .accessibilityIdentifier("home.compare.selectTwoHook")
                }

                if filteredPhotos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("home.compare.filter.empty"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                        Text(AppLocalization.string("home.compare.filter.empty.detail"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                            spacing: 10
                        ) {
                            ForEach(Array(filteredPhotos.enumerated()), id: \.element.persistentModelID) { index, photo in
                                Button {
                                    toggleSelection(for: photo)
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        PhotoGridThumb(
                                            photo: photo,
                                            size: 104,
                                            cacheID: String(describing: photo.persistentModelID)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(
                                                    selectedPhotos.contains(photo)
                                                    ? Color.appAccent
                                                    : Color.white.opacity(0.08),
                                                    lineWidth: selectedPhotos.contains(photo) ? 2 : 1
                                                )
                                        }

                                        if let selectionIndex = selectedPhotos.firstIndex(of: photo) {
                                            Text("\(selectionIndex + 1)")
                                                .font(AppTypography.microEmphasis.monospacedDigit())
                                                .foregroundStyle(.black)
                                                .frame(width: 22, height: 22)
                                                .background(Color.appAccent)
                                                .clipShape(Circle())
                                                .padding(6)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("home.compare.photo.\(index)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }

                Button {
                    openCompare(using: selectedPhotos)
                } label: {
                    Text(AppLocalization.string("Compare"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                .disabled(selectedPhotos.count != 2)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("home.compare.confirm")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(AppLocalization.string("home.compare.chooser.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
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
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppLocalization.string("home.compare.filter.title"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color.appAccent)
                Spacer()
                Text(AppLocalization.string("home.compare.filter.count", filteredPhotos.count))
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableRanges, id: \.self) { range in
                        Button {
                            Haptics.selection()
                            selectedRange = range
                        } label: {
                            Text(range.title)
                                .font(AppTypography.microEmphasis)
                                .foregroundStyle(selectedRange == range ? .black : .white.opacity(0.82))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedRange == range ? Color.appAccent : Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.compare.filter.\(range.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
            }

            if selectedRange == .custom {
                HStack(spacing: 12) {
                    DatePicker(
                        AppLocalization.string("From"),
                        selection: $customStartDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()

                    DatePicker(
                        AppLocalization.string("To"),
                        selection: $customEndDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func sanitizeSelection() {
        let visibleIDs = Set(filteredPhotos.map(\.persistentModelID))
        selectedPhotos = selectedPhotos.filter { visibleIDs.contains($0.persistentModelID) }
    }

    private func toggleSelection(for photo: PhotoEntry) {
        Haptics.selection()
        if let existingIndex = selectedPhotos.firstIndex(of: photo) {
            selectedPhotos.remove(at: existingIndex)
            return
        }

        if selectedPhotos.count == 2 {
            selectedPhotos = [selectedPhotos[1], photo]
        } else {
            selectedPhotos.append(photo)
        }
    }

    private func openCompare(using photos: [PhotoEntry]) {
        guard photos.count == 2 else { return }
        let sorted = photos.sorted { $0.date < $1.date }
        onCompareSelected(sorted[0], sorted[1])
        dismiss()
    }
}
