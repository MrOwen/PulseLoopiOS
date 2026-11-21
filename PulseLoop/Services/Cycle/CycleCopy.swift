import Foundation

/// Status copy shared by the Vitals card and the detail header. Pure so the priority order
/// (period > pregnancy hint > confirmation > rise > countdown > phase) is unit-testable.
enum CycleCopy {
    /// The single most useful line for "where am I?" — countdown first, jargon last.
    static func headline(
        _ analysis: CycleAnalysis,
        hormonal: Bool,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let today = calendar.startOfDay(for: today)
        if analysis.phase == .menstruation {
            return "Period — day \(analysis.dayNumber)"
        }
        if analysis.flags.contains(.possiblePregnancy) {
            return "High temps for 18+ days"
        }
        if hormonal {
            return "Cycle day \(analysis.dayNumber)"
        }
        if analysis.flags.contains(.longCycle) {
            return "Long cycle — waiting for data"
        }
        if case let .confirmed(_, confirmedOn) = analysis.ovulation,
           CycleAnalyzer.daysBetween(confirmedOn, today, calendar: calendar) <= 3 {
            return "Ovulation likely confirmed"
        }
        if let prediction = analysis.nextPeriod {
            let delta = CycleAnalyzer.daysBetween(today, prediction.expected, calendar: calendar)
            switch delta {
            case 2...: return "Period in ~\(delta) days"
            case 1: return "Period likely tomorrow"
            case 0: return "Period due today"
            default: return "Period \(-delta) day\(delta == -1 ? "" : "s") late"
            }
        }
        if case .probable = analysis.ovulation {
            return "Temperature rising"
        }
        if let window = analysis.fertileWindow, window.contains(today) {
            return "Fertile window"
        }
        if analysis.completedCycles.isEmpty {
            return "Learning your cycle"
        }
        return "Cycle day \(analysis.dayNumber)"
    }

    /// "Day 14 · Luteal" — the second line under the headline.
    static func subtitle(_ analysis: CycleAnalysis, hormonal: Bool, today: Date = Date(), calendar: Calendar = .current) -> String {
        hormonal
            ? "Day \(analysis.dayNumber) · analysis paused"
            : "Day \(analysis.dayNumber) · \(phaseLabel(analysis, hormonal: false, today: today, calendar: calendar))"
    }

    /// The phase word for the ring center and the subtitle. The thermal-shift rule (3-over-6)
    /// closes the fertile window on the *evening* of the confirming high day, so on that day
    /// "ovulation confirmed" and "fertile window" are both true — name the hinge instead of
    /// letting the two read as a contradiction.
    static func phaseLabel(
        _ analysis: CycleAnalysis,
        hormonal: Bool,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if hormonal { return "Tracking" }
        if analysis.phase == .fertile,
           case let .confirmed(_, confirmedOn) = analysis.ovulation,
           calendar.isDate(confirmedOn, inSameDayAs: today) {
            return "Fertile window · closes tonight"
        }
        return analysis.phase.label
    }

    /// Whether to surface the one-tap "My period started" button: around the predicted date
    /// (J-3 … onward), late without a prediction, or whenever nothing is known yet.
    static func shouldOfferPeriodStart(
        _ analysis: CycleAnalysis?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let analysis else { return true }
        let today = calendar.startOfDay(for: today)
        if analysis.phase == .menstruation { return false }
        if let prediction = analysis.nextPeriod {
            return CycleAnalyzer.daysBetween(prediction.expected, today, calendar: calendar) >= -3
        }
        return analysis.dayNumber >= 21
    }

    /// Longer explanations for the flag banners on the detail screen.
    static func flagMessage(_ flag: CycleFlag) -> String {
        switch flag {
        case .possiblePregnancy:
            return "Your temperature has stayed high for 18+ days after ovulation with no period logged. "
                + "A pregnancy test may be worth considering."
        case .noThermalShiftYet:
            return "No temperature shift detected this cycle so far. Cycles without a clear shift happen "
                + "and are usually nothing to worry about."
        case .longCycle:
            return "This cycle is running unusually long. Period estimates are on hold until a temperature "
                + "shift is confirmed or a new period is logged."
        }
    }

    // MARK: - Accuracy card

    /// Night-coverage sentence for the accuracy card. Every tier names the same
    /// user-controllable lever — wearing the ring nightly — because that is what moves it.
    static func coverageSentence(_ accuracy: CycleAccuracy) -> String {
        switch accuracy.quality {
        case .good:
            return "Good coverage — \(accuracy.usableNights) of \(accuracy.totalNights) nights captured. "
                + "Keep wearing the ring nightly."
        case .fair:
            return "Fair coverage — \(accuracy.usableNights) of \(accuracy.totalNights) nights captured. "
                + "Wearing the ring nightly sharpens the estimates."
        case .sparse:
            return "Sparse data — \(accuracy.usableNights) of \(accuracy.totalNights) nights captured. "
                + "Wearing the ring nightly is what fixes this."
        case .noData:
            return "Not enough nights yet — under 5 nights since your period started. "
                + "Wearing the ring nightly builds the picture."
        }
    }

    /// Where the user stands on the cycles-logged ladder. Says only what is already true:
    /// during the first cycle the calendar predictions have not appeared yet.
    static func milestoneSentence(_ accuracy: CycleAccuracy) -> String {
        switch accuracy.cyclesLogged {
        case 1:
            return "First cycle underway — calendar predictions appear once it's logged."
        case 2:
            return "Personal statistics arrive at cycle 3 — one more cycle to go."
        case 3..<6:
            let remaining = 6 - accuracy.cyclesLogged
            return "Personal statistics are live — full recent history joins at cycle 6 (\(remaining) more to go)."
        default:
            return "Full history unlocked — predictions now draw on your most recent cycles."
        }
    }

    /// Only earned when the recent lengths actually vary; `nil` keeps the card quiet otherwise.
    static func irregularitySentence(_ accuracy: CycleAccuracy) -> String? {
        guard accuracy.irregularCycleLengths else { return nil }
        return "Cycle lengths vary by more than 4 days, so ranges are drawn wider — the estimates stay, honestly uncertain."
    }

    /// The stated accuracy, reading the same half-width the drawn band uses. `nil` when there
    /// is no prediction to qualify yet.
    static func rangeSentence(_ accuracy: CycleAccuracy) -> String? {
        guard let rangeDays = accuracy.periodRangeDays else { return nil }
        if accuracy.ovulationConfirmed {
            return "Ovulation is temperature-confirmed — the period window is tight: ±\(rangeDays) days."
        }
        return "Estimated from your statistics — the period can start within ±\(rangeDays) days of the date shown."
    }
}
