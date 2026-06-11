import SwiftUI
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
                    Text("今天还没有数据")
                        .font(.title3)
                    Text("开始专注后，今晚 22:00 在这里见。")
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
        Text("今日复盘 · \(data.dateLabel)")
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
            Text(data.narrative.isEmpty ? "今天没有足够的数据生成叙事。" : data.narrative)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func timelineSection(_ data: RecapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("24h 时间线")
            TimelineBar(segments: data.segments)
                .frame(height: 36)
            HStack {
                legend(Color(hex: 0x22C55E), "深度绿区")
                legend(Color(hex: 0x86EFAC), "绿区")
                legend(Color(hex: 0xD1D5DB), "灰区")
                legend(Color(hex: 0xFCA5A5), "红区")
            }
            .font(.caption2)
        }
    }

    private func heatmapSection(_ data: RecapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("本周漂移热力图（周一–周五 · 8–22 时）")
            HeatmapGrid(heatmap: data.heatmap)
        }
    }

    private func thievesSection(_ data: RecapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("今日罪人榜")
            if data.thieves.isEmpty {
                Text("今天没有时间小偷。").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(data.thieves, id: \.rank) { thief in
                    HStack {
                        Text("#\(thief.rank)").font(.headline.monospacedDigit())
                        Text(thief.label).lineLimit(1)
                        Spacer()
                        Text(Self.minutesLabel(thief.totalSeconds)).foregroundStyle(.secondary)
                        if let snark = thief.snark {
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
            sectionTitle("漂移链 Top 2")
            if data.chains.isEmpty {
                Text("本周还没有成型的漂移路径。").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(Array(data.chains.enumerated()), id: \.offset) { _, chain in
                    HStack(spacing: 6) {
                        ForEach(Array(chain.nodes.enumerated()), id: \.offset) { index, node in
                            pill(node, color: [Color.blue, .orange, .red][min(index, 2)])
                            if index < chain.nodes.count - 1 { Text("→").foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text("\(chain.count) 次 · 平均 \(Self.minutesLabel(chain.averageSeconds))")
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
    static func minutesLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(max(0, seconds)) 秒" : "\(seconds / 60) 分钟"
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

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF3F4F6)))
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
        case .offline: return Color(hex: 0xF3F4F6)
        }
    }
}

/// 5×7 漂移热力图（§五.2）。
struct HeatmapGrid: View {
    let heatmap: DriftHeatmap

    private let weekdayLabels = ["一", "二", "三", "四", "五"]

    var body: some View {
        let peak = max(1, heatmap.grid.flatMap { $0 }.max() ?? 1)
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<DriftHeatmap.weekdayCount, id: \.self) { row in
                GridRow {
                    Text(weekdayLabels[row])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    ForEach(0..<DriftHeatmap.bucketCount, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: 0xFB923C).opacity(Double(heatmap.count(weekday: row, bucket: col)) / Double(peak)))
                            .frame(width: 52, height: 16)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.quaternary, lineWidth: 0.5))
                    }
                }
            }
        }
    }
}
