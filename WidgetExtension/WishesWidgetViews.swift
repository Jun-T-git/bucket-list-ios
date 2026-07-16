import WidgetKit
import SwiftUI

// Widget presentation. Plain / familiar (原則§1); one green hue with depth for
// priority (原則§2). Titles are shown verbatim — already 体言止め, no verbs added
// (原則§7). Small = one pick; Medium = up to three.

struct WishesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WishEntry

    var body: some View {
        if entry.picks.isEmpty {
            EmptyStateView()
        } else if family == .systemSmall {
            SmallView(line: entry.line, pick: entry.picks[0])
        } else {
            MediumView(line: entry.line, picks: Array(entry.picks.prefix(3)))
        }
    }
}

// MARK: - Small — one gentle pick

private struct SmallView: View {
    let line: String
    let pick: WishPick

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FrameLine(line)
            Spacer(minLength: 6)
            Text(pick.title)
                .font(Theme.Font.display(17, weight: .bold))
                .foregroundColor(Theme.Color.ink0)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            WidgetPriorityPill(priority: pick.priority)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium — up to three

private struct MediumView: View {
    let line: String
    let picks: [WishPick]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FrameLine(line)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(picks) { pick in
                    // Title leads — the wish is the subject; priority is the
                    // quiet trailing cue, so the row never reads as a task manager
                    // (コアコンセプト§6 の非目標「優先度管理を主役にする」を避ける).
                    HStack(spacing: 8) {
                        Text(pick.title)
                            .font(Theme.Font.sans(14.5, weight: .semibold))
                            .foregroundColor(Theme.Color.ink0)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        WidgetPriorityPill(priority: pick.priority)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "tray")
                .font(.system(size: 20))
                .foregroundColor(Theme.Color.ink2)
            Spacer(minLength: 6)
            Text("いつかを、ここに")
                .font(Theme.Font.display(15, weight: .bold))
                .foregroundColor(Theme.Color.ink0)
            Text("＋ から追加できます")
                .font(Theme.Font.sans(12, weight: .regular))
                .foregroundColor(Theme.Color.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Pieces

// The nudge frame, e.g. "今週末におすすめ" — quiet, above the picks.
private struct FrameLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.sans(12, weight: .semibold))
            .foregroundColor(Theme.Color.green700)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// Priority as green depth (高/中/低) — mirrors the app's PriorityPill
// (Components.swift) exactly for visual unity (原則§2), just re-implemented here
// because Components.swift is AppStore-coupled via TagChip and can't join the
// widget target. Match: opaque white dot, weight bold only for .top.
private struct WidgetPriorityPill: View {
    let priority: Priority

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.white).frame(width: 6, height: 6)
            Text(priority.ja)
                .font(Theme.Font.sans(10.5, weight: priority == .top ? .bold : .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(priority.color))
    }
}
