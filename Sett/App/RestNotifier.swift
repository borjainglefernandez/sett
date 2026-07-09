import Foundation
import UserNotifications

/// Tenet 1 ("rest runs itself") beyond the app boundary: schedules a local
/// notification for the moment rest ends, so a lifter who pockets the phone still
/// gets told to start the next set. Fires only on the lock screen / when
/// backgrounded — the in-app countdown + haptic already cover the foreground case.
///
/// Stage 1 of the roadmap's #1 item. The richer ActivityKit Live-Activity countdown
/// (Dynamic Island + a running lock-screen timer with the next-set ghost values) is
/// the sequenced follow-up; this is the zero-entitlement floor that ships today.
enum RestNotifier {
    private static let restID = "sett.rest.complete"

    /// Ask once; the system only ever prompts the first time. Called lazily when the
    /// first rest starts, so the prompt lands in context (not during onboarding).
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// (Re)schedule the rest-complete alert for `date`. Replaces any pending one, so
    /// this is also the reschedule path when the lifter adds/removes rest time.
    static func scheduleRestComplete(at date: Date, nextUp: String?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restID])
        let interval = date.timeIntervalSinceNow
        guard interval > 0.5 else { return }   // already over — nothing to fire

        let content = UNMutableNotificationContent()
        content.title = "REST COMPLETE"
        content.body = nextUp.map { "Next: \($0). The Chamber is ready." }
            ?? "The Chamber is ready. Log your next set."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: restID, content: content, trigger: trigger))
    }

    /// Cancel a pending rest alert — on skip, on finishing, or on abandoning.
    static func cancelRestComplete() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restID])
    }
}
