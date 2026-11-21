import Foundation
import SwiftData
import UserNotifications

/// Schedules the period-prediction notifications and handles their one-tap actions. The
/// "has it started?" prompt with a **Yes, log it** action *is* the feature's one-tap UX:
/// day 1 gets logged from the lock screen without opening the app.
///
/// Notification copy is deliberately discreet — a lock screen should not broadcast cycle
/// details beyond what the prompt needs.
@MainActor
final class CycleNotificationCenter {
    static let shared = CycleNotificationCenter()

    static let categoryIdentifier = "pulseloop.cycle.periodPrompt"
    static let actionStarted = "pulseloop.cycle.periodStarted"
    static let actionNotYet = "pulseloop.cycle.periodNotYet"
    static let dueRequestIdentifier = "pulseloop.cycle.periodDue"
    static let preAlertRequestIdentifier = "pulseloop.cycle.periodPreAlert"
    static let followUpRequestIdentifier = "pulseloop.cycle.periodFollowUp"
    /// Every prompt this center owns — the replace set for re-derivations and cancels.
    private static let allRequestIdentifiers = [dueRequestIdentifier, preAlertRequestIdentifier, followUpRequestIdentifier]
    /// Prompts deliver at 09:00 local on their day.
    private static let deliveryHour = 9
    /// The pre-alert fires this many days before the due date.
    private static let preAlertLeadDays = 2
    /// After an unlogged due date, exactly one follow-up fires this many days later.
    private static let followUpLagDays = 2

    /// Set once at app start; the notification delegate has no other path to the store.
    private var contextProvider: (() -> ModelContext)?

    func register(contextProvider: @escaping () -> ModelContext) {
        self.contextProvider = contextProvider
        registerCategory()
    }

    private func registerCategory() {
        let started = UNNotificationAction(identifier: Self.actionStarted, title: "Yes — log day 1", options: [])
        let notYet = UNNotificationAction(identifier: Self.actionNotYet, title: "Not yet", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [started, notYet],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            UNUserNotificationCenter.current().setNotificationCategories(existing.union([category]))
        }
    }

    /// Re-derive the prediction and (re)schedule the prompt(s). Called on app-active and
    /// after any cycle edit; always replaces what was previously pending so a changed
    /// prediction never leaves a stale notification behind.
    func scheduleNext() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.allRequestIdentifiers)

        let store = CycleSettingsStore.shared
        guard store.isActive, store.settings.periodPromptEnabled, let context = contextProvider?() else { return }
        guard CycleService.isAvailable(context: context) else { return }
        let overview = CycleService.overview(context: context)
        guard let prediction = overview.analysis?.nextPeriod else { return }

        let calendar = Calendar.current
        let loggedPeriodDays = CycleRepository.days(context: context)
            .filter(\.isPeriod)
            .map { calendar.startOfDay(for: $0.date) }
        let plan = Self.schedulePlan(
            prediction: prediction,
            loggedPeriodDays: loggedPeriodDays,
            now: Date(),
            preAlertEnabled: store.settings.preAlertEnabled,
            calendar: calendar
        )
        for prompt in plan { add(prompt, calendar: calendar) }
    }

    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.allRequestIdentifiers)
    }

    private func add(_ prompt: CycleScheduledPrompt, calendar: Calendar) {
        let content = UNMutableNotificationContent()
        content.title = "PulseLoop"
        content.body = prompt.body
        content.sound = .default
        if prompt.withActions { content.categoryIdentifier = Self.categoryIdentifier }

        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: prompt.deliverAt)
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: prompt.identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Route a notification action. "Yes" writes today's period day straight into the store —
    /// the app never needs to open.
    func handleAction(identifier: String) {
        guard identifier == Self.actionStarted, let context = contextProvider?() else { return }
        CycleRepository.logPeriodDay(on: Date(), context: context)
    }

    // MARK: - The scheduling decision (pure)

    /// Which prompts should be pending, decided as a pure function: given the fresh prediction,
    /// the logged period days, and now — nothing is read from storage, the clock, or
    /// UserNotifications, so every re-derivation is testable and idempotent.
    ///
    /// The rules:
    ///  - A period day logged on/after the prediction's earliest plausible day means the
    ///    predicted period arrived — cancel everything. This is what makes the follow-up
    ///    auto-cancel the moment any period day is logged, whenever it lands relative to the
    ///    due date. Days before that window are the cycle the prediction is derived from, not
    ///    an answer to it.
    ///  - Up to the due date: the "has it started?" prompt on the due morning (plus the
    ///    pre-alert two mornings ahead, when enabled).
    ///  - Once the due date passes unlogged: exactly one discreet follow-up, on the due+2
    ///    morning. Re-derivations produce the same single request — the caller's
    ///    replace-don't-accumulate removal turns that into "never a duplicate".
    ///  - A prompt whose 09:00 delivery has passed is never (re)scheduled: one that already
    ///    fired must not resurrect from a later foreground or data edit.
    static func schedulePlan(
        prediction: PeriodPrediction,
        loggedPeriodDays: [Date],
        now: Date,
        preAlertEnabled: Bool,
        calendar: Calendar
    ) -> [CycleScheduledPrompt] {
        let today = calendar.startOfDay(for: now)
        let earliest = calendar.startOfDay(for: prediction.earliest)
        let due = calendar.startOfDay(for: prediction.expected)
        let logged = loggedPeriodDays.map { calendar.startOfDay(for: $0) }.filter { $0 <= today }

        if logged.contains(where: { $0 >= earliest }) { return [] }

        var prompts: [CycleScheduledPrompt] = []
        func prompt(_ identifier: String, on day: Date, body: String, withActions: Bool) {
            guard let deliverAt = calendar.date(bySettingHour: Self.deliveryHour, minute: 0, second: 0, of: day),
                  deliverAt > now else { return }
            prompts.append(CycleScheduledPrompt(
                identifier: identifier, deliverAt: deliverAt, body: body, withActions: withActions
            ))
        }

        if due >= today {
            prompt(
                Self.dueRequestIdentifier, on: due,
                body: "Your period is due around today — has it started?", withActions: true
            )
        } else if let followUpDay = calendar.date(byAdding: .day, value: Self.followUpLagDays, to: due),
                  today <= followUpDay {
            prompt(
                Self.followUpRequestIdentifier, on: followUpDay,
                body: "Still nothing? Log day 1 if it has started.", withActions: true
            )
        }
        if preAlertEnabled,
           let preAlertDay = calendar.date(byAdding: .day, value: -Self.preAlertLeadDays, to: due) {
            prompt(
                Self.preAlertRequestIdentifier, on: preAlertDay,
                body: "Your period is likely in about 2 days.", withActions: false
            )
        }
        return prompts
    }
}

/// One prompt the plan wants pending: which request, when (09:00 local), what copy, and
/// whether it carries the one-tap actions. Pure data — no UserNotifications types.
struct CycleScheduledPrompt: Equatable {
    let identifier: String
    let deliverAt: Date
    let body: String
    let withActions: Bool
}
