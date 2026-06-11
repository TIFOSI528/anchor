import Foundation

extension AppContext {
    /// 复盘里展示的目的地标签：有 URL 取 host，否则 bundle id。
    public var destinationLabel: String {
        url?.host ?? bundleId
    }
}

/// 把"离开绿区 → 在外面辗转 → 回到绿区"翻译成一串 `DriftRecord`。
///
/// 漂移途中每换一个目的地就结算上一条（`nextDestination` 指向新目的地，
/// 喂给漂移链分析），回绿区 / session 结束时结算最后一条并带上 `endReason`。
public final class DriftLogger {

    public struct Pending: Equatable {
        public let from: AppContext?
        public let to: AppContext
        public let openedAt: Date
    }

    public private(set) var pending: Pending?

    private let sessionId: String
    private let makeId: () -> String

    public init(sessionId: String, makeId: @escaping () -> String = { UUID().uuidString }) {
        self.sessionId = sessionId
        self.makeId = makeId
    }

    /// 进入非绿区。若已有进行中的漂移则结算它（hop），并以新目的地重新开一条。
    /// 返回被结算的记录（首次进入返回 nil）。
    @discardableResult
    public func enterNonGreen(from: AppContext?, to: AppContext, at date: Date) -> DriftRecord? {
        guard pending?.to != to else { return nil }
        let closed = pending.map { open in
            record(for: open, closedAt: date, endReason: nil, nextDestination: to.destinationLabel)
        }
        pending = Pending(from: pending == nil ? from : pending?.to, to: to, openedAt: date)
        return closed
    }

    /// 回到绿区，结算进行中的漂移。
    @discardableResult
    public func returnToGreen(at date: Date, reason: DriftRecord.EndReason) -> DriftRecord? {
        guard let open = pending else { return nil }
        pending = nil
        return record(for: open, closedAt: date, endReason: reason, nextDestination: nil)
    }

    /// session 结束（退出 app / 暂停），漂移按 `.sessionEnd` 收尾。
    @discardableResult
    public func sessionEnded(at date: Date) -> DriftRecord? {
        returnToGreen(at: date, reason: .sessionEnd)
    }

    // MARK: - private

    private func record(
        for open: Pending,
        closedAt: Date,
        endReason: DriftRecord.EndReason?,
        nextDestination: String?
    ) -> DriftRecord {
        DriftRecord(
            id: makeId(),
            sessionId: sessionId,
            occurredAt: open.openedAt,
            fromApp: open.from?.bundleId,
            fromURL: open.from?.url?.absoluteString,
            toApp: open.to.bundleId,
            toURL: open.to.url?.absoluteString,
            durationSeconds: max(0, Int(closedAt.timeIntervalSince(open.openedAt))),
            endReason: endReason,
            nextDestination: nextDestination
        )
    }
}
