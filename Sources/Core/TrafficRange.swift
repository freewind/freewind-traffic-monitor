import Foundation

/// 查询用时间区间的业务定义。
public enum TrafficRange: Equatable, Sendable {
    case today
    case lastDays(Int)
    case custom(from: Date, to: Date)
}

/// 把业务区间换算成 SQLite 使用的左闭右开时间戳区间 [from, to)。
public enum RangeCalculator {
    public static func bounds(
        for range: TrafficRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (from: Int64, to: Int64) {
        switch range {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (Int64(start.timeIntervalSince1970), Int64(now.timeIntervalSince1970) + 1)

        case .lastDays(let days):
            let count = max(days, 1)
            let startDay = calendar.date(byAdding: .day, value: -(count - 1), to: now) ?? now
            let start = calendar.startOfDay(for: startDay)
            return (Int64(start.timeIntervalSince1970), Int64(now.timeIntervalSince1970) + 1)

        case .custom(let from, let to):
            let start = calendar.startOfDay(for: from)
            let end = calendar.startOfDay(for: to).addingTimeInterval(86_400)
            return (Int64(start.timeIntervalSince1970), Int64(end.timeIntervalSince1970))
        }
    }
}
