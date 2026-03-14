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

    /// Co sprawdza: removeEntries usuwa wpisy pasujace do tytulu metryki
    /// Dlaczego: Invalidacja cache po zapisie nowego pomiaru
    /// Kryteria: Pasujace wpisy usuniete, inne zachowane
    func testRemoveEntries_matchingTitle() {
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
        XCTAssertNotNil(InsightDiskCache.read(forKey: "BodyFat_456"))
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
