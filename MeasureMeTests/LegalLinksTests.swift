/// Cel testow: Pilnuje linku, ktory otwiera formularz oceny aplikacji w App Store.
/// Dlaczego to wazne: Zly link zamiast formularza recenzji otwieralby zwykla strone aplikacji i oceny nadal by nie przybywalo.
/// Kryteria zaliczenia: Link prowadzi do tej samej aplikacji co link do udostepniania i ma parametr action=write-review.

import XCTest
@testable import MeasureMe

final class LegalLinksTests: XCTestCase {
    func testWriteReviewLinkOpensTheReviewFormOfThisApp() throws {
        let components = try XCTUnwrap(URLComponents(url: LegalLinks.writeReview, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "apps.apple.com")
        XCTAssertEqual(components.queryItems?.first { $0.name == "action" }?.value, "write-review")
        let appID = try XCTUnwrap(LegalLinks.appStore.absoluteString.split(separator: "/").first { $0.hasPrefix("id") }?.prefix { $0 != "?" })
        XCTAssertTrue(components.path.hasSuffix(String(appID)), "The review link must point at the same app id as the share link")
    }

    func testWriteReviewLinkIsNotPinnedToOneStorefront() {
        XCTAssertNil(LegalLinks.writeReview.pathComponents.first { $0.count == 2 && $0 != "id" }, "No /pl/-style country segment")
        XCTAssertNil(URLComponents(url: LegalLinks.writeReview, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "l" })
    }
}
