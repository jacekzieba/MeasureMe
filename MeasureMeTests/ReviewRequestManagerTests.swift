import XCTest
@testable import MeasureMe

@MainActor
final class ReviewRequestManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: AppSettingsStore!

    override func setUp() {
        super.setUp()
        let suiteName = "ReviewRequestManagerTests.\(name)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ReviewRequestManagerTests.\(name)")
        settings = nil
        defaults = nil
        super.tearDown()
    }

    func testUserMaturityRequiresMinimumMetricEntries() {
        let firstEngagement = Date(timeIntervalSince1970: 1_700_000_000)
        let now = firstEngagement.addingTimeInterval(8 * 24 * 60 * 60)
        settings.set(firstEngagement, forKey: "review_prompt_first_engagement_date")
        settings.set(2, forKey: "review_prompt_lifetime_metric_count")

        XCTAssertFalse(ReviewRequestManager.isUserMatureEnoughForPrompt(settings: settings, now: now))
    }

    func testUserMaturityRequiresSevenDaysSinceFirstEngagement() {
        let firstEngagement = Date(timeIntervalSince1970: 1_700_000_000)
        let now = firstEngagement.addingTimeInterval(3 * 24 * 60 * 60)
        settings.set(firstEngagement, forKey: "review_prompt_first_engagement_date")
        settings.set(3, forKey: "review_prompt_lifetime_metric_count")

        XCTAssertFalse(ReviewRequestManager.isUserMatureEnoughForPrompt(settings: settings, now: now))
    }

    func testUserMaturityAllowsPromptAfterMinimumEntriesAndSevenDays() {
        let firstEngagement = Date(timeIntervalSince1970: 1_700_000_000)
        let now = firstEngagement.addingTimeInterval(7 * 24 * 60 * 60)
        settings.set(firstEngagement, forKey: "review_prompt_first_engagement_date")
        settings.set(3, forKey: "review_prompt_lifetime_metric_count")

        XCTAssertTrue(ReviewRequestManager.isUserMatureEnoughForPrompt(settings: settings, now: now))
    }

    func testCooldownBlocksPromptInsideFourteenDays() {
        let lastPrompt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = lastPrompt.addingTimeInterval(13 * 24 * 60 * 60)
        settings.set(lastPrompt, forKey: "review_prompt_last_date")

        XCTAssertFalse(ReviewRequestManager.hasEnoughTimePassedSinceLastPrompt(settings: settings, now: now))
    }

    func testCooldownAllowsPromptAfterFourteenDays() {
        let lastPrompt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = lastPrompt.addingTimeInterval(14 * 24 * 60 * 60)
        settings.set(lastPrompt, forKey: "review_prompt_last_date")

        XCTAssertTrue(ReviewRequestManager.hasEnoughTimePassedSinceLastPrompt(settings: settings, now: now))
    }
}
