import Foundation

/// 本周漂移热力图：5 行（周一–周五）× 7 列（8–22 时，每 2h 一格）。
/// 见 daily-recap-spec §五.2。
public struct DriftHeatmap: Equatable, Sendable {

    public static let weekdayCount = 5  // 周一–周五
    public static let bucketCount = 7   // 8-10, 10-12, ..., 20-22
    public static let startHour = 8
    public static let bucketHours = 2

    /// `grid[weekday][bucket]`，weekday 0=周一…4=周五。
    public let grid: [[Int]]

    public init(grid: [[Int]]) {
        self.grid = grid
    }

    /// 按 occurredAt 落格统计漂移次数。周末与 8–22 时之外的漂移忽略。
    public static func build(drifts: [DriftRecord], calendar: Calendar = .current) -> DriftHeatmap {
        var grid = Array(repeating: Array(repeating: 0, count: bucketCount), count: weekdayCount)

        for drift in drifts {
            let comps = calendar.dateComponents([.weekday, .hour], from: drift.occurredAt)
            guard let weekday = comps.weekday, let hour = comps.hour else { continue }
            // Calendar weekday: 1=周日…7=周六。取周一(2)…周五(6) → row 0…4。
            guard (2...6).contains(weekday) else { continue }
            guard hour >= startHour, hour < startHour + bucketCount * bucketHours else { continue }
            let row = weekday - 2
            let col = (hour - startHour) / bucketHours
            grid[row][col] += 1
        }

        return DriftHeatmap(grid: grid)
    }

    public func count(weekday: Int, bucket: Int) -> Int {
        grid[weekday][bucket]
    }

    public var total: Int {
        grid.reduce(0) { $0 + $1.reduce(0, +) }
    }
}
