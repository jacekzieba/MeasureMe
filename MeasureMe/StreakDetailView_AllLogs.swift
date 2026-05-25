import SwiftData
import SwiftUI

// MARK: - AllLogsView (navigated to from StreakDetailView.totalLogsRow)

struct AllLogsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomMetricDefinition.sortOrder)
    private var customDefinitions: [CustomMetricDefinition]

    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    @State private var sourceFilter: SourceFilter = .all
    @State private var dateFilter: DateFilter = .all
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
    @State private var customEndDate: Date = AppClock.now
    @State private var pagedSamples: [MetricSample] = []
    @State private var currentOffset: Int = 0
    @State private var hasMorePages: Bool = true
    @State private var isLoadingPage: Bool = false

    private let pageSize: Int = 80

    private enum SourceFilter: String, CaseIterable, Identifiable {
        case all
        case manual
        case healthKit

        var id: String { rawValue }
    }

    private enum DateFilter: String, CaseIterable, Identifiable {
        case all
        case custom

        var id: String { rawValue }
    }

    private var customDefinitionByID: [String: CustomMetricDefinition] {
        Dictionary(uniqueKeysWithValues: customDefinitions.map { ($0.identifier, $0) })
    }

    private var activePredicate: Predicate<MetricSample>? {
        let healthKitRaw = MetricSampleSource.healthKit.rawValue
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: customStartDate)
        let endDay = calendar.startOfDay(for: customEndDate)
        let endDate = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay) ?? customEndDate

        switch (sourceFilter, dateFilter) {
        case (.all, .all):
            return nil
        case (.manual, .all):
            return #Predicate<MetricSample> { $0.sourceRaw != healthKitRaw }
        case (.healthKit, .all):
            return #Predicate<MetricSample> { $0.sourceRaw == healthKitRaw }
        case (.all, .custom):
            return #Predicate<MetricSample> { $0.date >= startDate && $0.date <= endDate }
        case (.manual, .custom):
            return #Predicate<MetricSample> {
                $0.sourceRaw != healthKitRaw &&
                $0.date >= startDate &&
                $0.date <= endDate
            }
        case (.healthKit, .custom):
            return #Predicate<MetricSample> {
                $0.sourceRaw == healthKitRaw &&
                $0.date >= startDate &&
                $0.date <= endDate
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 300, tint: Color.appAccent.opacity(0.18))

            ScrollView {
                VStack(spacing: 12) {
                    filtersCard
                    listSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(AppLocalization.string("alllogs.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            handleAllLogsAppear()
        }
        .onChange(of: sourceFilter) { _, _ in
            handleAllLogsSourceFilterChange()
        }
        .onChange(of: dateFilter) { _, _ in
            handleAllLogsDateFilterChange()
        }
        .onChange(of: customStartDate) { _, newValue in
            handleAllLogsCustomStartDateChange(newValue)
        }
        .onChange(of: customEndDate) { _, newValue in
            handleAllLogsCustomEndDateChange(newValue)
        }
    }

    private var filtersCard: some View {
        AppGlassCard(depth: .base, cornerRadius: 16, tint: .clear, contentPadding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.string("Filters"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.65))

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.string("alllogs.filter.source"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Picker("", selection: $sourceFilter) {
                        Text(AppLocalization.string("alllogs.filter.all")).tag(SourceFilter.all)
                        Text(AppLocalization.string("alllogs.filter.manual")).tag(SourceFilter.manual)
                        Text(AppLocalization.string("alllogs.filter.healthkit")).tag(SourceFilter.healthKit)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.string("Date Range"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Picker("", selection: $dateFilter) {
                        Text(AppLocalization.string("alllogs.filter.all")).tag(DateFilter.all)
                        Text(AppLocalization.string("photos.dateRange.custom")).tag(DateFilter.custom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if dateFilter == .custom {
                        DatePicker(
                            AppLocalization.string("From"),
                            selection: $customStartDate,
                            displayedComponents: [.date]
                        )
                        DatePicker(
                            AppLocalization.string("To"),
                            selection: $customEndDate,
                            displayedComponents: [.date]
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var listSection: some View {
        if pagedSamples.isEmpty && !isLoadingPage {
            AppGlassCard(depth: .base, cornerRadius: 16, tint: .clear, contentPadding: 16) {
                Text(AppLocalization.string("alllogs.empty"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            LazyVStack(spacing: 8) {
                ForEach(pagedSamples, id: \.persistentModelID) { sample in
                    row(for: sample)
                        .onAppear {
                            handleAllLogsRowAppear(sample)
                        }
                }

                if isLoadingPage {
                    ProgressView()
                        .tint(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private func row(for sample: MetricSample) -> some View {
        AppGlassCard(depth: .base, cornerRadius: 14, tint: .clear, contentPadding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(metricTitle(for: sample))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    sourceBadge(for: sample.source)
                }

                HStack(spacing: 8) {
                    Text(metricValueText(for: sample))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer(minLength: 8)

                    Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func sourceBadge(for source: MetricSampleSource) -> some View {
        let label: String
        switch source {
        case .manual:
            label = AppLocalization.string("alllogs.filter.manual")
        case .healthKit:
            label = AppLocalization.string("alllogs.filter.healthkit")
        }

        return Text(label)
            .font(AppTypography.micro)
            .foregroundStyle(.white.opacity(0.84))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.12))
            )
    }

    private func handleAllLogsAppear() {
        if pagedSamples.isEmpty {
            resetAndLoad()
        }
    }

    private func handleAllLogsSourceFilterChange() {
        resetAndLoad()
    }

    private func handleAllLogsDateFilterChange() {
        resetAndLoad()
    }

    private func handleAllLogsCustomStartDateChange(_ newValue: Date) {
        if newValue > customEndDate {
            customEndDate = newValue
        }
        if dateFilter == .custom {
            resetAndLoad()
        }
    }

    private func handleAllLogsCustomEndDateChange(_ newValue: Date) {
        if newValue < customStartDate {
            customStartDate = newValue
        }
        if dateFilter == .custom {
            resetAndLoad()
        }
    }

    private func handleAllLogsRowAppear(_ sample: MetricSample) {
        loadNextPageIfNeeded(currentSample: sample)
    }

    private func metricTitle(for sample: MetricSample) -> String {
        if let kind = sample.kind {
            return kind.title
        }
        if let custom = customDefinitionByID[sample.kindRaw] {
            return custom.name
        }
        return sample.kindRaw
    }

    private func metricValueText(for sample: MetricSample) -> String {
        if let kind = sample.kind {
            return kind.formattedMetricValue(fromMetric: sample.value, unitsSystem: unitsSystem)
        }
        if let custom = customDefinitionByID[sample.kindRaw] {
            return String(format: "%.2f %@", sample.value, custom.unitLabel)
        }
        return String(format: "%.2f", sample.value)
    }

    private func resetAndLoad() {
        currentOffset = 0
        hasMorePages = true
        isLoadingPage = false
        pagedSamples = []
        loadNextPage()
    }

    private func loadNextPageIfNeeded(currentSample: MetricSample) {
        guard !isLoadingPage, hasMorePages else { return }
        guard let index = pagedSamples.firstIndex(where: { $0.persistentModelID == currentSample.persistentModelID }) else { return }
        if index >= pagedSamples.count - 12 {
            loadNextPage()
        }
    }

    private func loadNextPage() {
        guard !isLoadingPage, hasMorePages else { return }
        isLoadingPage = true

        var descriptor = FetchDescriptor<MetricSample>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.predicate = activePredicate
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = currentOffset

        do {
            let batch = try modelContext.fetch(descriptor)
            if batch.isEmpty {
                hasMorePages = false
            } else {
                pagedSamples.append(contentsOf: batch)
                currentOffset += batch.count
                if batch.count < pageSize {
                    hasMorePages = false
                }
            }
        } catch {
            hasMorePages = false
        }

        isLoadingPage = false
    }
}
