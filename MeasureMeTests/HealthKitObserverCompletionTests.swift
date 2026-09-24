/// Cel testow: Sprawdza, ze obserwator HealthKit zglasza zakonczenie dopiero po imporcie.
/// Dlaczego to wazne: Przy dostarczaniu w tle system moze uspic aplikacje zaraz po wywolaniu `completion`.
///   Wywolanie go przed importem oznaczalo, ze pomiary z Health czesto nie trafialy do aplikacji w tle.
/// Kryteria zaliczenia: `completion` wywolane po zakonczeniu importu, a przy bledzie od razu.

import XCTest
import HealthKit
@testable import MeasureMe

final class HealthKitObserverCompletionTests: XCTestCase {
    private let query = HKObserverQuery(sampleType: HKQuantityType(.bodyMass), predicate: nil) { _, _, _ in }

    func testCompletionIsCalledOnlyAfterTheImportFinished() async {
        let events = EventLog()
        let completed = expectation(description: "completion called")
        let handler = HealthKitManager.observerUpdateHandler {
            try? await Task.sleep(for: .milliseconds(50))
            events.append("import finished")
        }

        handler(query, {
            events.append("completion")
            completed.fulfill()
        }, nil)

        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(events.all, ["import finished", "completion"])
    }

    func testCompletionIsCalledWithoutImportingWhenTheQueryFailed() async {
        let events = EventLog()
        let completed = expectation(description: "completion called")
        let handler = HealthKitManager.observerUpdateHandler {
            events.append("import finished")
        }

        handler(query, {
            events.append("completion")
            completed.fulfill()
        }, NSError(domain: "test", code: 1))

        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(events.all, ["completion"])
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    var all: [String] {
        lock.withLock { events }
    }

    func append(_ event: String) {
        lock.withLock { events.append(event) }
    }
}
