import Foundation

enum HomeModuleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case summaryHero
    case quickActions
    case keyMetrics
    case recentPhotos
    case healthSummary
    case activationHub
    case setupChecklist

    var id: String { rawValue }

    static var activeCases: [HomeModuleKind] {
        [.summaryHero, .quickActions, .keyMetrics, .recentPhotos, .healthSummary, .activationHub]
    }

    var defaultSize: HomeModuleSize {
        switch self {
        case .summaryHero, .keyMetrics, .recentPhotos, .healthSummary:
            return .large
        case .quickActions:
            return .large
        case .activationHub, .setupChecklist:
            return .wide
        }
    }

    nonisolated fileprivate var sortIndex: Int {
        switch self {
        case .summaryHero: return 0
        case .quickActions: return 1
        case .keyMetrics: return 2
        case .recentPhotos: return 3
        case .healthSummary: return 4
        case .activationHub: return 5
        case .setupChecklist: return 6
        }
    }
}

enum HomePinnedAction: String, Codable, CaseIterable, Sendable {
    case addMeasurement
    case setGoal
    case comparePhotos
}

enum HomeModuleSize: String, Codable, Sendable {
    case small
    case wide
    case tall
    case large

    var columnSpan: Int {
        switch self {
        case .small, .tall:
            return 1
        case .wide, .large:
            return 2
        }
    }

    var rowSpan: Int {
        switch self {
        case .small, .wide:
            return 1
        case .tall, .large:
            return 2
        }
    }

    func normalized(for columns: Int) -> HomeModuleSize {
        guard columns > 1 else { return .small }
        switch self {
        case .small, .tall:
            return self
        case .wide, .large:
            return columns >= 2 ? self : .small
        }
    }
}

struct HomeModuleLayoutItem: Codable, Equatable, Identifiable, Sendable {
    let kind: HomeModuleKind
    var isVisible: Bool
    var size: HomeModuleSize
    var row: Int
    var column: Int

    var id: HomeModuleKind { kind }
}

struct HomeLayoutSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 5

    var schemaVersion: Int
    var items: [HomeModuleLayoutItem]

    static func defaultV1(using settings: AppSettingsSnapshot) -> HomeLayoutSnapshot {
        HomeLayoutSnapshot(
            schemaVersion: currentSchemaVersion,
            items: [
                HomeModuleLayoutItem(kind: .summaryHero, isVisible: true, size: .large, row: 0, column: 0),
                HomeModuleLayoutItem(kind: .quickActions, isVisible: false, size: .large, row: 0, column: 2),
                HomeModuleLayoutItem(kind: .activationHub, isVisible: !settings.onboarding.activationIsDismissed, size: .wide, row: 0, column: 2),
                HomeModuleLayoutItem(kind: .keyMetrics, isVisible: settings.home.showMeasurementsOnHome, size: .large, row: 2, column: 0),
                HomeModuleLayoutItem(kind: .recentPhotos, isVisible: settings.home.showLastPhotosOnHome, size: .large, row: 2, column: 2),
                HomeModuleLayoutItem(kind: .healthSummary, isVisible: settings.home.showHealthMetricsOnHome, size: .large, row: 4, column: 0)
            ]
        )
    }

    func item(for kind: HomeModuleKind) -> HomeModuleLayoutItem? {
        items.first { $0.kind == kind }
    }

    mutating func setVisibility(_ isVisible: Bool, for kind: HomeModuleKind) {
        guard let index = items.firstIndex(where: { $0.kind == kind }) else { return }
        items[index].isVisible = isVisible
    }

    func resettingToDefaultGeometry(using settings: AppSettingsSnapshot) -> HomeLayoutSnapshot {
        let defaultSnapshot = Self.defaultV1(using: settings)
        let currentVisibility = visibilityMap(from: items)
        let resetItems = defaultSnapshot.items.map { item in
            var next = item
            next.isVisible = currentVisibility[item.kind] ?? item.isVisible
            return next
        }
        return HomeLayoutSnapshot(schemaVersion: Self.currentSchemaVersion, items: resetItems)
    }

    private func visibilityMap(from items: [HomeModuleLayoutItem]) -> [HomeModuleKind: Bool] {
        var map: [HomeModuleKind: Bool] = [:]
        for item in items where map[item.kind] == nil {
            map[item.kind] = item.isVisible
        }
        return map
    }
}

