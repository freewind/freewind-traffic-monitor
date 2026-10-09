import Foundation

/// 流量的可读格式化，统一使用 1000 进制（与运营商计费口径一致）。
public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    public static func size(_ bytes: UInt64) -> String {
        format(Double(bytes))
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        format(bytesPerSecond) + "/s"
    }

    private static func format(_ value: Double) -> String {
        var value = max(value, 0)
        var index = 0

        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }

        if index == 0 {
            return "\(Int(value)) \(units[index])"
        }

        let pattern = value >= 100 ? "%.0f %@" : (value >= 10 ? "%.1f %@" : "%.2f %@")
        return String(format: pattern, value, units[index])
    }
}
