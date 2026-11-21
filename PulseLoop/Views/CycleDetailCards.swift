import SwiftUI

/// The cycle detail screen's self-contained cards, extracted from `CycleDetailView` to keep
/// that struct small: each is a thin render of engine data plus copy-module sentences, with
/// every decision still living in `CycleAccuracyEngine` / `CycleAnalyzer` / `CycleEducation`.

/// What the numbers are worth: coverage quality, the honest period range, the irregularity
/// note, the milestone ladder. A thin render of engine data (`CycleAccuracy`) plus
/// copy-module sentences — every decision lives in `CycleAccuracyEngine` / `CycleCopy`.
/// Under hormonal contraception the coverage stays visible (the ring still collects nights)
/// while the fertility-side sentences hide.
struct CycleAccuracyCard: View {
    let accuracy: CycleAccuracy
    let hormonal: Bool

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("How good is this data?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                    Text(accuracy.quality.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(qualityColor(accuracy.quality))
                }
                Text(CycleCopy.coverageSentence(accuracy))
                    .font(.system(size: 13))
                    .foregroundStyle(PulseColors.textSecondary)
                if !hormonal {
                    if let range = CycleCopy.rangeSentence(accuracy) {
                        Text(range)
                            .font(.system(size: 13))
                            .foregroundStyle(PulseColors.textSecondary)
                    }
                    if let irregular = CycleCopy.irregularitySentence(accuracy) {
                        Text(irregular)
                            .font(.system(size: 13))
                            .foregroundStyle(PulseColors.warning)
                    }
                }
                Text(CycleCopy.milestoneSentence(accuracy))
                    .font(.system(size: 11))
                    .foregroundStyle(PulseColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func qualityColor(_ quality: CycleAccuracy.Quality) -> Color {
        switch quality {
        case .good: return PulseColors.success
        case .fair: return PulseColors.info
        case .sparse: return PulseColors.warning
        case .noData: return PulseColors.textMuted
        }
    }
}

/// The setup tour's facts restated compactly at the bottom of the screen: one PulseCard
/// with a collapsed disclosure per tour page, so a number here can always be traced back
/// to how it works without leaving the app. Copy comes straight from `CycleEducation` —
/// no second hand-written version — and the hormonal gating is decided in the module.
struct CycleReferenceCard: View {
    let hormonal: Bool

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(CycleEducation.referenceTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                ForEach(CycleEducation.referencePages(hormonal: hormonal)) { page in
                    referencePageDisclosure(page)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func referencePageDisclosure(_ page: CycleEducationPage) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(page.sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                        ForEach(section.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.system(size: 12))
                                .foregroundStyle(PulseColors.textSecondary)
                                .lineSpacing(3)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text(page.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PulseColors.textSecondary)
        }
        .tint(PulseColors.textSecondary)
    }
}

/// The past-cycles list: one row per completed cycle with its start, length, and estimated
/// ovulation day, plus the typical-length summary. A thin render of `CycleAnalysis`.
struct CycleHistoryCard: View {
    let analysis: CycleAnalysis

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Past cycles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                ForEach(analysis.completedCycles.suffix(6).reversed()) { cycle in
                    HStack {
                        Text(cycle.start.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                            .font(.system(size: 13))
                            .foregroundStyle(PulseColors.textSecondary)
                        Spacer()
                        if let luteal = cycle.lutealDays {
                            Text("luteal \(luteal) d")
                                .font(.system(size: 11))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        Text("\(cycle.lengthDays) days")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                }
                if let typical = analysis.typicalCycleLengthDays {
                    Text("Typical length \(typical) days · luteal phase \(analysis.lutealLengthDays) days")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
