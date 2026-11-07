import Foundation

enum Planner {
    static func capacity(_ s: AppSettings, _ d: [Disruption], day: Date) -> Int {
        let loss = min(0.95, d.filter { $0.isActive(on: day) }.reduce(0) { $0 + $1.capacityLoss })
        return Int(Double(s.dailyCapacity) * (1 - loss))
    }

    /// Minutes per goal for today, scaled down when demand exceeds capacity.
    static func allocate(_ goals: [Goal], done: [PlanItem], capacity: Int, day: Date) -> [(Goal, Int)] {
        var needs: [(Goal, Double)] = []
        for g in goals where !g.isComplete {
            let d = Double(
    done.filter {
        $0.goalID == g.id && $0.done
    }.reduce(0) {
        $0 + $1.minutes
    }
)
            let perDay = (Double(g.remainingMinutes) + d) / Double(g.daysLeft(from: day))
            let weight = 1 + 0.2 * Double(g.priority - 2)
            needs.append((g, min(Double(g.remainingMinutes), max(0, perDay * weight - d))))
        }
        let total = needs.reduce(0) { $0 + $1.1 }
        let scale = (total > Double(capacity) && total > 0) ? Double(capacity) / total : 1
        return needs.compactMap {
            let m = Int(($0.1 * scale / 5).rounded()) * 5
            return m >= 10 ? ($0.0, m) : nil
        }
    }

    /// Places blocks (max 60 min, 10 min breaks) around busy calendar slots.
    static func schedule(_ allocs: [(Goal, Int)], settings: AppSettings, busy: [DateInterval], now: Date) -> [PlanItem] {
        let day = Calendar.current.startOfDay(for: now)
        let winStart = day.addingTimeInterval(Double(settings.dayStart) * 60)
        let winEnd = day.addingTimeInterval(Double(settings.dayEnd) * 60)
        let rounded = Date(timeIntervalSinceReferenceDate: ceil(now.timeIntervalSinceReferenceDate / 300) * 300)
        var cursor = max(winStart, rounded)
        var out: [PlanItem] = []
        let ordered = allocs.sorted {
            $0.0.priority != $1.0.priority ? $0.0.priority > $1.0.priority : $0.0.deadline < $1.0.deadline
        }
        for (g, minutes) in ordered {
            var left = minutes
            while left > 0 {
                let block = min(left, 60)
                var end = cursor.addingTimeInterval(Double(block) * 60)
                while let b = busy.first(where: { $0.start < end && $0.end > cursor }) {
                    cursor = b.end
                    end = cursor.addingTimeInterval(Double(block) * 60)
                }
                if end > winEnd { break }
                out.append(PlanItem(goalID: g.id, start: cursor, minutes: block))
                cursor = end.addingTimeInterval(600)
                left -= block
            }
        }
        return out
    }
}
