import XCTest
@testable import MeasureMe

final class InsightDiskCacheTests: XCTestCase {

    private var testSuiteName: String!
    private var originalSuiteName: String!
    private var originalTTL: TimeInterval!
    private var originalMaxEntries: Int!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testSuiteName = "InsightDiskCacheTests.\(UUID().uuidString)"
        originalSuiteName = InsightDiskCache.suiteName
        originalTTL = InsightDiskCache.ttl
        originalMaxEntries = InsightDiskCache.maxEntries
        InsightDiskCache.suiteName = testSuiteName
    }

    override func tearDownWithError() throws {
        if let suite = testSuiteName {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        InsightDiskCache.suiteName = originalSuiteName
        InsightDiskCache.ttl = originalTTL
        InsightDiskCache.maxEntries = originalMaxEntries
        try super.tearDownWithError()
    }

    /// Co sprawdza: Zapis i odczyt roundtrip
    /// Dlaczego: Podstawowa funkcjonalnosc cache na dysku
    /// Kryteria: Odczyt zwraca te same dane co zapis
    func testWriteAndRead_roundtrip() {
        let pair = MetricInsightPair(shortText: "Trending up.", detailedText: "Keep going.")
        InsightDiskCache.write(pair, forKey: "weight_123")

        let read = InsightDiskCache.read(forKey: "weight_123")
        XCTAssertNotNil(read)
        XCTAssertEqual(read?.shortText, "Trending up.")
        XCTAssertEqual(read?.detailedText, "Keep going.")
    }

    /// Co sprawdza: TTL wygasl — zwraca nil
    /// Dlaczego: Cache nie powinien zwracac nieaktualnych danych
    /// Kryteria: Po uplywie TTL read zwraca nil
    func testRead_expiredTTL_returnsNil() {
        // Ustawiamy TTL na 0 sekund — wszystko natychmiast wygasa
        InsightDiskCache.ttl = 0

        let pair = MetricInsightPair(shortText: "Old.", detailedText: "Stale data.")
        InsightDiskCache.write(pair, forKey: "expired_key")

        let read = InsightDiskCache.read(forKey: "expired_key")
        XCTAssertNil(read)
    }

    /// Co sprawdza: Eviction najstarszych wpisow po przekroczeniu max
    /// Dlaczego: Cache nie powinien rosnac bez ograniczen
    /// Kryteria: Najstarsze wpisy usuniete, najnowsze zachowane
    func testWrite_maxEntriesEviction() {
        InsightDiskCache.maxEntries = 3

        for i in 0..<4 {
            let pair = MetricInsightPair(shortText: "Entry \(i)", detailedText: "Detail \(i)")
            InsightDiskCache.write(pair, forKey: "key_\(i)")
        }

        // Najstarszy wpis (key_0) powinien byc wyrzucony
        XCTAssertNil(InsightDiskCache.read(forKey: "key_0"))
        // Najnowszy (key_3) powinien istniec
        XCTAssertNotNil(InsightDiskCache.read(forKey: "key_3"))
    }

    /// Co sprawdza: removeEntries czysci cache przy invalidacji metryki
    /// Dlaczego: Klucze sa hashowane, wiec nie da sie ich dopasowac po tytule metryki;
    ///   cache jest ograniczony do maxEntries, wiec czyszczenie calosci jest tanie.
    /// Kryteria: Po invalidacji zaden wpis nie zostaje.
    func testRemoveEntries_clearsTheStore() {
        InsightDiskCache.write(
            MetricInsightPair(shortText: "W", detailedText: "W"),
            forKey: "Weight_123"
        )
        InsightDiskCache.write(
            MetricInsightPair(shortText: "B", detailedText: "B"),
            forKey: "BodyFat_456"
        )

        InsightDiskCache.removeEntries(matching: "Weight")

        XCTAssertNil(InsightDiskCache.read(forKey: "Weight_123"))
        XCTAssertNil(InsightDiskCache.read(forKey: "BodyFat_456"))
    }

    /// Co sprawdza: Klucz cache nie zawiera wartosci pomiaru
    /// Dlaczego: Klucz laduje jako jawny klucz slownika w plist na dysku
    /// Kryteria: Ani wartosc, ani jednostka nie pojawiaja sie w kluczu
    func testStableKeyDoesNotContainTheMeasurementValue() {
        let key = InsightDiskCache.stableKey(
            metricTitle: "Weight",
            latestValueText: "82.4 kg",
            promptVersion: "7"
        )

        XCTAssertFalse(key.contains("82.4"))
        XCTAssertFalse(key.contains("kg"))
        XCTAssertFalse(key.contains("Weight"))
        XCTAssertTrue(key.hasPrefix("v7_"))
    }

    /// Co sprawdza: Nowy pomiar nadal uniewaznia zapisany insight
    /// Dlaczego: Hashowanie nie moze zepsuc regeneracji po zmianie danych
    /// Kryteria: Inna wartosc daje inny klucz
    func testStableKeyChangesWhenTheValueChanges() {
        let a = InsightDiskCache.stableKey(metricTitle: "Weight", latestValueText: "82.4 kg", promptVersion: "7")
        let b = InsightDiskCache.stableKey(metricTitle: "Weight", latestValueText: "82.5 kg", promptVersion: "7")

        XCTAssertNotEqual(a, b)
    }

    /// Co sprawdza: Doba cache liczy sie wedlug kalendarza lokalnego, nie UTC
    /// Dlaczego: ISO8601DateFormatter jest w UTC, wiec "dzienny" cache resetowal sie
    ///   przed poludniem dla stref na wschod od Greenwich.
    /// Kryteria: 23:30 i 01:30 czasu lokalnego to dwie rozne doby
    func testStableKeyRollsOverOnTheLocalDayNotUTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!

        let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 23, minute: 30))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 1, minute: 30))!

        let a = InsightDiskCache.dayComponent(for: lateEvening, calendar: calendar)
        let b = InsightDiskCache.dayComponent(for: afterMidnight, calendar: calendar)

        XCTAssertEqual(a, "2026-08-24")
        XCTAssertEqual(b, "2026-08-25")
        XCTAssertNotEqual(a, b)
    }

    /// Co sprawdza: Odczyt z brakujacych danych zwraca nil
    /// Dlaczego: Pierwszy uzycie lub po wyczyszczeniu
    /// Kryteria: nil bez crashu
    func testRead_missingData_returnsNil() {
        XCTAssertNil(InsightDiskCache.read(forKey: "nonexistent"))
    }

    /// Co sprawdza: Uszkodzone dane w UserDefaults zwracaja nil
    /// Dlaczego: Odpornosc na korupcje danych
    /// Kryteria: nil bez crashu
    func testRead_corruptedData_returnsNil() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.set(Data("not json".utf8), forKey: "insight_disk_cache_v1")

        XCTAssertNil(InsightDiskCache.read(forKey: "any_key"))
    }
}
