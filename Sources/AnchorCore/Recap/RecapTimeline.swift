import Foundation

/// 复盘时间线里的区段类型。`deepGreen` 不是输入态，而是聚合时从 ≥15min 的连续绿区升级而来。
public enum RecapZone: String, Sendable, Equatable {
    case deepGreen
    case green
    case gray
    case red
    case offline
}

/// 一段连续的同区时间（聚合输入）。
public struct ZoneInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let zone: RecapZone

    public init(start: Date, end: Date, zone: RecapZone) {
        self.start = start
        self.end = end
        self.zone = zone
    }

    public var seconds: Int { max(0, Int(end.timeIntervalSince(start))) }
}

/// 时间线上的一段（聚合输出，绿区可能已升级为 deepGreen）。
public struct TimelineSegment: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let zone: RecapZone

    public init(start: Date, end: Date, zone: RecapZone) {
        self.start = start
        self.end = end
        self.zone = zone
    }

    public var seconds: Int { max(0, Int(end.timeIntervalSince(start))) }
}

/// 24h 时间线聚合 + Deep Score / 叙事所需的当日汇总。
public enum RecapTimeline {

    /// 连续绿区 ≥ 15min 视为"深度绿区"。
    public static let deepStreakThresholdSeconds = 900

    /// 排序并把够长的绿区升级为 deepGreen。
    public static func segments(from intervals: [ZoneInterval]) -> [TimelineSegment] {
        intervals
            .sorted { $0.start < $1.start }
            .map { interval in
                let zone: RecapZone = (interval.zone == .green && interval.seconds >= deepStreakThresholdSeconds)
                    ? .deepGreen
                    : interval.zone
                return TimelineSegment(start: interval.start, end: interval.end, zone: zone)
            }
    }

    public struct Totals: Equatable, Sendable {
        public let greenSeconds: Int
        public let graySeconds: Int
        public let redSeconds: Int
        public let longestStreakSeconds: Int

        public init(greenSeconds: Int, graySeconds: Int, redSeconds: Int, longestStreakSeconds: Int) {
            self.greenSeconds = greenSeconds
            self.graySeconds = graySeconds
            self.redSeconds = redSeconds
            self.longestStreakSeconds = longestStreakSeconds
        }
    }

    /// 汇总绿/灰/红区秒数 + 最长连续专注。绿区秒数含 deepGreen。
    public static func totals(from intervals: [ZoneInterval]) -> Totals {
        var green = 0, gray = 0, red = 0, longest = 0
        for interval in intervals {
            switch interval.zone {
            case .green, .deepGreen:
                green += interval.seconds
                longest = max(longest, interval.seconds)
            case .gray:
                gray += interval.seconds
            case .red:
                red += interval.seconds
            case .offline:
                break
            }
        }
        return Totals(greenSeconds: green, graySeconds: gray, redSeconds: red, longestStreakSeconds: longest)
    }
}
