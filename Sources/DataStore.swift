import Foundation

@MainActor
final class DataStore: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var disruptions: [Disruption] = []
    @Published var plan: [PlanItem] = []
    @Published var settings = AppSettings()
    @Published var busy: [DateInterval] = []
    private var planDay = Calendar.current.startOfDay(for: Date())
    private var credited: [String: Int] = [:]

    private struct Snapshot: Codable {
        var goals: [Goal]; var disruptions: [Disruption]; var plan: [PlanItem]
        var planDay: Date; var settings: AppSettings; var credited: [String: Int]
    }
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("goalpilot.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Snapshot.self, from: d) {
            goals = s.goals; disruptions = s.disruptions; plan = s.plan
            planDay = s.planDay; settings = s.settings; credited = s.credited
        }
    }

    func save() {
        let s = Snapshot(goals: goals, disruptions: disruptions, plan: plan, planDay: planDay, settings: settings, credited: credited)
        try? JSONEncoder().encode(s).write(to: Self.url, options: .atomic)
    }

    // MARK: Derived
    var today: Date { Calendar.current.startOfDay(for: Date()) }
    var activeGoals: [Goal] { goals.filter { !$0.isComplete } }
    var overallProgress: Double { goals.isEmpty ? 0 : goals.reduce(0) { $0 + $1.progress } / Double(goals.count) }
    var todayCapacity: Int { Planner.capacity(settings, disruptions, day: today) }
    var activeDisruptions: [Disruption] { disruptions.filter { $0.isActive(on: today) } }
    func goal(_ id: UUID) -> Goal? { goals.first { $0.id == id } }

    private func perDayNeed(_ g: Goal) -> Double { Double(g.remainingMinutes) / Double(g.daysLeft()) }
    /// >1 means total demand exceeds what you can realistically do per day.
    var loadFactor: Double {
        let need = activeGoals.reduce(0) { $0 + perDayNeed($1) }
        return todayCapacity > 0 ? need / Double(todayCapacity) : (need > 0 ? 9 : 0)
    }
    func status(_ g: Goal) -> GoalStatus {
        if g.isComplete { return .done }
        switch loadFactor { case ...1.0: return .onTrack; case ...1.25: return .atRisk; default: return .behind }
    }
    /// Realistic finish date given current capacity share.
    func projectedFinish(_ g: Goal) -> Date? {
        let total = activeGoals.reduce(0) { $0 + perDayNeed($1) }
        guard total > 0, todayCapacity > 0, !g.isComplete else { return nil }
        let share = Double(todayCapacity) * perDayNeed(g) / total
        guard share > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: Int(ceil(Double(g.remainingMinutes) / share)) - 1, to: today)
    }

    // MARK: Mutations
    func add(_ g: Goal) { var n = g; n.colorIndex = goals.count; goals.append(n); save(); Task { await replan() } }
    func delete(_ g: Goal) { goals.removeAll { $0.id == g.id }; plan.removeAll { $0.goalID == g.id }; save(); Task { await replan() } }
    func add(_ d: Disruption) { disruptions.append(d); save(); Task { await replan() } }
    func delete(_ d: Disruption) { disruptions.removeAll { $0.id == d.id }; save(); Task { await replan() } }

    func log(_ minutes: Int, to g: Goal) {
        guard let i = goals.firstIndex(where: { $0.id == g.id }) else { return }
        goals[i].doneMinutes = max(0, goals[i].doneMinutes + minutes); save(); Task { await replan() }
    }

    func toggle(_ item: PlanItem) {
        guard let i = plan.firstIndex(where: { $0.id == item.id }),
              let gi = goals.firstIndex(where: { $0.id == item.goalID }) else { return }
        plan[i].done.toggle()
        goals[gi].doneMinutes = max(0, goals[gi].doneMinutes + (plan[i].done ? item.minutes : -item.minutes))
        save(); Task { await replan() }
    }

    // MARK: Planning
    func replan() async {
        let t = today
        if planDay != t { plan = []; planDay = t }
        busy = settings.useCalendar ? await ActivityReader.shared.busy(on: t) : []
        if settings.useHealth { await creditExercise(t) }
        let done = plan.filter(\.done)
        let free = max(0, todayCapacity - done.reduce(0) { $0 + $1.minutes })
        let allocs = Planner.allocate(goals, done: done, capacity: free, day: t)
        let items = Planner.schedule(allocs, settings: settings, busy: busy, now: Date())
        plan = (done + items).sorted { $0.start < $1.start }
        save()
        await Notifier.reschedule(goals: goals, plan: plan, settings: settings)
    }

    private func creditExercise(_ t: Date) async {
        let minutes = await ActivityReader.shared.exerciseMinutes(on: t)
        for i in goals.indices where goals[i].tracksExercise && !goals[i].isComplete {
            let key = "\(goals[i].id)-\(Int(t.timeIntervalSince1970))"
            let delta = minutes - (credited[key] ?? 0)
            if delta > 0 { goals[i].doneMinutes += delta; credited[key] = minutes }
        }
    }
}
