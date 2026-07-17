import WidgetKit
import SwiftUI

// Widget presentation. Plain / familiar (原則§1); one green hue only (原則§2).
// Titles are shown verbatim — already 体言止め, no verbs added (原則§7). Priority
// is intentionally NOT shown — it isn't what the user cares about here, and
// leading with it would read as a task manager (コアコンセプト§6). Small = one
// wish with its context; Medium = a short list of what fits now.

struct WishesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WishEntry

    var body: some View {
        if entry.picks.isEmpty {
            EmptyStateView()
        } else if family == .systemSmall {
            SmallView(line: entry.line, pick: entry.picks[0])
        } else {
            MediumView(line: entry.line, picks: Array(entry.picks.prefix(4)))
        }
    }
}

// MARK: - Small — one gentle pick, with its context

private struct SmallView: View {
    let line: String
    let pick: WishPick

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FrameLine(line)
            Spacer(minLength: 8)
            Text(pick.title)
                .font(Theme.Font.display(19, weight: .bold))
                .foregroundColor(Theme.Color.ink0)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if !pick.meta.isEmpty {
                Text(pick.meta)
                    .font(Theme.Font.sans(12, weight: .regular))
                    .foregroundColor(Theme.Color.ink2)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium — a short list of what fits now

private struct MediumView: View {
    let line: String
    let picks: [WishPick]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FrameLine(line)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(picks) { pick in
                    HStack(spacing: 8) {
                        // A small green dot keeps the single-hue accent and gives
                        // the list quiet structure — no priority, no color coding.
                        Circle()
                            .fill(Theme.Color.green500)
                            .frame(width: 5, height: 5)
                        Text(pick.title)
                            .font(Theme.Font.sans(14.5, weight: .semibold))
                            .foregroundColor(Theme.Color.ink0)
                            .lineLimit(1)
                        Spacer(minLength: 0)
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
