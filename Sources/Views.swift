
import SwiftUI
import StoreKit
import UIKit

// MARK: - Settings View
struct SettingsView: View {

    @EnvironmentObject var data: DataStore
    @EnvironmentObject var subs: SubscriptionManager

    // MARK: - Time Bindings

    private var dayStartBinding: Binding<Date> {
        timeBinding($data.settings.dayStart)
    }

    private var dayEndBinding: Binding<Date> {
        timeBinding($data.settings.dayEnd)
    }

    private var reminderBinding: Binding<Date> {
        timeBinding($data.settings.morningReminder)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                daySection

                notificationSection

                activitySection

                subscriptionSection

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)

            // Automatically save and replan when settings change.
            .onChange(of: data.settings.dayStart) { _, _ in apply() }
            .onChange(of: data.settings.dayEnd) { _, _ in apply() }
            .onChange(of: data.settings.dailyCapacity) { _, _ in apply() }
            .onChange(of: data.settings.notificationsOn) { _, _ in apply() }
            .onChange(of: data.settings.morningReminder) { _, _ in apply() }
            .onChange(of: data.settings.useCalendar) { _, _ in apply() }
            .onChange(of: data.settings.useHealth) { _, _ in apply() }
        }
    }

    // MARK: - Day Settings

    private var daySection: some View {
        Section {
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

        } header: {
            Label("Your day", systemImage: "sun.max")
        } footer: {
            Text("Set your available working hours and daily focus capacity.")
        }
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        Section {
            Toggle(
                "Enable reminders",
                isOn: $data.settings.notificationsOn
            )

            if data.settings.notificationsOn {
                DatePicker(
                    "Morning plan",
                    selection: reminderBinding,
                    displayedComponents: .hourAndMinute
                )
            }

        } header: {
            Label("Notifications", systemImage: "bell")
        } footer: {
            Text("Choose when GoalPilot should remind you to review your daily plan.")
        }
    }

    // MARK: - Activity Access

    private var activitySection: some View {
        Section {
            Toggle(
                "Read Calendar",
                isOn: $data.settings.useCalendar
            )

            Toggle(
                "Read Apple Health",
                isOn: $data.settings.useHealth
            )

        } header: {
            Label("Activity access", systemImage: "heart.text.square")
        } footer: {
            Text("""
            Calendar events are avoided when scheduling.
            Health exercise minutes count toward fitness goals.
            """)
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        Section {
            HStack {
                Text("Subscription status")

                Spacer()

                Text(subscriptionStatus)
                    .foregroundStyle(subs.isSubscribed ? .green : .secondary)
            }

            Button {
                Task {
                    await subs.restore()
                }
            } label: {
                Label("Restore purchases", systemImage: "arrow.clockwise")
            }

            Button {
                openSubscriptionManagement()
            } label: {
                Label("Manage subscription", systemImage: "creditcard")
            }

            if let error = subs.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

        } header: {
            Label("Subscription", systemImage: "crown")
        }
    }

    // MARK: - Subscription Status

    private var subscriptionStatus: String {
        if subs.inTrial {
            return "Free trial active"
        } else if subs.isSubscribed {
            return "Subscribed"
        } else {
            return "Inactive"
        }
    }

    // MARK: - Subscription Management

    private func openSubscriptionManagement() {
        guard let url = URL(
            string: "https://apps.apple.com/account/subscriptions"
        ) else {
            return
        }

        UIApplication.shared.open(url)
    }

    // MARK: - Save and Replan

    private func apply() {
        data.save()

        Task {
            await data.replan()
        }
    }
}

// MARK: - Time Binding Helper

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
