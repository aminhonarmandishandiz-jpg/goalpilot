import SwiftUI

enum Palette {
    static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .red]
}

enum GoalType: String, Codable, CaseIterable, Identifiable {
    case personal = "Personal", business = "Business"
    var id: String { rawValue }
    var icon: String { self == .personal ? "person.fill" : "briefcase.fill" }
}

enum GoalStatus: String {
    case onTrack = "On track", atRisk = "At risk", behind = "Behind", done = "Completed"
    var color: Color {
        switch self { case .onTrack: .green; case .atRisk: .orange; case .behind: .red; case .done: .blue }
    }
}

struct Goal: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var type: GoalType
    var deadline: Date
    var createdAt = Date()
    var totalMinutes: Int          // estimated total effort
    var doneMinutes: Int = 0
    var priority: Int = 2          // 1 low ... 3 high
    var colorIndex: Int = 0
    var tracksExercise = false     // auto-credit from Apple Health

    var progress: Double { totalMinutes > 0 ? min(1, Double(doneMinutes) / Double(totalMinutes)) : 0 }
    var remainingMinutes: Int { max(0, totalMinutes - doneMinutes) }
    var isComplete: Bool { doneMinutes >= totalMinutes }
    var color: Color { Palette.colors[colorIndex % Palette.colors.count] }

    /// Days available including `day` itself.
    func daysLeft(from day: Date = Date()) -> Int {
        let c = Calendar.current
        let d = c.dateComponents([.day], from: c.startOfDay(for: day), to: c.startOfDay(for: deadline)).day ?? 0
        return max(1, d + 1)
    }
}

struct Disruption: Identifiable, Codable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case illness = "Illness", emergency = "Family emergency", travel = "Travel",
             urgentWork = "Urgent work", other = "Other"
        var id: String { rawValue }
        var icon: String {
            switch self { case .illness: "cross.case.fill"; case .emergency: "exclamationmark.octagon.fill"
            case .travel: "airplane"; case .urgentWork: "bolt.fill"; case .other: "questionmark.circle.fill" }
        }
    }
    var id = UUID()
    var title: String
    var kind: Kind
    var start: Date
    var end: Date
    var capacityLoss: Double       // 0...1 share of daily capacity lost

    func isActive(on day: Date) -> Bool {
        let c = Calendar.current
        return c.startOfDay(for: start) <= day && day <= c.startOfDay(for: end)
    }
}

struct PlanItem: Identifiable, Codable {
    var id = UUID()
    var goalID: UUID
    var start: Date
    var minutes: Int
    var done = false
}

struct AppSettings: Codable {
    var dayStart = 8 * 60          // minutes from midnight
    var dayEnd = 22 * 60
    var dailyCapacity = 240        // focus minutes available per day
    var morningReminder = 8 * 60
    var notificationsOn = true
    var useCalendar: Bool
    var useHealth: Bool
}
