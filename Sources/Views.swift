import SwiftUI
import StoreKit
import UIKit

 // MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var subs: SubscriptionManager

    private var dayStartBinding: Binding<Date> {
        timeBinding($data.settings.dayStart)
    }

    private var dayEndBinding: Binding<Date> {
        timeBinding($data.settings.dayEnd)
    }

    private var reminderBinding: Binding<Date> {
        timeBinding($data.settings.morningReminder)
    }

    var body: some View {
        NavigationStack {
            Form {
                daySection
                notificationSection
                activitySection
                subscriptionSection
            }
            .navigationTitle("Settings")
            .onChange(of: data.settings.dayStart) { _, _ in apply() }
            .onChange(of: data.settings.dayEnd) { _, _ in apply() }
            .onChange(of: data.settings.dailyCapacity) { _, _ in apply() }
            .onChange(of: data.settings.notificationsOn) { _, _ in apply() }
            .onChange(of: data.settings.morningReminder) { _, _ in apply() }
            .onChange(of: data.settings.useCalendar) { _, _ in apply() }
            .onChange(of: data.settings.useHealth) { _, _ in apply() }
        }
    }

    private var daySection: some View {
        Section("Your day") {
            DatePicker(
                "Day starts",
                selection: dayStartBinding,
                displayedComponents: .hourAndMinute
            )

            DatePicker(
                "Day ends",
                selection: dayEndBinding,
                displayedComponents: .hourAndMinute
            )

            Stepper(
                "Daily focus time: \(data.settings.dailyCapacity / 60)h \(data.settings.dailyCapacity % 60)m",
                value: $data.settings.dailyCapacity,
                in: 30...720,
                step: 30
            )
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            Toggle(
                "Enable reminders",
                isOn: $data.settings.notificationsOn
            )

            DatePicker(
                "Morning plan",
                selection: reminderBinding,
                displayedComponents: .hourAndMinute
            )
        }
    }

    private var activitySection: some View {
        Section(
            "Activity access",
            footer: Text("Calendar events are avoided when scheduling. Health exercise minutes count toward fitness goals.")
        ) {
            Toggle("Read Calendar", isOn: $data.settings.useCalendar)
            Toggle("Read Apple Health", isOn: $data.settings.useHealth)
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription") {
            Text(subs.inTrial ? "Free trial active" : "Subscribed")

            Button("Manage subscription") {
                guard let url = URL(
                    string: "https://apps.apple.com/account/subscriptions"
                ) else {
                    return
                }
                UIApplication.shared.open(url)
            }
        }
    }

    private func apply() {
        data.save()
        Task {
            await data.replan()
        }
    }
}

func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding<Date>(
        get: {
            let value = minutes.wrappedValue
            let hour = value / 60
            let minute = value % 60

            return Calendar.current.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: Date()
            ) ?? Date()
        },
        set: { newDate in
            let components = Calendar.current.dateComponents(
                [.hour, .minute],
                from: newDate
            )

            let hour = components.hour ?? 0
            let minute = components.minute ?? 0
            minutes.wrappedValue = hour * 60 + minute
        }
    )
}
