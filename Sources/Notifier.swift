import UserNotifications

enum Notifier {
    static func requestAuth() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(goals: [Goal], plan: [PlanItem], settings: AppSettings) async {
        let c = UNUserNotificationCenter.current()
        c.removeAllPendingNotificationRequests()
        guard settings.notificationsOn, await requestAuth() else { return }
        let cal = Calendar.current

        func add(_ id: String, _ title: String, _ body: String, _ comps: DateComponents, repeats: Bool) {
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
            c.add(UNNotificationRequest(identifier: id, content: content, trigger: trig))
        }

        // Morning plan + evening check-in (daily)
        add("morning", "Your plan is ready", "Open GoalPilot to see today's routine.",
            DateComponents(hour: settings.morningReminder / 60, minute: settings.morningReminder % 60), repeats: true)
        add("evening", "Evening check-in", "Tick off what you finished and log any disruptions.",
            DateComponents(hour: 21, minute: 0), repeats: true)

        // Reminder for each upcoming block today
        for item in plan where !item.done && item.start > Date() {
            let name = goals.first { $0.id == item.goalID }?.title ?? "Goal"
            add("block-\(item.id)", "Time for: \(name)", "\(item.minutes) min focus block starts now.",
                cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.start), repeats: false)
        }

        // Deadline warnings: 3 days and 1 day before
        for g in goals where !g.isComplete {
            for d in [3, 1] {
                guard let date = cal.date(byAdding: .day, value: -d, to: g.deadline),
                      var comps = Optional(cal.dateComponents([.year, .month, .day], from: date)),
                      date > Date() else { continue }
                comps.hour = 9
                add("deadline-\(g.id)-\(d)", "\(g.title): \(d) day\(d > 1 ? "s" : "") left",
                    "You're at \(Int(g.progress * 100))%. Keep going!", comps, repeats: false)
            }
        }
    }
}