enum HomeLayoutNormalizer {
    static func normalize(_ snapshot: HomeLayoutSnapshot, using settings: AppSettingsSnapshot) -> HomeLayoutSnapshot {
        if snapshot.schemaVersion < HomeLayoutSnapshot.currentSchemaVersion {
            let defaultSnapshot = HomeLayoutSnapshot.defaultV1(using: settings)
            let currentVisibility = visibilityMap(from: snapshot.items)
            let migratedItems = defaultSnapshot.items.map { item in
                var next = item
                next.isVisible = currentVisibility[item.kind] ?? item.isVisible
                return next
            }
            return HomeLayoutSnapshot(
                schemaVersion: HomeLayoutSnapshot.currentSchemaVersion,
                items: migratedItems.sorted(by: sortItems)
            )
        }

        let defaultSnapshot = HomeLayoutSnapshot.defaultV1(using: settings)
        var uniqueItems: [HomeModuleKind: HomeModuleLayoutItem] = [:]

        for item in snapshot.items {
            guard uniqueItems[item.kind] == nil else { continue }
            uniqueItems[item.kind] = HomeModuleLayoutItem(
                kind: item.kind,
                isVisible: item.isVisible,
                size: item.size,
                row: max(item.row, 0),
                column: max(item.column, 0)
            )
        }

        for defaultItem in defaultSnapshot.items where uniqueItems[defaultItem.kind] == nil {
            uniqueItems[defaultItem.kind] = defaultItem
        }

        let normalizedItems = HomeModuleKind.activeCases.compactMap { kind -> HomeModuleLayoutItem? in
            guard var item = uniqueItems[kind] else { return nil }
            item.size = item.size
            return item
        }

        return HomeLayoutSnapshot(
            schemaVersion: max(snapshot.schemaVersion, HomeLayoutSnapshot.currentSchemaVersion),
            items: normalizedItems.sorted(by: sortItems)
        )
    }

    nonisolated static func sortItems(_ lhs: HomeModuleLayoutItem, _ rhs: HomeModuleLayoutItem) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        return lhs.kind.sortIndex < rhs.kind.sortIndex
    }

    private static func visibilityMap(from items: [HomeModuleLayoutItem]) -> [HomeModuleKind: Bool] {
        var map: [HomeModuleKind: Bool] = [:]
        for item in items where map[item.kind] == nil {
            map[item.kind] = item.isVisible
        }
        return map
    }
}

enum HomeLayoutCompactor {
    static func compact(_ items: [HomeModuleLayoutItem], columns: Int) -> [HomeModuleLayoutItem] {
        guard columns > 0 else { return [] }

        let visibleItems = items
            .filter(\.isVisible)
            .sorted(by: HomeLayoutNormalizer.sortItems)

        var occupied: Set<GridCell> = []
        var compacted: [HomeModuleLayoutItem] = []

        for item in visibleItems {
            let size = item.size.normalized(for: columns)
            let placement = firstPlacement(for: size, columns: columns, occupied: occupied)
            var next = item
            next.size = size
            next.row = placement.row
            next.column = placement.column
            compacted.append(next)

            for row in placement.row..<(placement.row + size.rowSpan) {
                for column in placement.column..<(placement.column + size.columnSpan) {
                    occupied.insert(GridCell(row: row, column: column))
                }
            }
        }

        return compacted
    }

    private static func firstPlacement(
        for size: HomeModuleSize,
        columns: Int,
        occupied: Set<GridCell>
    ) -> GridCell {
        let maxColumn = max(columns - size.columnSpan, 0)
        var row = 0

        while row < 100 {
            for column in 0...maxColumn {
                let candidate = GridCell(row: row, column: column)
                if fits(candidate, size: size, columns: columns, occupied: occupied) {
                    return candidate
                }
            }
            row += 1
        }

        return GridCell(row: row, column: 0)
    }

    private static func fits(
        _ origin: GridCell,
        size: HomeModuleSize,
        columns: Int,
        occupied: Set<GridCell>
    ) -> Bool {
        guard origin.column + size.columnSpan <= columns else { return false }

        for row in origin.row..<(origin.row + size.rowSpan) {
            for column in origin.column..<(origin.column + size.columnSpan) {
                if occupied.contains(GridCell(row: row, column: column)) {
                    return false
                }
            }
        }
        return true
    }

    private struct GridCell: Hashable {
        let row: Int
        let column: Int
    }
}
