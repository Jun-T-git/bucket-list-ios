import WidgetKit
import SwiftUI

// Widget presentation. Plain / familiar (原則§1); one green hue only (原則§2).
// Titles are shown verbatim — already 体言止め, no verbs added (原則§7). Priority
// is intentionally NOT shown — it isn't what the user cares about here, and
// leading with it would read as a task manager (コアコンセプト§6). Small = one
// wish with its context; Medium = a couple of wishes that fit now, each with its
// context; Lock Screen (accessory) = the single top wish. Every surface deep-
// links to the exact wish it shows (WishLink), so a tap leads straight to a
// glance — the shortest path toward "やった".

struct WishesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WishEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryRectangular, .accessoryInline, .accessoryCircular:
                    // The Lock Screen renders accessory widgets with its own
                    // vibrant material — don't paint over it.
                    Color.clear
                default:
                    Theme.Color.paper0
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            AccessoryRectView(line: entry.line, pick: entry.picks.first)
        case .accessoryInline:
            AccessoryInlineView(pick: entry.picks.first)
        default:
            if entry.picks.isEmpty {
                EmptyStateView()
            } else if family == .systemSmall {
                SmallView(line: entry.line, pick: entry.picks[0])
            } else {
                MediumView(line: entry.line, picks: Array(entry.picks.prefix(3)))
            }
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
        // Whole tile opens the wish it shows.
        .widgetURL(WishLink.url(id: pick.id))
    }
}

// MARK: - Medium — a couple of wishes that fit now, each with its context

private struct MediumView: View {
    let line: String
    let picks: [WishPick]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FrameLine(line)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(picks) { pick in
                    // Each row deep-links to its own wish (Link, not widgetURL,
                    // so the medium family can route per row).
                    Link(destination: WishLink.url(id: pick.id)) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            // A small green dot keeps the single-hue accent and
                            // gives the list quiet structure — no priority, no
                            // color coding.
                            Circle()
                                .fill(Theme.Color.green500)
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pick.title)
                                    .font(Theme.Font.sans(15, weight: .semibold))
                                    .foregroundColor(Theme.Color.ink0)
                                    .lineLimit(1)
                                if !pick.meta.isEmpty {
                                    Text(pick.meta)
                                        .font(Theme.Font.sans(11.5, weight: .regular))
                                        .foregroundColor(Theme.Color.ink2)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Lock Screen (accessory)

// Rectangular slot: the frame line + the single top wish and its context.
// Colors are ignored here (the system tints accessory widgets), so this leans
// on system fonts and the vibrant rendering — plain / familiar (原則§1).
private struct AccessoryRectView: View {
    let line: String
    let pick: WishPick?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let pick {
                Text(line.isEmpty ? "そっと、いつか" : line)
                    .font(.caption2).fontWeight(.semibold)
                    .widgetAccentable()
                Text(pick.title)
                    .font(.headline)
                    .lineLimit(pick.meta.isEmpty ? 2 : 1)
                if !pick.meta.isEmpty {
                    Text(pick.meta)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("いつかを、ここに")
                    .font(.headline).widgetAccentable()
                Text("＋ から追加")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(pick.map { WishLink.url(id: $0.id) })
    }
}

// Inline slot (beside the clock): one short line. Tapping opens the app.
private struct AccessoryInlineView: View {
    let pick: WishPick?

    var body: some View {
        if let pick {
            // A calm bookmark — "saved for someday" — not キラキラ (原則§1).
            Label(pick.title, systemImage: "bookmark")
                .widgetURL(WishLink.url(id: pick.id))
        } else {
            Label("いつかを追加", systemImage: "plus")
        }
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
