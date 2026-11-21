import XCTest
@testable import PulseLoop

/// Copy guardrails and structure for the cycle setup tour. `CycleEducation` is plain data, so
/// the tests read like a specification of the tour itself: three pages in order, no banned
/// jargon, no accuracy over-promises, and the final page still carrying the gating disclaimer.
@MainActor
final class CycleEducationTests: XCTestCase {
    /// Every user-facing string in the module: page titles, section titles, paragraphs, plus
    /// the standalone lines the final page and later screens compose from.
    private var allCopy: [String] {
        var strings = CycleEducation.pages.flatMap { page in
            [page.title] + page.sections.flatMap { [$0.title] + $0.paragraphs }
        }
        strings += [
            CycleEducation.enableButtonTitle,
            CycleEducation.lutealLine,
            CycleEducation.ovulationAccuracyLine,
            CycleEducation.condensedDisclaimer,
        ]
        return strings
    }

    private func joined(_ strings: [String]) -> String {
        strings.joined(separator: "\n")
    }

    // MARK: - Structure

    func testTourHasThreePagesInFixedOrder() {
        XCTAssertEqual(CycleEducation.pages.count, 3)
        XCTAssertEqual(
            CycleEducation.pages.map(\.id),
            ["how-it-works", "what-you-log", "over-time"]
        )
    }

    func testEveryPageHasTitleAndNonEmptySections() {
        for page in CycleEducation.pages {
            XCTAssertFalse(page.title.isEmpty, "page \(page.id) needs a title")
            XCTAssertFalse(page.sections.isEmpty, "page \(page.id) needs content")
            for section in page.sections {
                XCTAssertFalse(section.title.isEmpty, "page \(page.id): untitled section")
                XCTAssertFalse(section.paragraphs.isEmpty, "page \(page.id): empty section \(section.id)")
            }
        }
    }

    func testFinalPageCarriesTheGatingDisclaimer() {
        let finalPage = CycleEducation.pages.last
        XCTAssertEqual(finalPage?.id, "over-time")
        // The condensed disclaimer is what the enable button gates — it must exist and be
        // genuinely shorter than the full text still shown in settings.
        XCTAssertFalse(CycleEducation.condensedDisclaimer.isEmpty)
        XCTAssertLessThan(
            CycleEducation.condensedDisclaimer.count,
            CycleSettingsView.disclaimerText.count,
            "the tour disclaimer should be a condensed version of the settings one"
        )
        XCTAssertEqual(CycleEducation.enableButtonTitle, "I understand — enable")
    }

    // MARK: - Copy guardrails

    func testBannedJargonNeverAppears() {
        let text = joined(allCopy)
        XCTAssertFalse(text.contains("cycle-length variability"), "banned jargon: cycle-length variability")
    }

    func testLutealLineUsesTheRecommendedWording() {
        let line = CycleEducation.lutealLine
        XCTAssertTrue(line.contains("the most predictable part of your cycle, typically 11–17 days, learned from your own data"))
        XCTAssertTrue(line.contains("one reason your period date is a range, not a single day"))
    }

    func testOvulationDatingIsRetrospectiveAndNeverTighterThanTwoDays() {
        let line = CycleEducation.ovulationAccuracyLine
        XCTAssertTrue(line.contains("±2 days"), "accuracy floor: ovulation dating is ±2 days retrospective")
        XCTAssertTrue(line.contains("after"), "ovulation dating must be retrospective, not a promise made in advance")
    }

    func testNoCopyOverPromisesAccuracy() {
        let text = joined(allCopy)
        XCTAssertFalse(text.contains("±1"), "never promise tighter than ±2 days")
        XCTAssertFalse(text.contains("exact day"), "never promise the exact day of anything")
        XCTAssertFalse(text.contains("pinpoint"), "never promise pinpoint accuracy")
    }

    func testPeriodLogsArePresentedAsTheAnchorInput() {
        let anchorPage = CycleEducation.pages.first { $0.id == "what-you-log" }
        let title = anchorPage?.title ?? ""
        let paragraphs = joined(anchorPage?.sections.flatMap(\.paragraphs) ?? [])
        let text = joined([title, paragraphs])
        XCTAssertTrue(text.contains("Day 1"), "day 1 must be named as the anchor")
        XCTAssertTrue(text.contains("anchor"), "period logging must be presented as the anchor input")
    }
}
