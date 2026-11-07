
import Foundation
import Combine

// MARK: - Data Store

@MainActor
final class DataStore: ObservableObject {

    // MARK: Published Data

    @Published var goals: [Goal] = []
    @Published var disruptions: [Disruption] = []
    @Published var plan: [PlanItem] = []
    @Published var settings = AppSettings()
    @Published var busy: [DateInterval] = []

    private var planDay = Calendar.current.startOfDay(for: Date())
    private var credited: [String: Int] = [:]

    // MARK: Persistence

    private struct Snapshot: Codable {
        var goals: [Goal]
        var disruptions: [Disruption]
        var plan: [PlanItem]
        var planDay: Date
        var settings: AppSettings
        var credited: [String: Int]
    }

    private static var url: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("goalpilot.json")
    }

    init() {
        load()
    }

    func load() {
        guard
            let data = try? Data(contentsOf: Self.url),
            let snapshot = try? JSONDecoder().decode(
                Snapshot.self,
                from: data
            )
        else {
            return
        }

        goals = snapshot.goals
        disruptions = snapshot.disruptions
        plan = snapshot.plan
        planDay = snapshot.planDay
        settings = snapshot.settings
        credited = snapshot.credited
    }

    func save() {
        let snapshot = Snapshot(
            goals: goals,
            disruptions: disruptions,
            plan: plan,
            planDay: planDay,
            settings: settings,
            credited: credited
        )

        do {
            let encoded = try JSONEncoder().encode(snapshot)

            try encoded.write(
                to: Self.url,
                options: .atomic
            )
        } catch {
            print("GoalPilot save error: \(error.localizedDescription)")
        }
    }

    // MARK: Derived Properties

    var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var activeGoals: [Goal] {
        goals.filter { !$0.isComplete }
    }

    var overallProgress: Double {
        guard !goals.isEmpty else { return 0 }

        return goals.reduce(0) {
            $0 + $1.progress
        } / Double(goals.count)
    }

    var todayCapacity: Int {
        Planner.capacity(
            settings,
            disruptions,
            day: today
        )
    }

    var activeDisruptions: [Disruption] {
        disruptions.filter {
            $0.isActive(on: today)
        }
    }

    func goal(_ id: UUID) -> Goal? {
        goals.first {
            $0.id == id
        }
    }

    // MARK: Goal Calculations

    private func perDayNeed(_ goal: Goal) -> Double {
        Double(goal.remainingMinutes) /
        Double(goal.daysLeft())
    }

    /// Greater than 1 means demand exceeds daily capacity.
    var loadFactor: Double {
        let need = activeGoals.reduce(0) {
            $0 + perDayNeed($1)
        }

        guard todayCapacity > 0 else {
            return need > 0 ? 9 : 0
        }

        return need / Double(todayCapacity)
    }

    func status(_ goal: Goal) -> GoalStatus {
        if goal.isComplete {
            return .done
        }

        switch loadFactor {
        case ...1.0:
            return .onTrack

        case ...1.25:
            return .atRisk

        default:
            return .behind
        }
    }

    /// Estimates the goal completion date.
    func projectedFinish(_ goal: Goal) -> Date? {
        let total = activeGoals.reduce(0) {
            $0 + perDayNeed($1)
        }

        guard
            total > 0,
            todayCapacity > 0,
            !goal.isComplete
        else {
            return nil
        }

        let share =
            Double(todayCapacity) *
            perDayNeed(goal) / total

        guard share > 0 else {
            return nil
        }

        let days = max(
            1,
            Int(ceil(Double(goal.remainingMinutes) / share))
        )

        return Calendar.current.date(
            byAdding: .day,
            value: days - 1,
            to: today
        )
    }

    // MARK: Goal Mutations

    func add(_ goal: Goal) {
        var newGoal = goal
        newGoal.colorIndex = goals.count

        goals.append(newGoal)

        save()
        scheduleReplan()
    }

    func delete(_ goal: Goal) {
        goals.removeAll {
            $0.id == goal.id
        }

        plan.removeAll {
            $0.goalID == goal.id
        }

        save()
        scheduleReplan()
    }

    // MARK: Disruption Mutations

    func add(_ disruption: Disruption) {
        disruptions.append(disruption)

        save()
        scheduleReplan()
    }

    func delete(_ disruption: Disruption) {
        disruptions.removeAll {
            $0.id == disruption.id
        }

        save()
        scheduleReplan()
    }

    // MARK: Progress Tracking

    func log(_ minutes: Int, to goal: Goal) {
        guard let index = goals.firstIndex(
            where: { $0.id == goal.id }
        ) else {
            return
        }

        goals[index].doneMinutes = max(
            0,
            goals[index].doneMinutes + minutes
        )

        save()
        scheduleReplan()
    }

    // MARK: Plan Item Management

    func toggle(_ item: PlanItem) {
        guard
            let index = plan.firstIndex(
                where: { $0.id == item.id }
            ),
            let goalIndex = goals.firstIndex(
                where: { $0.id == item.goalID }
            )
        else {
            return
        }

        plan[index].done.toggle()

        let adjustment = plan[index].done
            ? item.minutes
            : -item.minutes

        goals[goalIndex].doneMinutes = max(
            0,
            goals[goalIndex].doneMinutes + adjustment
        )

        save()
        scheduleReplan()
    }

    /// Convenience method used by TodayView.
    func togglePlanItem(_ id: UUID) {
        guard let item = plan.first(where: {
            $0.id == id
        }) else {
            return
        }

        toggle(item)
    }

    // MARK: Automatic Replanning

    private func scheduleReplan() {
        Task {
            await replan()
        }
    }

    func replan() async {

        let currentDay = today

        // Reset the plan when a new day begins.
        if planDay != currentDay {
            plan = []
            planDay = currentDay
        }

        // Read calendar availability.
        if settings.useCalendar {
            busy = await ActivityReader.shared.busy(
                on: currentDay
            )
        } else {
            busy = []
        }

        // Credit Apple Health exercise.
        if settings.useHealth {
            await creditExercise(currentDay)
        }

        // Preserve completed tasks.
        let completedItems = plan.filter {
            $0.done
        }

        let completedMinutes = completedItems.reduce(0) {
            $0 + $1.minutes
        }

        // Calculate remaining daily capacity.
        let freeCapacity = max(
            0,
            todayCapacity - completedMinutes
        )

        // Allocate time across active goals.
        let allocations = Planner.allocate(
            goals,
            done: completedItems,
            capacity: freeCapacity,
            day: currentDay
        )

        // Schedule around calendar events.
        let newItems = Planner.schedule(
            allocations,
            settings: settings,
            busy: busy,
            now: Date()
        )

        // Combine completed and newly scheduled tasks.
        plan = (
            completedItems + newItems
        ).sorted {
            $0.start < $1.start
        }

        save()

        // Refresh notifications.
        await Notifier.reschedule(
            goals: goals,
            plan: plan,
            settings: settings
        )
    }

    // MARK: Apple Health Integration

    private func creditExercise(_ day: Date) async {

        let minutes = await ActivityReader.shared.exerciseMinutes(
            on: day
        )

        for index in goals.indices
        where goals[index].tracksExercise &&
              !goals[index].isComplete {

            let key = "\(goals[index].id)-\(Int(day.timeIntervalSince1970))"

            let previouslyCredited = credited[key] ?? 0

            let difference = minutes - previouslyCredited

            if difference > 0 {

                goals[index].doneMinutes += difference

                credited[key] = minutes
            }
        }
    }
}
