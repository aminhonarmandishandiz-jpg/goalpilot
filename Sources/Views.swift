import SwiftUI
import StoreKit

// MARK: - Paywall
struct PaywallView: View {
    @EnvironmentObject var subs: SubscriptionManager
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "target").font(.system(size: 64)).foregroundStyle(.tint).padding(.top, 40)
                Text("GoalPilot").font(.largeTitle.bold())
                Text("Plan your day around every goal.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    feature("target", "Unlimited personal & business goals")
                    feature("calendar.badge.clock", "Smart daily routine, built around your calendar")
                    feature("chart.bar.fill", "Progress bar for every goal")
                    feature("exclamationmark.triangle", "Life-event mode re-plans all goals instantly")
                    feature("bell.badge", "Reminders for blocks and deadlines")
                    feature("heart.fill", "Auto-credit exercise from Apple Health")
                }.padding()
                ForEach(subs.products) { p in
                    Button {
                        busy = true
                        Task { await subs.purchase(p); busy = false }
                    } label: {
                        VStack {
                            Text(subs.trialText(p)).bold()
                            Text("then \(p.displayPrice) / \(p.subscription?.subscriptionPeriod.unit == .year ? "year" : "month")")
                                .font(.footnote)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).disabled(busy)
                }
                if subs.products.isEmpty { Text("Loading plans…").foregroundStyle(.secondary) }
                if let e = subs.error { Text(e).foregroundStyle(.red).font(.footnote) }
                Button("Restore Purchases") { Task { await subs.restore() } }
                #if TESTBUILD
                Button("Skip paywall (test build only)") { subs.testBypass = true }.foregroundStyle(.orange)
                #endif
                Text("Free for 7 days, then your subscription renews automatically unless cancelled at least 24 hours before the trial ends. Manage in Settings > Apple ID > Subscriptions.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Link("Terms", destination: URL(string: "https://example.com/terms")!)
                    Link("Privacy", destination: URL(string: "https://example.com/privacy")!)
                }.font(.caption)
            }.padding()
        }
    }
    private func feature(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.subheadline)
    }
}

