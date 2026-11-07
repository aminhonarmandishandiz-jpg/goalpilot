import EventKit
import HealthKit

/// Reads the user's activities: calendar events (to avoid clashes) and Apple Health exercise minutes.
final class ActivityReader {
    static let shared = ActivityReader()
    private let events = EKEventStore()
    private let health = HKHealthStore()

    func busy(on day: Date) async -> [DateInterval] {
        guard (try? await events.requestFullAccessToEvents()) == true else { return [] }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let pred = events.predicateForEvents(withStart: day, end: end, calendars: nil)
        return events.events(matching: pred).filter { !$0.isAllDay }
            .map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate.addingTimeInterval(60))) }
            .sorted { $0.start < $1.start }
    }

    func exerciseMinutes(on day: Date) async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let type = HKQuantityType(.appleExerciseTime)
        guard (try? await health.requestAuthorization(toShare: [], read: [type])) != nil else { return 0 }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let pred = HKQuery.predicateForSamples(withStart: day, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, r, _ in
                cont.resume(returning: Int(r?.sumQuantity()?.doubleValue(for: .minute()) ?? 0))
            }
            health.execute(q)
        }
    }
}
