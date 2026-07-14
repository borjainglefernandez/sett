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
        #if DEBUG
        // Debug overview screenshots start rest synthetically; don't pop the auth prompt.
        if let f = ProcessInfo.processInfo.environment["SETT_DEBUG_OVERVIEW"], !f.isEmpty { return }
        #endif
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
        content.body = nextUp.map { "Next: \($0) — tap to return and log your set." }
            ?? "The Chamber is ready — tap to return and log your next set."
        content.sound = .default
        // Time-sensitive so it breaks through Focus / the notification summary — the
        // whole point is to pull the lifter back for the next set (degrades to a normal
        // alert without the entitlement).
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: restID, content: content, trigger: trigger))
    }

    /// Cancel a pending rest alert — on skip, on finishing, or on abandoning.
    static func cancelRestComplete() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restID])
    }
}


// MARK: - Weekly Power Reading (Monday morning scouter ping)

/// Schedules the repeating Monday-morning local notification that pairs with home's
/// Weekly Power Reading card. Idempotent — re-scheduling replaces the previous one.
enum WeeklyReadingNotifier {
    private static let id = "sett.weeklyReading"

    static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Weekly Power Reading"
            content.body = "The scanner has your week: ΔPL, form progress, and Vexeth's move."
            content.sound = .default
            var comps = DateComponents()
            comps.weekday = 2   // Monday
            comps.hour = 9
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