// MARK: - Today
struct TodayView: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var subs: SubscriptionManager
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if subs.inTrial { Label("Free trial active", systemImage: "gift").font(.footnote) }
                Section {
                    VStack(alignment: .leading) {
                        Text("Overall progress").font(.headline)
                        ProgressView(value: data.overallProgress)
                        Text("\(Int(data.overallProgress * 100))% across \(data.goals.count) goals").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !data.activeDisruptions.isEmpty {
                    Section {
                        ForEach(data.activeDisruptions) { d in
                            Label("\(d.title): capacity reduced \(Int(d.capacityLoss * 100))%", systemImage: d.kind.icon)
                                .foregroundStyle(.orange)
                        }
                        Text("Today's capacity: \(data.todayCapacity) min. Plan adjusted automatically.").font(.caption)
                    }
                }
                Section("Today's routine") {
                    if data.plan.isEmpty { Text("Add a goal to generate your routine.").foregroundStyle(.secondary) }
                    ForEach(data.plan) { item in
                        if let g = data.goal(item.goalID) {
                            Button { data.toggle(item) } label: {
                                HStack {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(g.color)
                                    VStack(alignment: .leading) {
                                        Text(g.title).strikethrough(item.done)
                                        Text("\(item.start.formatted(date: .omitted, time: .shortened)) · \(item.minutes) min")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section("Goal progress") {
                    ForEach(data.goals) { GoalRow(goal: $0) }
                }
            }
            .navigationTitle("Today")
            .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showAdd) { AddGoalView() }
            .refreshable { await data.replan() }
        }
    }
}

struct GoalRow: View {
    @EnvironmentObject var data: DataStore
    let goal: Goal
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: goal.type.icon).foregroundStyle(goal.color)
                Text(goal.title).font(.headline)
                Spacer()
                Text(data.status(goal).rawValue).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(data.status(goal).color.opacity(0.2), in: Capsule())
            }
            ProgressView(value: goal.progress).tint(goal.color)
            HStack {
                Text("\(Int(goal.progress * 100))%")
                Spacer()
                Text("Due \(goal.deadline.formatted(date: .abbreviated, time: .omitted))")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Goals
struct GoalsView: View {
    @EnvironmentObject var data: DataStore
    @State private var showAdd = false
    var body: some View {
        NavigationStack {
            List {
                ForEach(GoalType.allCases) { type in
                    let items = data.goals.filter { $0.type == type }
                    if !items.isEmpty {
                        Section(type.rawValue) {
                            ForEach(items) { g in
                                NavigationLink { GoalDetailView(goalID: g.id) } label: { GoalRow(goal: g) }
                            }.onDelete { idx in idx.forEach { data.delete(items[$0]) } }
                        }
                    }
                }
                if data.goals.isEmpty { Text("No goals yet. Tap + to add one.").foregroundStyle(.secondary) }
            }
            .navigationTitle("Goals")
            .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showAdd) { AddGoalView() }
        }
    }
}

struct AddGoalView: View {
    @EnvironmentObject var data: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var type = GoalType.personal
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    @State private var hours = 20
    @State private var priority = 2
    @State private var tracksExercise = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal (e.g. Run a 10K, Launch my shop)", text: $title)
                Picker("Type", selection: $type) { ForEach(GoalType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                DatePicker("Reach it by", selection: $deadline, in: Date()..., displayedComponents: .date)
                Stepper("Total effort: \(hours) h", value: $hours, in: 1...2000, step: 5)
                Picker("Priority", selection: $priority) { Text("Low").tag(1); Text("Medium").tag(2); Text("High").tag(3) }.pickerStyle(.segmented)
                if type == .personal { Toggle("Auto-count exercise from Health", isOn: $tracksExercise) }
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        data.add(Goal(title: title, type: type, deadline: deadline, totalMinutes: hours * 60,
                                      priority: priority, tracksExercise: tracksExercise))
                        dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct GoalDetailView: View {
    @EnvironmentObject var data: DataStore
    let goalID: UUID
    var body: some View {
        if let g = data.goal(goalID) {
            List {
                Section {
                    ProgressView(value: g.progress).tint(g.color).scaleEffect(y: 2)
                    Text("\(Int(g.progress * 100))% · \(g.doneMinutes / 60)h \(g.doneMinutes % 60)m of \(g.totalMinutes / 60)h")
                    Label(data.status(g).rawValue, systemImage: "flag.fill").foregroundStyle(data.status(g).color)
                    if let f = data.projectedFinish(g), f > g.deadline {
                        Label("At your current capacity you'd finish ~\(f.formatted(date: .abbreviated, time: .omitted)). Consider extending the deadline or reducing other goals.",
                              systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section("Log time") {
                    HStack { ForEach([15, 30, 60], id: \.self) { m in
                        Button("+\(m)m") { data.log(m, to: g) }.buttonStyle(.bordered)
                    } }
                }
                Section { Button("Delete goal", role: .destructive) { data.delete(g) } }
            }.navigationTitle(g.title)
        }
    }
}

// MARK: - Unpredicted situations
struct DisruptionsView: View {
    @EnvironmentObject var data: DataStore
    @State private var showAdd = false
    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("Life happens. Log an unexpected event and every goal is re-planned around your reduced capacity.")) {
                    ForEach(data.disruptions) { d in
                        HStack {
                            Image(systemName: d.kind.icon).foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(d.title).font(.headline)
                                Text("\(d.start.formatted(date: .abbreviated, time: .omitted)) – \(d.end.formatted(date: .abbreviated, time: .omitted)) · -\(Int(d.capacityLoss * 100))% capacity")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { $0.forEach { data.delete(data.disruptions[$0]) } }
                }
                if data.loadFactor > 1 {
                    Label("Your goals need \(Int(data.loadFactor * 100))% of today's capacity. Consider extending deadlines.",
                          systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Life Events")
            .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showAdd) { AddDisruptionView() }
        }
    }
}

struct AddDisruptionView: View {
    @EnvironmentObject var data: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var kind = Disruption.Kind.illness
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
    @State private var loss = 0.5
    var body: some View {
        NavigationStack {
            Form {
                TextField("What happened?", text: $title)
                Picker("Kind", selection: $kind) { ForEach(Disruption.Kind.allCases) { Text($0.rawValue).tag($0) } }
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("Until", selection: $end, in: start..., displayedComponents: .date)
                VStack(alignment: .leading) {
                    Text("Time lost per day: \(Int(loss * 100))%")
                    Slider(value: $loss, in: 0.1...1, step: 0.1)
                }
            }
            .navigationTitle("Log Disruption")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        data.add(Disruption(title: title.isEmpty ? kind.rawValue : title, kind: kind, start: start, end: end, capacityLoss: loss))
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var subs: SubscriptionManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Your day") {
                    DatePicker("Day starts", selection: timeBinding($data.settings.dayStart), displayedComponents: .hourAndMinute)
                    DatePicker("Day ends", selection: timeBinding($data.settings.dayEnd), displayedComponents: .hourAndMinute)
                    Stepper("Daily focus time: \(data.settings.dailyCapacity / 60)h \(data.settings.dailyCapacity % 60)m",
                            value: $data.settings.dailyCapacity, in: 30...720, step: 30)
                }
                Section("Notifications") {
                    Toggle("Enable reminders", isOn: $data.settings.notificationsOn)
                    DatePicker("Morning plan", selection: timeBinding($data.settings.morningReminder), displayedComponents: .hourAndMinute)
                }
                Section("Activity access", footer: Text("Calendar events are avoided when scheduling. Health exercise minutes count toward fitness goals.")) {
                    Toggle("Read Calendar", isOn: $data.settings.useCalendar)
                    Toggle("Read Apple Health", isOn: $data.settings.useHealth)
                }
                Section("Subscription") {
                    Text(subs.inTrial ? "Free trial active" : "Subscribed")
                    Button("Manage subscription") {
                        if let u = URL(string: "https://apps.apple.com/account/subscriptions") { UIApplication.shared.open(u) }
                    }
                }
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
    private func apply() { data.save(); Task { await data.replan() } }
}

func timeBinding(_ m: Binding<Int>) -> Binding<Date> {
    Binding(
        get: { Calendar.current.date(bySettingHour: m.wrappedValue / 60, minute: m.wrappedValue % 60, second: 0, of: Date())! },
        set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); m.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    )
}
