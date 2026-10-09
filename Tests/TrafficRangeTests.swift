import XCTest
@testable import TrafficMonitorCore

final class TrafficRangeTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private func string(_ timestamp: Int64) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    func testTodayStartsAtMidnight() {
        let now = date("2026-03-05 14:30:00")
        let bounds = RangeCalculator.bounds(for: .today, now: now, calendar: calendar)

        XCTAssertEqual(string(bounds.from), "2026-03-05 00:00:00")
        XCTAssertEqual(bounds.to, Int64(now.timeIntervalSince1970) + 1)
    }

    func testLastSevenDaysIncludesToday() {
        let now = date("2026-03-05 09:00:00")
        let bounds = RangeCalculator.bounds(for: .lastDays(7), now: now, calendar: calendar)

        XCTAssertEqual(string(bounds.from), "2026-02-27 00:00:00")
        XCTAssertEqual(bounds.to, Int64(now.timeIntervalSince1970) + 1)
    }

    func testLastDaysClampsToOneDayMinimum() {
        let now = date("2026-03-05 09:00:00")
        let bounds = RangeCalculator.bounds(for: .lastDays(0), now: now, calendar: calendar)

        XCTAssertEqual(string(bounds.from), "2026-03-05 00:00:00")
    }

    func testCustomRangeCoversWholeEndDay() {
        let bounds = RangeCalculator.bounds(
            for: .custom(from: date("2026-03-01 18:00:00"), to: date("2026-03-03 02:00:00")),
            now: date("2026-03-10 00:00:00"),
            calendar: calendar
        )

        XCTAssertEqual(string(bounds.from), "2026-03-01 00:00:00")
        XCTAssertEqual(string(bounds.to), "2026-03-04 00:00:00")
    }

    func testCustomSingleDayIsOneDayLong() {
        let bounds = RangeCalculator.bounds(
            for: .custom(from: date("2026-03-01 00:00:00"), to: date("2026-03-01 23:59:59")),
            now: date("2026-03-10 00:00:00"),
            calendar: calendar
        )

        XCTAssertEqual(bounds.to - bounds.from, 86_400)
    }
}
