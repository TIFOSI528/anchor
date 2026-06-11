import Foundation

/// 按时间戳累计一个 session 的绿/灰/红秒数、漂移次数与最长连续专注。
///
/// 用"进入/离开时间戳"而不是 1Hz tick 驱动——绿区里不跑任何定时器
/// （technical-architecture §八 不变量 1），只在状态切换时结算。
public struct SessionAccumulator: Sendable, Equatable {

    public private(set) var greenSeconds = 0
    public private(set) var graySeconds = 0
    public private(set) var redSeconds = 0
    public private(set) var driftCount = 0
    public private(set) var longestStreakSeconds = 0

    private var currentZone: ZoneClassification?
    private var enteredAt: Date?

    public init() {}

    /// 进入新 zone（nil = offline/paused，停表）。相同 zone 重复调用是 no-op，
    /// 避免把一段连续绿区拆碎、错失 streak。
    public mutating func transition(to zone: ZoneClassification?, at date: Date) {
        guard zone != currentZone else { return }
        let previous = currentZone
        close(at: date)
        if previous == .green, let next = zone, next != .green {
            driftCount += 1
        }
        currentZone = zone
        enteredAt = zone == nil ? nil : date
    }

    /// 当前时刻的累计快照（把进行中的区段也结算进去，但不改变自身状态）。
    public func snapshot(at date: Date) -> Totals {
        var copy = self
        copy.close(at: date)
        return Totals(
            greenSeconds: copy.greenSeconds,
            graySeconds: copy.graySeconds,
            redSeconds: copy.redSeconds,
            driftCount: copy.driftCount,
            longestStreakSeconds: copy.longestStreakSeconds
        )
    }

    public struct Totals: Equatable, Sendable {
        public let greenSeconds: Int
        public let graySeconds: Int
        public let redSeconds: Int
        public let driftCount: Int
        public let longestStreakSeconds: Int

        public var onlineSeconds: Int { greenSeconds + graySeconds + redSeconds }
    }

    // MARK: - private

    private mutating func close(at date: Date) {
        guard let zone = currentZone, let start = enteredAt else { return }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        switch zone {
        case .green:
            greenSeconds += seconds
            longestStreakSeconds = max(longestStreakSeconds, seconds)
        case .gray:
            graySeconds += seconds
        case .red:
            redSeconds += seconds
        }
        enteredAt = date
    }
}
