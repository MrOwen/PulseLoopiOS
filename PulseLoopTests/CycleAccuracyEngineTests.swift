import XCTest
@testable import PulseLoop

/// Tests for the pure accuracy engine and its sentences: night-coverage quality tiers, the
/// cycles-logged milestone ladder, the irregularity cutoff, the honest period range, and the
/// agreement between the drawn prediction band and the stated accuracy. Fixtures run through
/// `CycleAnalyzer.analyze` — the pipeline `CycleService` feeds the engine at runtime — so the
/// expectations track the real analysis instead of a hand-written stub.
@MainActor
final class CycleAccuracyEngineTests: XCTestCase {
    private let calendar = Calendar.current
    private lazy var base = calendar.startOfDay(for: Date())

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base)!
    }

    /// Records for `cycleLengths.count` completed cycles (each starting `length` days after the
    /// previous one, period on day 1) plus the running cycle's `temps` nights from its day 1.
    /// A disturbed night keeps its temperature but is flagged — the coverage engine must read
    /// exactly that.
    private func records(cycleLengths: [Int], temps: [Double?] = [], disturbed: Set<Int> = []) -> [CycleDayRecord] {
        var all: [CycleDayRecord] = []
        var offset = 0
        for length in cycleLengths {
            all.append(CycleDayRecord(date: day(offset), temperature: nil, isPeriod: true, isDisturbed: false))
            offset += length
        }
        let currentStart = offset
        // The running cycle's day 1 is always a logged period day — even with zero nights yet —
        // so the analyzer opens the current cycle there instead of folding it into the last one.
        if temps.isEmpty {
            all.append(CycleDayRecord(date: day(currentStart), temperature: nil, isPeriod: true, isDisturbed: false))
        }
        for (index, temp) in temps.enumerated() {
            all.append(CycleDayRecord(
                date: day(currentStart + index),
                temperature: temp,
                isPeriod: index == 0,
                isDisturbed: disturbed.contains(index + 1)
            ))
        }
        return all
    }

    /// Runs the real analyzer over the fixture (today on the last given night), then the engine.
    private func evaluate(cycleLengths: [Int], temps: [Double?] = [], disturbed: Set<Int> = []) -> (CycleAccuracy, CycleAnalysis) {
        let all = records(cycleLengths: cycleLengths, temps: temps, disturbed: disturbed)
        let todayOffset = cycleLengths.reduce(0, +) + max(temps.count - 1, 0)
        let analysis = CycleAnalyzer.analyze(days: all, goal: .understand, today: day(todayOffset), calendar: calendar)!
        let accuracy = CycleAccuracyEngine.evaluate(days: all, analysis: analysis, today: day(todayOffset), calendar: calendar)!
        return (accuracy, analysis)
    }

    // MARK: - Night-coverage quality tiers

    func testGoodCoverageAtEightyFivePercent() {
        // 17 usable of 20 nights = 0.85 — exactly at the good threshold.
        var temps = Array(repeating: 36.0 as Double?, count: 20)
        temps[3] = nil; temps[9] = nil; temps[15] = nil
        let (accuracy, _) = evaluate(cycleLengths: [], temps: temps)
        XCTAssertEqual(accuracy.quality, .good)
        XCTAssertEqual(accuracy.usableNights, 17)
        XCTAssertEqual(accuracy.totalNights, 20)
    }

    func testFairCoverageAtSixtyPercent() {
        // 6 of 10 = 0.60 — the fair floor is inclusive.
        var temps = Array(repeating: 36.0 as Double?, count: 10)
        for index in 6..<10 { temps[index] = nil }
        let (accuracy, _) = evaluate(cycleLengths: [], temps: temps)
        XCTAssertEqual(accuracy.quality, .fair)
    }

    func testSparseCoverageBelowSixtyPercent() {
        var temps = Array(repeating: 36.0 as Double?, count: 10)
        for index in 5..<10 { temps[index] = nil }
        let (accuracy, _) = evaluate(cycleLengths: [], temps: temps)
        XCTAssertEqual(accuracy.quality, .sparse)
    }

    func testFewerThanFiveNightsIsNoDataRegardlessOfRatio() {
        let (accuracy, _) = evaluate(cycleLengths: [], temps: [36.0, 36.0, 36.0, 36.0])
        XCTAssertEqual(accuracy.quality, .noData)
        XCTAssertEqual(accuracy.totalNights, 4)
    }

    func testDisturbedNightCountsInTotalButNotUsable() {
        let (accuracy, _) = evaluate(cycleLengths: [], temps: Array(repeating: 36.0 as Double?, count: 10), disturbed: [3])
        XCTAssertEqual(accuracy.usableNights, 9)
        XCTAssertEqual(accuracy.totalNights, 10)
        XCTAssertEqual(accuracy.excludedNights, 1)
        XCTAssertEqual(accuracy.quality, .good)
    }

    // MARK: - Milestone ladder

    /// The ladder itself: each case is the next rung to climb toward.
    func testMilestoneTransitions() {
        XCTAssertEqual(CycleAccuracyEngine.nextMilestone(cyclesLogged: 0), .first)
        XCTAssertEqual(CycleAccuracyEngine.nextMilestone(cyclesLogged: 1), .establishing)
        XCTAssertEqual(CycleAccuracyEngine.nextMilestone(cyclesLogged: 2), .establishing)
        XCTAssertEqual(CycleAccuracyEngine.nextMilestone(cyclesLogged: 3), .personalized)
        XCTAssertEqual(CycleAccuracyEngine.nextMilestone(cyclesLogged: 5), .personalized)
        // Six logged cycles = the full recent history in use; the ladder tops out.
        XCTAssertEqual(CycleAccuracyEngine.nextMilestone(cyclesLogged: 6), .personalized)
        XCTAssertEqual(CycleAccuracyEngine.nextMilestone(cyclesLogged: 9), .personalized)
    }

    func testEngineCountsTheRunningCycleAsLogged() {
        XCTAssertEqual(evaluate(cycleLengths: [], temps: []).0.cyclesLogged, 1)
        XCTAssertEqual(evaluate(cycleLengths: [28], temps: []).0.cyclesLogged, 2)
        XCTAssertEqual(evaluate(cycleLengths: [28, 28], temps: []).0.cyclesLogged, 3)
        XCTAssertEqual(evaluate(cycleLengths: [28, 28, 28, 28, 28], temps: []).0.cyclesLogged, 6)
        XCTAssertEqual(evaluate(cycleLengths: [], temps: []).0.nextMilestone, .establishing)
        XCTAssertEqual(evaluate(cycleLengths: [28], temps: []).0.nextMilestone, .establishing)
        XCTAssertEqual(evaluate(cycleLengths: [28, 28], temps: []).0.nextMilestone, .personalized)
        XCTAssertEqual(evaluate(cycleLengths: [28, 28, 28, 28, 28], temps: []).0.nextMilestone, .personalized)
    }

    // MARK: - Irregularity

    /// Strictly over 4 days of standard deviation: exactly 4 is still regular.
    func testIrregularityCutoffIsStrictlyOverFourDays() {
        // Population std of [26, 26, 34, 34] is exactly 4.0 → regular.
        XCTAssertFalse(CycleAccuracyEngine.isIrregular(lengths: [26, 26, 34, 34]))
        // [25, 27, 33, 35] → std ≈ 4.12 → irregular.
        XCTAssertTrue(CycleAccuracyEngine.isIrregular(lengths: [25, 27, 33, 35]))
        // Fewer than three lengths say nothing about regularity.
        XCTAssertFalse(CycleAccuracyEngine.isIrregular(lengths: [20, 40]))
        XCTAssertFalse(CycleAccuracyEngine.isIrregular(lengths: []))
    }

    func testEngineReadsRecentCycleLengths() {
        let irregular = evaluate(cycleLengths: [25, 27, 33, 35], temps: Array(repeating: 36.0 as Double?, count: 10)).0
        XCTAssertTrue(irregular.irregularCycleLengths)
        let regular = evaluate(cycleLengths: [26, 26, 34, 34], temps: Array(repeating: 36.0 as Double?, count: 10)).0
        XCTAssertFalse(regular.irregularCycleLengths)
    }

    // MARK: - The honest range (drawn band and stated accuracy agree)

    func testConfirmedSpreadConstantIsTwoDays() {
        // The audit's whole point, pinned: confirmed ovulation means ±2 everywhere.
        XCTAssertEqual(CycleAnalyzer.confirmedSpreadDays, 2)
    }

    func testConfirmedOvulationWidensTheDrawnBandToTwoDays() {
        let (accuracy, analysis) = evaluate(
            cycleLengths: [], temps: Array(repeating: 36.0 as Double?, count: 10)
                + Array(repeating: 36.5 as Double?, count: 8)
        )
        XCTAssertTrue(accuracy.ovulationConfirmed)
        let prediction = analysis.nextPeriod!
        XCTAssertEqual(prediction.earliest, calendar.date(byAdding: .day, value: -2, to: prediction.expected)!)
        XCTAssertEqual(prediction.latest, calendar.date(byAdding: .day, value: 2, to: prediction.expected)!)
        XCTAssertEqual(accuracy.predictionSpreadDays, 2)
        XCTAssertEqual(accuracy.periodRangeDays, 2)
    }

    func testStatisticalSpreadCarriesIntoTheStatedRange() {
        // Lengths with std ≈ 4.12 → the drawn spread is 4 days, and the card must state 4.
        let (accuracy, analysis) = evaluate(
            cycleLengths: [25, 27, 33, 35], temps: Array(repeating: 36.0 as Double?, count: 10)
        )
        XCTAssertFalse(accuracy.ovulationConfirmed)
        XCTAssertEqual(analysis.nextPeriod?.earliest,
                       calendar.date(byAdding: .day, value: -4, to: analysis.nextPeriod!.expected))
        XCTAssertEqual(accuracy.predictionSpreadDays, 4)
        XCTAssertEqual(accuracy.periodRangeDays, 4)
    }

    func testFirstCycleHasNoRangeToState() {
        let (accuracy, analysis) = evaluate(cycleLengths: [], temps: Array(repeating: 36.0 as Double?, count: 10))
        XCTAssertNil(analysis.nextPeriod)
        XCTAssertNil(accuracy.predictionSpreadDays)
        XCTAssertNil(accuracy.periodRangeDays)
    }

    func testStatedRangeNeverDisagreesWithTheDrawnBand() {
        // The invariant the card depends on: the half-width the copy states is exactly the
        // half-width of the drawn prediction band, for both confirmed and statistical paths.
        for fixture in [
            (lengths: [Int](), temps: [Double?](repeating: 36.0, count: 10) + [Double?](repeating: 36.5, count: 8)),
            (lengths: [25, 27, 33, 35], temps: [Double?](repeating: 36.0, count: 10)),
            (lengths: [28, 28], temps: [Double?](repeating: 36.0, count: 10))
        ] {
            let (accuracy, analysis) = evaluate(cycleLengths: fixture.lengths, temps: fixture.temps)
            let prediction = analysis.nextPeriod!
            XCTAssertEqual(
                accuracy.periodRangeDays,
                CycleAnalyzer.daysBetween(prediction.expected, prediction.latest, calendar: calendar),
                "lengths \(fixture.lengths)"
            )
        }
    }

    // MARK: - Sentences

    func testCoverageSentenceNamesTheLeverInEveryTier() {
        XCTAssertEqual(
            CycleCopy.coverageSentence(evaluate(cycleLengths: [], temps: Array(repeating: 36.0 as Double?, count: 10)).0),
            "Good coverage — 10 of 10 nights captured. Keep wearing the ring nightly."
        )
        var fairTemps = Array(repeating: 36.0 as Double?, count: 10)
        for index in 6..<10 { fairTemps[index] = nil }
        XCTAssertEqual(
            CycleCopy.coverageSentence(evaluate(cycleLengths: [], temps: fairTemps).0),
            "Fair coverage — 6 of 10 nights captured. Wearing the ring nightly sharpens the estimates."
        )
        var sparseTemps = Array(repeating: 36.0 as Double?, count: 10)
        for index in 5..<10 { sparseTemps[index] = nil }
        XCTAssertEqual(
            CycleCopy.coverageSentence(evaluate(cycleLengths: [], temps: sparseTemps).0),
            "Sparse data — 5 of 10 nights captured. Wearing the ring nightly is what fixes this."
        )
        XCTAssertEqual(
            CycleCopy.coverageSentence(evaluate(cycleLengths: [], temps: [36.0, 36.0, 36.0, 36.0]).0),
            "Not enough nights yet — under 5 nights since your period started. Wearing the ring nightly builds the picture."
        )
    }

    func testMilestoneSentences() {
        XCTAssertEqual(
            CycleCopy.milestoneSentence(evaluate(cycleLengths: [], temps: []).0),
            "First cycle underway — calendar predictions appear once it's logged."
        )
        XCTAssertEqual(
            CycleCopy.milestoneSentence(evaluate(cycleLengths: [28], temps: []).0),
            "Personal statistics arrive at cycle 3 — one more cycle to go."
        )
        XCTAssertEqual(
            CycleCopy.milestoneSentence(evaluate(cycleLengths: [28, 28], temps: []).0),
            "Personal statistics are live — full recent history joins at cycle 6 (3 more to go)."
        )
        XCTAssertEqual(
            CycleCopy.milestoneSentence(evaluate(cycleLengths: [28, 28, 28, 28, 28, 28], temps: []).0),
            "Full history unlocked — predictions now draw on your most recent cycles."
        )
    }

    func testIrregularitySentenceOnlyWhenIrregular() {
        let irregular = evaluate(cycleLengths: [25, 27, 33, 35], temps: Array(repeating: 36.0 as Double?, count: 10)).0
        XCTAssertEqual(
            CycleCopy.irregularitySentence(irregular),
            "Cycle lengths vary by more than 4 days, so ranges are drawn wider — the estimates stay, honestly uncertain."
        )
        let regular = evaluate(cycleLengths: [26, 26, 34, 34], temps: Array(repeating: 36.0 as Double?, count: 10)).0
        XCTAssertNil(CycleCopy.irregularitySentence(regular))
    }

    func testRangeSentenceMatchesTheDrawnBand() {
        let confirmed = evaluate(
            cycleLengths: [], temps: Array(repeating: 36.0 as Double?, count: 10)
                + Array(repeating: 36.5 as Double?, count: 8)
        ).0
        XCTAssertEqual(
            CycleCopy.rangeSentence(confirmed),
            "Ovulation is temperature-confirmed — the period window is tight: ±2 days."
        )
        let statistical = evaluate(
            cycleLengths: [25, 27, 33, 35], temps: Array(repeating: 36.0 as Double?, count: 10)
        ).0
        XCTAssertEqual(
            CycleCopy.rangeSentence(statistical),
            "Estimated from your statistics — the period can start within ±4 days of the date shown."
        )
        XCTAssertNil(CycleCopy.rangeSentence(evaluate(cycleLengths: [], temps: Array(repeating: 36.0 as Double?, count: 10)).0))
    }

    func testQualityLabels() {
        XCTAssertEqual(CycleAccuracy.Quality.good.label, "Good")
        XCTAssertEqual(CycleAccuracy.Quality.fair.label, "Fair")
        XCTAssertEqual(CycleAccuracy.Quality.sparse.label, "Sparse")
        XCTAssertEqual(CycleAccuracy.Quality.noData.label, "No data")
    }
}
