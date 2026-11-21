import Foundation

/// One titled block of education copy: a heading with the paragraphs that follow it.
struct CycleEducationSection: Equatable, Identifiable {
    let id: String
    let title: String
    let paragraphs: [String]
}

/// One page of the cycle education: a title and its sections, in reading order.
struct CycleEducationPage: Equatable, Identifiable {
    let id: String
    let title: String
    let sections: [CycleEducationSection]
}

/// The cycle-education copy as plain data: the three setup-tour pages (how it works → what
/// you log → what to expect) plus the standalone lines the final page composes. Pure strings,
/// so the copy guardrails are unit-testable — and the cycle detail screen reuses the same
/// content instead of a second hand-written version. House rules: jargon-free, ovulation
/// dating never promised tighter than ±2 days retrospective, period day 1 presented as the
/// anchor input.
enum CycleEducation {
    /// The three tour pages, in the order the enable flow walks them.
    static let pages: [CycleEducationPage] = [howItWorks, whatYouLog, overTime]

    /// Title of the button that accepts the disclaimer and turns the feature on —
    /// the master switch stays gated behind it.
    static let enableButtonTitle = "I understand — enable"

    /// The luteal phase, described without the name: the spec's recommended wording.
    static let lutealLine = "The stretch after the temperature rise is the most predictable part "
        + "of your cycle, typically 11–17 days, learned from your own data — still shifts a day "
        + "or two, occasionally runs short — one reason your period date is a range, not a single day."

    /// Honest accuracy for ovulation: retrospective only, never tighter than ±2 days.
    static let ovulationAccuracyLine = "The rise can only be dated in hindsight, to within about "
        + "±2 days after it happened — PulseLoop never promises more precision, and never guesses "
        + "the day in advance."

    /// The disclaimer as it appears on the final tour page — condensed from the full text that
    /// stays on the settings screen, but still the thing "I understand — enable" gates.
    static let condensedDisclaimer = "PulseLoop estimates your cycle phases from the skin "
        + "temperature your ring measures at night. These are indicators, not certainties — they "
        + "depend on your sleep, the ring, and your physiology. Not a medical device and not "
        + "clinically validated; never use them on their own for contraception or medical "
        + "decisions. Talk to a healthcare professional about anything medical."

    /// Title of the cycle detail screen's reference card — the collapsed entry point for the
    /// same facts the tour walks through. Deliberately not any page's title.
    static let referenceTitle = "How PulseLoop works"

    /// The pages the detail screen's reference card shows, in tour order — the tour pages
    /// themselves, never copies. Under hormonal contraception the temperature analysis is
    /// paused, so the pages about the temperature signal and the fertility-accuracy fine
    /// print are dropped; the gating is decided here as plain data, the view only renders.
    static func referencePages(hormonal: Bool) -> [CycleEducationPage] {
        guard hormonal else { return pages }
        return pages
            .filter { $0.id != "how-it-works" }
            .map { page in
                guard page.id == "over-time" else { return page }
                return CycleEducationPage(
                    id: page.id,
                    title: page.title,
                    sections: page.sections.filter { $0.id != "honest-accuracy" }
                )
            }
    }

    // MARK: - Pages

    private static let howItWorks = CycleEducationPage(
        id: "how-it-works",
        title: "How it works",
        sections: [
            CycleEducationSection(
                id: "ring-measures",
                title: "The ring does the measuring",
                paragraphs: [
                    "While you sleep, your ring measures your skin temperature — every night, "
                        + "with nothing to remember. PulseLoop reads those nights and looks for "
                        + "a small, sustained rise that typically happens after ovulation.",
                ]
            ),
            CycleEducationSection(
                id: "looks-back",
                title: "Confirmation looks back, not forward",
                paragraphs: [
                    "A rise only counts once it has held for a few nights, so it is confirmed a "
                        + "couple of days after it begins — always looking back at what already "
                        + "happened, never forward. By the time it is confirmed, the fertile "
                        + "days are behind you, which is why PulseLoop leans on the steadier "
                        + "second half of your cycle for its estimates.",
                ]
            ),
        ]
    )

    private static let whatYouLog = CycleEducationPage(
        id: "what-you-log",
        title: "What you log and why it matters",
        sections: [
            CycleEducationSection(
                id: "day-one-anchor",
                title: "Day 1 is the anchor",
                paragraphs: [
                    "The only thing you must log is when your period starts. Day 1 anchors a new "
                        + "cycle: every phase, estimate and average is measured from it. You only "
                        + "log period days — everything else is passive.",
                ]
            ),
            CycleEducationSection(
                id: "rough-nights-spotting",
                title: "Rough nights and spotting",
                paragraphs: [
                    "If you slept badly, drank alcohol, or felt ill, mark the night as disturbed — "
                        + "PulseLoop sets it aside instead of letting it blur the picture.",
                    "Logging spotting helps too: it keeps a light day from being mistaken for "
                        + "day 1 of a new period.",
                ]
            ),
        ]
    )

    private static let overTime = CycleEducationPage(
        id: "over-time",
        title: "What to expect over time",
        sections: [
            CycleEducationSection(
                id: "first-weeks",
                title: "The first weeks",
                paragraphs: [
                    "At first the app simply watches: you'll see your cycle day and a calendar "
                        + "of what you logged. Nothing is predicted yet.",
                ]
            ),
            CycleEducationSection(
                id: "milestone-ladder",
                title: "Step by step",
                paragraphs: [
                    "With two or three periods logged, PulseLoop starts estimating your next "
                        + "period — at first as a wide range, which narrows as more history "
                        + "builds up.",
                ]
            ),
            CycleEducationSection(
                id: "honest-accuracy",
                title: "How accurate it really is",
                paragraphs: [lutealLine, ovulationAccuracyLine],
            ),
        ]
    )
}
