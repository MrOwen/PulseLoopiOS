import Foundation

// MARK: - Result

/// How many cycles the user has logged, as rungs on a ladder. Each case is the next rung the
/// user climbs toward; `.personalized` is the top — once six cycles are logged the full recent
/// history is in use and the ladder stops growing.
enum CycleMilestone: Equatable {
    /// One logged cycle: calendar predictions appear.
    case first
    /// Three logged cycles: personal statistics (luteal, typical length) take over from defaults.
    case establishing
    /// Six logged cycles: predictions draw on the full recent history.
    case personalized
}

/// What the user's numbers are worth, derived in one pass off the render path. Pure: every
/// input arrives through `evaluate`, no store access, no clock reads. The cycle detail screen
/// renders this as a card, and the copy module turns it into sentences.
struct CycleAccuracy: Equatable {
    /// How much of the current cycle's nightly data actually exists.
    enum Quality: Equatable {
        case good
        case fair
        case sparse
        case noData

        var label: String {
            switch self {
            case .good: return "Good"
            case .fair: return "Fair"
            case .sparse: return "Sparse"
            case .noData: return "No data"
            }
        }
    }

    /// Completed cycles plus the one currently running.
    var cyclesLogged: Int
    var usableNights: Int
    var totalNights: Int
    var excludedNights: Int
    /// Recent cycle lengths vary (std > 4 days): ranges widen rather than estimates hiding.
    var irregularCycleLengths: Bool
    /// Half-width, in days, of the drawn prediction band — exactly what `PeriodPrediction`
    /// earliest/latest were built with.
    var predictionSpreadDays: Int?
    var ovulationConfirmed: Bool
    var quality: Quality
    var nextMilestone: CycleMilestone

    var coverageFraction: Double {
        guard totalNights > 0 else { return 0 }
        return Double(usableNights) / Double(totalNights)
    }

    /// The honest ±half-width stated next to the predictions: the shared confirmed constant
    /// once ovulation is temperature-confirmed, otherwise the statistical spread the band was
    /// drawn with. Reading it here (instead of restating a number) is what keeps the drawn
    /// band and the stated accuracy from ever disagreeing.
    var periodRangeDays: Int? {
        guard let predictionSpreadDays else { return nil }
        return ovulationConfirmed ? CycleAnalyzer.confirmedSpreadDays : predictionSpreadDays
    }
}

// MARK: - Engine

/// Derives `CycleAccuracy` from records + analysis in one pass. No I/O, no globals — the caller
/// (CycleService, off the render path) passes everything in, including the *unstripped* records
/// so coverage stays visible under hormonal contraception while fertility content hides.
enum CycleAccuracyEngine {
    /// Coverage at or above this is good; the gap down to the fair floor is the honest middle.
    static let goodCoverageThreshold = 0.85
    static let fairCoverageThreshold = 0.60
    /// Under this many nights in the cycle there is nothing to grade yet.
    static let noDataMinimumNights = 5
    /// Standard deviation of recent cycle lengths over which the word "irregular" is earned.
    static let irregularityStdThreshold = 4.0
    /// Recent cycles the irregularity check reads (same window the prediction spread uses).
    static let irregularityWindow = 6

    static func evaluate(
        days: [CycleDayRecord],
        analysis: CycleAnalysis?,
        today: Date,
        calendar: Calendar = .current
    ) -> CycleAccuracy? {
        guard let analysis else { return nil }
        let today = calendar.startOfDay(for: today)
        let currentCycle = days.filter { $0.date >= analysis.cycleStart && $0.date <= today }

        let totalNights = currentCycle.count
        let usableNights = currentCycle.filter(\.isValidTemperature).count
        let excludedNights = currentCycle.filter(\.isDisturbed).count

        let quality: CycleAccuracy.Quality
        if totalNights < noDataMinimumNights {
            quality = .noData
        } else {
            let coverage = Double(usableNights) / Double(totalNights)
            if coverage >= goodCoverageThreshold {
                quality = .good
            } else if coverage >= fairCoverageThreshold {
                quality = .fair
            } else {
                quality = .sparse
            }
        }

        // The spread exactly as it was drawn: half the width of the prediction band.
        let spread = analysis.nextPeriod.map {
            CycleAnalyzer.daysBetween($0.expected, $0.latest, calendar: calendar)
        }

        return CycleAccuracy(
            cyclesLogged: analysis.completedCycles.count + 1,
            usableNights: usableNights,
            totalNights: totalNights,
            excludedNights: excludedNights,
            irregularCycleLengths: isIrregular(
                lengths: analysis.completedCycles.suffix(irregularityWindow).map(\.lengthDays)
            ),
            predictionSpreadDays: spread,
            ovulationConfirmed: analysis.ovulation.isConfirmed,
            quality: quality,
            nextMilestone: nextMilestone(cyclesLogged: analysis.completedCycles.count + 1)
        )
    }

    /// The next rung of the milestone ladder; `.personalized` is the top, so six or more logged
    /// cycles stay there. Internal so the transitions are unit-testable in isolation.
    static func nextMilestone(cyclesLogged: Int) -> CycleMilestone {
        if cyclesLogged < 1 { return .first }
        if cyclesLogged < 3 { return .establishing }
        return .personalized
    }

    /// Recent cycle lengths vary when their population standard deviation clears the threshold
    /// (strictly over — exactly 4 is still regular). At least three lengths are needed before
    /// a spread means anything.
    static func isIrregular(lengths: [Int]) -> Bool {
        guard lengths.count >= 3 else { return false }
        let values = lengths.map(Double.init)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() > irregularityStdThreshold
    }
}
