
import SwiftUI
import StoreKit

// MARK: - Today View

struct TodayView: View {
    @EnvironmentObject var data: DataStore

    var body: some View {
        NavigationStack {
            List {
                Section("Today's plan") {
                    if data.plan.isEmpty {
                        ContentUnavailableView(
                            "No tasks scheduled",
                            systemImage: "calendar",
                            description: Text("Your daily plan will appear here.")
                        )
                    } else {
                        ForEach(data.plan) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(
                                        data.goals.first {
                                            $0.id == item.goalID
                                        }?.title ?? "Goal"
                                    )
                                    Text("\(item.minutes) minutes")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    data.togglePlanItem(item.id)
                                } label: {
                                    Image(systemName:
                                        item.done
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                    )
                                    .foregroundStyle(item.done ? .green : .secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
        }
    }
}

// MARK: - Goals View

struct GoalsView: View {
    @EnvironmentObject var data: DataStore
    @State private var showingAddGoal = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(data.goals) { goal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: goal.type.icon)
                            Text(goal.title)
                                .font(.headline)
                            Spacer()
                            Text(goal.isComplete ? "Completed" : goal.remainingMinutes.description + " min left")
                                .font(.caption)
                        }

                        ProgressView(value: goal.progress)
                            .tint(goal.color)

                        Text(goal.deadline.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    data.goals.remove(atOffsets: offsets)
                    data.save()
                    Task { await data.replan() }
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddGoal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView()
            }
        }
    }
}

// MARK: - Add Goal View

struct AddGoalView: View {
    @EnvironmentObject var data: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var type: GoalType = .personal
    @State private var deadline = Calendar.current.date(
        byAdding: .day,
        value: 30,
        to: Date()
    ) ?? Date()
    @State private var minutes = 600
    @State private var priority = 2

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal title", text: $title)

                Picker("Goal type", selection: $type) {
                    ForEach(GoalType.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }

                DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)

                Stepper("Estimated effort: \(minutes) minutes", value: $minutes, in: 30...10000, step: 30)

                Picker("Priority", selection: $priority) {
                    Text("Low").tag(1)
                    Text("Medium").tag(2)
                    Text("High").tag(3)
                }
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let goal = Goal(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            type: type,
                            deadline: deadline,
                            totalMinutes: minutes,
                            priority: priority
                        )

                        data.goals.append(goal)
                        data.save()

                        Task {
                            await data.replan()
                        }

                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Disruptions View

struct DisruptionsView: View {
    @EnvironmentObject var data: DataStore
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(data.disruptions) { disruption in
                    VStack(alignment: .leading) {
                        Label(
                            disruption.title,
                            systemImage: disruption.kind.icon
                        )

                        Text(
                            "\(disruption.start.formatted(date: .abbreviated, time: .omitted)) – \(disruption.end.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(
                            "\(Int(disruption.capacityLoss * 100))% capacity reduction"
                        )
                        .font(.caption)
                    }
                }
                .onDelete { offsets in
                    data.disruptions.remove(atOffsets: offsets)
                    data.save()
                    Task { await data.replan() }
                }
            }
            .navigationTitle("Life Events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddDisruptionView()
            }
        }
    }
}

// MARK: - Add Disruption View

struct AddDisruptionView: View {
    @EnvironmentObject var data: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: Disruption.Kind = .other
    @State private var start = Date()
    @State private var end = Date()
    @State private var capacityLoss = 0.5

    var body: some View {
        NavigationStack {
            Form {
                TextField("Event title", text: $title)

                Picker("Event type", selection: $kind) {
                    ForEach(Disruption.Kind.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }

                DatePicker("Start", selection: $start, displayedComponents: .date)

                DatePicker("End", selection: $end, in: start..., displayedComponents: .date)

                VStack(alignment: .leading) {
                    Text("Daily capacity reduction: \(Int(capacityLoss * 100))%")
                    Slider(value: $capacityLoss, in: 0...1, step: 0.05)
                }
            }
            .navigationTitle("New Life Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let event = Disruption(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            kind: kind,
                            start: start,
                            end: end,
                            capacityLoss: capacityLoss
                        )

                        data.disruptions.append(event)
                        data.save()

                        Task {
                            await data.replan()
                        }

                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end < start)
                }
            }
        }
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @EnvironmentObject var subs: SubscriptionManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "target")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Unlock GoalPilot")
                    .font(.largeTitle.bold())

                Text("Plan your goals, organize your day and stay on track.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if subs.products.isEmpty {
                    ProgressView("Loading subscriptions...")
                } else {
                    ForEach(subs.products, id: \.id) { product in
                        Button {
                            Task {
                                await subs.purchase(product)
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Text(product.displayName)
                                    .font(.headline)

                                Text(product.displayPrice)
                                    .font(.subheadline)

                                Text(subs.trialText(product))
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                Button("Restore Purchases") {
                    Task {
                        await subs.restore()
                    }
                }

                if let error = subs.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()
            .navigationTitle("GoalPilot Premium")
        }
    }
}
