import SwiftData

/// Abstrakcja zapisu danych do widgetu, ułatwiająca tworzenie atrap testowych.
protocol WidgetDataWriting {
    func writeAndReload(kinds: [MetricKind], context: ModelContext, unitsSystem: String)
}

/// Produkcyjna implementacja deleguje do statycznego WidgetDataWriter.
struct LiveWidgetDataWriter: WidgetDataWriting {
    func writeAndReload(kinds: [MetricKind], context: ModelContext, unitsSystem: String) {
        WidgetDataWriter.writeAndReload(kinds: kinds, context: context, unitsSystem: unitsSystem)
    }
}
