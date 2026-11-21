import XCTest
@testable import PulseLoop

/// The scheduling decision for cycle prompts, pinned as a pure matrix: given the fresh
/// prediction, the logged period days, and now — which prompts should be pending? No store,
/// no UserNotifications, no clock: every date is fixed and passed in.
@MainActor
final class CycleNotificationDecisionTests: XCTestCase {
    private let calendar = Calendar.current

    /// A fixed anchor (March 2026) so no test reads the clock.
    private let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10))!

    /// The predicted due date: 28 days after the anchor (the cycle the prediction is derived
    /// from starts on the anchor, so its logged period days sit far before the due date).
    private var due: Date { calendar.date(byAdding: .day, value: 28, to: anchor)! }

    private func prediction(expected: Date, spread: Int = 2) -> PeriodPrediction {
        PeriodPrediction(
            expected: expected,
            earliest: calendar.date(byAdding: .day, value: -spread, to: expected)!,
            latest: calendar.date(byAdding: .day, value: spread, to: expected)!
        )
    }

    /// A full timestamp `offsetFromDue` days from the due date, at `hour` local time.
    private func day(_ offsetFromDue: Int, hour: Int = 12) -> Date {
        let base = calendar.date(byAdding: .day, value: offsetFromDue, to: due)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }

    private func plan(
        now: Date,
        due expected: Date? = nil,
        logged: [Date] = [],
        preAlert: Bool = false
    ) -> [CycleScheduledPrompt] {
        CycleNotificationCenter.schedulePlan(
            prediction: prediction(expected: expected ?? due),
            loggedPeriodDays: logged,
            now: now,
            preAlertEnabled: preAlert,
            calendar: calendar
        )
    }

    private func prompt(_ plan: [CycleScheduledPrompt], _ identifier: String) -> CycleScheduledPrompt? {
        plan.first { $0.identifier == identifier }
    }

    // MARK: - Due date in the future, nothing logged

    func testUnloggedDueInFutureSchedulesOnlyTheHasItStartedPrompt() {
        let prompts = plan(now: day(-3))

        XCTAssertEqual(prompts.count, 1)
        let duePrompt = try! XCTUnwrap(prompt(prompts, CycleNotificationCenter.dueRequestIdentifier))
        XCTAssertEqual(duePrompt.deliverAt, day(0, hour: 9))
        XCTAssertTrue(duePrompt.withActions)
        XCTAssertNil(prompt(prompts, "pulseloop.cycle.periodFollowUp"))
    }

    func testPreAlertAddsADiscreetPromptTwoMorningsAhead() {
        let prompts = plan(now: day(-3), preAlert: true)

        XCTAssertEqual(prompts.count, 2)
        let preAlertPrompt = try! XCTUnwrap(prompt(prompts, CycleNotificationCenter.preAlertRequestIdentifier))
        XCTAssertEqual(preAlertPrompt.deliverAt, day(-2, hour: 9))
        XCTAssertFalse(preAlertPrompt.withActions)
    }

    func testPreAlertIsDroppedOnceItsMorningHasPassed() {
        // Pre-alert morning (due−2, 09:00) is behind us; only the due prompt remains.
        let prompts = plan(now: day(-1), preAlert: true)

        XCTAssertEqual(prompts.map(\.identifier), [CycleNotificationCenter.dueRequestIdentifier])
    }

    func testDuePromptIsNeverResurrectedAfterItsMorningHasPassed() {
        // 09:00 on the due day already fired (or was missed) — a foreground re-derivation at
        // noon must not re-arm it for next year.
        XCTAssertTrue(plan(now: day(0, hour: 12)).isEmpty)
    }

    // MARK: - A period day was logged (auto-cancel)

    func testLoggingAPeriodDayOnTheDueDateCancelsEverything() {
        XCTAssertTrue(plan(now: day(0, hour: 8), logged: [day(0)]).isEmpty)
    }

    func testLoggingAPeriodDayOnTheEarliestPlausibleDayCancelsEverything() {
        XCTAssertTrue(plan(now: day(-2, hour: 8), logged: [day(-2)]).isEmpty)
    }

    func testLoggingAPeriodDayAfterTheDueDateCancelsThePendingFollowUp() {
        XCTAssertTrue(plan(now: day(1), logged: [day(1)]).isEmpty)
    }

    func testALoggedDayBeforeTheDueDateLeavesNoFollowUp() {
        XCTAssertTrue(plan(now: day(1), logged: [day(-1)]).isEmpty)
    }

    func testTheSeedingPeriodDaysDoNotCancelThePrediction() {
        // The cycle the prediction is derived from: its period days are weeks before the due
        // date and must not read as "the predicted period arrived".
        let prompts = plan(now: day(-3), logged: [day(-28), day(-27), day(-26)])

        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.identifier, CycleNotificationCenter.dueRequestIdentifier)
    }

    func testFutureLoggedPeriodDaysDoNotCancel() {
        // The analyzer ignores period days after `today`; the decision does too.
        let prompts = plan(now: day(-3), logged: [day(5)])

        XCTAssertEqual(prompts.count, 1)
    }

    // MARK: - Due date passed unlogged (the follow-up)

    func testUnloggedDueDatePassingSchedulesExactlyOneFollowUpTwoDaysLater() {
        let prompts = plan(now: day(1))

        XCTAssertEqual(prompts.count, 1)
        let followUp = try! XCTUnwrap(prompt(prompts, "pulseloop.cycle.periodFollowUp"))
        XCTAssertEqual(followUp.deliverAt, day(2, hour: 9))
        XCTAssertTrue(followUp.withActions)
        XCTAssertNil(prompt(prompts, CycleNotificationCenter.dueRequestIdentifier))
    }

    func testTheFollowUpStillSchedulesOnItsOwnMorning() {
        let prompts = plan(now: day(2, hour: 7))

        XCTAssertEqual(prompts.map(\.identifier), ["pulseloop.cycle.periodFollowUp"])
    }

    func testTheFollowUpNeverResurrectsAfterItsDeliveryPassed() {
        XCTAssertTrue(plan(now: day(2, hour: 12)).isEmpty)
    }

    func testNothingSchedulesOnceTheFollowUpWindowHasClosed() {
        XCTAssertTrue(plan(now: day(3)).isEmpty)
    }

    func testReDerivationsProduceTheSameSingleFollowUp() {
        // Foreground on day+1, then again on day+2 morning: same one prompt, never a second.
        XCTAssertEqual(plan(now: day(1)), plan(now: day(2, hour: 7)))
    }

    // MARK: - Copy

    func testFollowUpCopyStaysDiscreetAndCarriesTheOneTapAction() {
        let followUp = try! XCTUnwrap(prompt(plan(now: day(1)), "pulseloop.cycle.periodFollowUp"))

        // Lock-screen safe: no cycle details, no "late"/"missed" framing.
        XCTAssertEqual(followUp.body, "Still nothing? Log day 1 if it has started.")
        XCTAssertFalse(followUp.body.lowercased().contains("period"))
        XCTAssertFalse(followUp.body.lowercased().contains("late"))
        XCTAssertTrue(followUp.withActions)
    }
}
