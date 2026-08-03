import SwiftUI
import AppKit
import AnchorCore

/// 今日复盘窗口（PR #24/#25）。Sections 见 daily-recap-spec §二。
struct RecapView: View {
    let data: RecapData?

    var body: some View {
        ScrollView {
            if let data {
                VStack(alignment: .leading, spacing: 22) {
                    header(data)
                    scoreSection(data)
                    timelineSection(data)
                    heatmapSection(data)
                    thievesSection(data)
                    chainsSection(data)
                }
                .padding(24)
            } else {
                VStack(spacing: 8) {
                    Text(L("recap.empty.title"))
                        .font(.title3)
                    Text(L("recap.empty.subtitle"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 120)
            }
        }
        .frame(width: 640, height: 560)
    }

    // MARK: - sections

    private func header(_ data: RecapData) -> some View {
        // dateLabel 是 locale 无关的存储 key；这里转成跟随系统语言/日历的显示文案。
        Text(L("recap.header.title", DayKey.displayLabel(forKey: data.dateLabel)))
            .font(.title2.bold())
    }

    private func scoreSection(_ data: RecapData) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack {
                Text("\(data.deepScore)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(data.deepScore))
                Text("Deep Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(data.narrative.isEmpty ? L("recap.narrative.empty") : data.narrative)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func timelineSection(_ data: RecapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("recap.section.timeline"))
            TimelineBar(segments: data.segments)
                .frame(height: 36)
            HStack {
                legend(Color(hex: 0x22C55E), L("recap.legend.deep_green"))
                legend(Color(hex: 0x86EFAC), L("recap.legend.green"))
                legend(Color(hex: 0xD1D5DB), L("recap.legend.gray"))
                legend(Color(hex: 0xFCA5A5), L("recap.legend.red"))
            }
            .font(.caption2)
        }
    }

    private func heatmapSection(_ data: RecapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("recap.section.heatmap"))
            HeatmapGrid(heatmap: data.heatmap)
        }
    }

    private func thievesSection(_ data: RecapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("recap.section.thieves"))
            if data.thieves.isEmpty {
                Text(L("recap.thieves.empty")).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(data.thieves, id: \.rank) { thief in
                    HStack {
                        Text("#\(thief.rank)").font(.headline.monospacedDigit())
                        Text(thief.label).lineLimit(1)
                        Spacer()
                        Text(Self.minutesLabel(thief.totalSeconds)).foregroundStyle(.secondary)
                        // thief.snark 存的是本地化 key，查表推迟到这里（见 TopThieves.snarkLibrary）。
                        if let snark = thief.localizedSnark {
                            Text(snark)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.18), in: Capsule())
                        }
                    }
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(thief.rank == 1 ? Color(hex: 0xDC2626) : Color(hex: 0xFB923C), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func chainsSection(_ data: RecapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("recap.section.chains"))
            if data.chains.isEmpty {
                Text(L("recap.chains.empty")).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(Array(data.chains.enumerated()), id: \.offset) { _, chain in
                    HStack(spacing: 6) {
                        ForEach(Array(chain.nodes.enumerated()), id: \.offset) { index, node in
                            pill(node, color: [Color.blue, .orange, .red][min(index, 2)])
                            if index < chain.nodes.count - 1 { Text("→").foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(L("recap.chains.summary", chain.count, Self.minutesLabel(chain.averageSeconds)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - bits

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }

    /// "0 分钟" 读起来像 bug —— 不足 1 分钟显示秒。
    ///
    /// 单位是文案的一部分（"分钟" / "min" 都在 `.strings` 里），而且超过一小时会进位：
    /// 125 分钟读成 "125 分钟" 同样像 bug。两件事都在 `DurationLabel` 里，
    /// 跟叙事共用一套词汇。
    static func minutesLabel(_ seconds: Int) -> String {
        DurationLabel.text(seconds: seconds)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case ..<30: return Color(hex: 0xDC2626)
        case ..<60: return Color(hex: 0xF59E0B)
        default: return Color(hex: 0x22C55E)
        }
    }
}

/// 24h 横向时间线（daily-recap-spec §五.1 的配色）。
struct TimelineBar: View {
    let segments: [TimelineSegment]

    /// 空轨（没在线的时段）底色。
    ///
    /// 原来写死 `0xF3F4F6`——那是一个浅灰，深色模式下就是横在界面里的一条白条。
    /// 换成语义色：`quaternaryLabelColor` 在浅色下是极淡的黑、深色下是极淡的白，
    /// 两种外观里都只是"底"，不会抢眼。
    private static var trackColor: Color { Color(nsColor: .quaternaryLabelColor) }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.trackColor))
            guard let dayStart = segments.first.map({ Calendar.current.startOfDay(for: $0.start) }) else { return }
            let daySeconds = 86_400.0
            for segment in segments {
                let x = segment.start.timeIntervalSince(dayStart) / daySeconds * size.width
                let width = max(1, Double(segment.seconds) / daySeconds * size.width)
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(rect), with: .color(color(for: segment.zone)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func color(for zone: RecapZone) -> Color {
        switch zone {
        case .deepGreen: return Color(hex: 0x22C55E)
        case .green: return Color(hex: 0x86EFAC)
        case .gray: return Color(hex: 0xD1D5DB)
        case .red: return Color(hex: 0xFCA5A5)
        case .offline: return Self.trackColor
        }
    }
}

/// 5×7 漂移热力图（§五.2）。
struct HeatmapGrid: View {
    let heatmap: DriftHeatmap

    /// 行标签是本地化 key，查表在渲染时做。
    private let weekdayLabels = [
        "recap.weekday.mon",
        "recap.weekday.tue",
        "recap.weekday.wed",
        "recap.weekday.thu",
        "recap.weekday.fri"
    ]

    /// 行标签列宽。中文一个字（"一"）就够，英文要放得下 "Mo"/"Th"。
    private let labelColumnWidth: CGFloat = 24
    private let cellWidth: CGFloat = 52

    var body: some View {
        let peak = max(1, heatmap.grid.flatMap { $0 }.max() ?? 1)
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<DriftHeatmap.weekdayCount, id: \.self) { row in
                GridRow {
                    Text(L(weekdayLabels[row]))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: labelColumnWidth)
                    ForEach(0..<DriftHeatmap.bucketCount, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: 0xFB923C).opacity(Double(heatmap.count(weekday: row, bucket: col)) / Double(peak)))
                            .frame(width: cellWidth, height: 16)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.quaternary, lineWidth: 0.5))
                    }
                }
            }
            // 原来只有行标签、没有列标签——"哪一格是下午三点"全靠数格子。
            GridRow {
                Color.clear.frame(width: labelColumnWidth, height: 1)
                ForEach(0..<DriftHeatmap.bucketCount, id: \.self) { col in
                    Text(Self.hourColumnLabel(col))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: cellWidth)
                }
            }
        }
    }

    /// 第 `col` 格覆盖的小时区间，如 "8–10"。区间边界跟着 `DriftHeatmap` 的常量走。
    static func hourColumnLabel(_ col: Int) -> String {
        let start = DriftHeatmap.startHour + col * DriftHeatmap.bucketHours
        return L("recap.heatmap.hour_column", start, start + DriftHeatmap.bucketHours)
    }
}
