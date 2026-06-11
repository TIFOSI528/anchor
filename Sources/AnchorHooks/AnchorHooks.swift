import Foundation

/// 预留模块。**v1 不使用。**
///
/// v3+ 用于接入 AI agent hook（Claude Code / Codex 等），让 Anchor 同时也能感知
/// "你正在与 AI agent 协作" 这种特殊上下文——AI agent 工作时不算"漂移"。
///
/// 当前只是占位，避免未来重构 Package.swift。
public enum AnchorHooks {
    public static let placeholder = "reserved for v3+"
}
