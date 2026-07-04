import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    let onTap: (BucketItem) -> Void
    let onOpenOptions: () -> Void

    @State private var openSwipeID: Int? = nil

    var body: some View {
        // Single flat list. Done / not-done is a filter (see ViewOptionsSheet),
        // not a split section. sort() keeps checked-off items in place.
        let shown = store.sort(store.filtered())

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "リスト")

                if let sug = suggestion() {
                    InlineSuggestionBanner(
                        line: sug.line,
                        picks: sug.picks.map {
                            SuggestionPick(id: $0.id, title: trimmedTitle($0.title))
                        },
                        onPick: { p in
                            if let it = store.items.first(where: { $0.id == p.id }) {
                                onTap(it)
                            }
                        },
                        onDismiss: { store.nudgeDismissed = true }
                    )
                }

                CountStrip(
                    count: shown.count,
                    onOpenOptions: onOpenOptions
                )

                if shown.isEmpty {
                    EmptyList(anyFiltered: !store.filters.isEmpty)
                        .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 10) {
                        ForEach(shown) { it in
                            ListRow(
                                item: it,
                                swipeOpen: openSwipeID == it.id,
                                onSwipeOpen: { openSwipeID = $0 },
                                onSwipeClose: { openSwipeID = nil },
                                onTap: { onTap(it) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                Color.clear.frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func suggestion() -> TimingSuggestion? {
        guard store.tweaks.seasonNudge, !store.nudgeDismissed else { return nil }
        guard store.filters.isEmpty else { return nil }
        return store.timingSuggestion()
    }

    private func trimmedTitle(_ s: String) -> String {
        // 12 chars keeps phrases like "代々木公園のあの蕎麦屋" readable while
        // still fitting two chips in a row on small phones.
        if s.count > 12 { return String(s.prefix(12)) + "…" }
        return s
    }
}

// MARK: - InlineSuggestionBanner

struct SuggestionPick: Identifiable {
    let id: Int
    let title: String
}

struct InlineSuggestionBanner: View {
    let line: String
    let picks: [SuggestionPick]
    let onPick: (SuggestionPick) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(line)
                    .font(Theme.Font.sans(12.5, weight: .semibold))
                    .foregroundColor(Theme.Color.ink1)
                Spacer(minLength: 4)
                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    // 44×44 minimum tap target — matches HIG and shrinks the
                    // "did I really hit it?" anxiety for the dismiss control.
                    Text("×")
                        .font(Theme.Font.display(18, weight: .bold))
                        .foregroundColor(Theme.Color.ink3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("提案を閉じる")
            }
            if !picks.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(Array(picks.enumerated()), id: \.element.id) { idx, p in
                        Button {
                            Haptics.light()
                            onPick(p)
                        } label: {
                            HStack(spacing: 3) {
                                Text(p.title)
                                Text("›").opacity(0.7)
                            }
                            .font(Theme.Font.sans(11.5, weight: idx == 0 ? .bold : .medium))
                            .foregroundColor(idx == 0 ? .white : Theme.Color.green700)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(idx == 0 ? Theme.Color.green700 : Theme.Color.paper0)
                                    .overlay(
                                        Capsule().stroke(
                                            idx == 0 ? .clear : Theme.Color.green700.opacity(0.25),
                                            lineWidth: 1)
                                    )
                            )
                            // Keep the small chip look, but give it a 44pt-tall
                            // hit target so it's comfortable to tap.
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("提案: \(p.title)")
                    }
                }
            }
        }
        .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12).fill(Theme.Color.paper0)
                Theme.Color.peach500.frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        )
        .paperShadow()
        .padding(.horizontal, 20)
        .padding(.bottom, 10).padding(.top, 4)
    }
}

// MARK: - CountStrip + OptionsButton

struct CountStrip: View {
    @EnvironmentObject var store: AppStore
    let count: Int
    let onOpenOptions: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if store.selectionMode {
                Text("\(store.selection.count)件選択中")
                    .font(Theme.Font.display(17, weight: .bold))
                    .foregroundColor(Theme.Color.ink0)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    store.toggleSelectAllVisible()
                } label: {
                    Text(store.allVisibleSelected ? "選択解除" : "すべて選択")
                        .font(Theme.Font.sans(14, weight: .semibold))
                        .foregroundColor(Theme.Color.green700)
                        // 44pt hit target; the text stays the same size, only the
                        // tappable area grows so a near-miss still registers.
                        .padding(.horizontal, 4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    store.setSelectionMode(false)
                } label: {
                    Text("完了")
                        .font(Theme.Font.sans(14, weight: .semibold))
                        .foregroundColor(Theme.Color.ink2)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                countText
                    .font(Theme.Font.display(17, weight: .bold))
                    .foregroundColor(Theme.Color.ink0)
                    .lineLimit(1)
                Spacer(minLength: 4)
                // Mail-style "Edit" entry — a bordered pill (matches OptionsButton)
                // so it clearly reads as a tappable control, not a label.
                Button {
                    Haptics.tap()
                    store.setSelectionMode(true)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("選択")
                            .font(Theme.Font.sans(12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(Theme.Color.ink1)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Theme.Color.paper0)
                            .overlay(Capsule().stroke(Theme.Color.cardBorder, lineWidth: 1))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("選択モード")
                .accessibilityHint("複数選択して一括編集します")
                // One control for the whole sheet: it names the current sort and,
                // when filters are on, carries their count as a badge.
                OptionsButton(
                    mode: store.sortMode,
                    filterCount: store.filters.activeCount,
                    action: onOpenOptions
                )
            }
        }
        // Minimum height so the header (and the list below it) stays steady when
        // toggling selection mode — pills vs plain text would differ otherwise —
        // and the text/pill controls keep a full HIG-minimum hit target. Uses
        // minHeight (not a fixed height) so large Dynamic Type sizes can grow the
        // row instead of clipping the label.
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 8).padding(.bottom, 10)
    }

    private var countText: some View {
        Group {
            if count > 0 {
                HStack(spacing: 2) {
                    Text("\(count)")
                        .foregroundColor(Theme.Color.ink0)
                    Text("件")
                        .foregroundColor(Theme.Color.ink2)
                        .fontWeight(.medium)
                }
            } else if !store.filters.isEmpty {
                // "該当なし" only makes sense as a filter outcome — with no
                // filter, zero items is the genuinely-empty state, not a miss.
                Text("該当なし")
                    .foregroundColor(Theme.Color.ink2)
                    .fontWeight(.medium)
            } else {
                Text("0件")
                    .foregroundColor(Theme.Color.ink2)
                    .fontWeight(.medium)
            }
        }
    }
}

// Single entry point to the unified sort + filter sheet. The slider icon is
// iOS's standard "adjust / sort & filter" affordance — it signals that more
// than sorting lives here, which a sort-arrow icon alone would hide. The label
// names the current sort for glanceability; a badge shows active filters.
struct OptionsButton: View {
    let mode: SortMode
    let filterCount: Int
    let action: () -> Void
    var active: Bool { filterCount > 0 }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                Text(mode.ja)
                    .font(Theme.Font.sans(12, weight: .semibold))
                    .lineLimit(1)
                if active {
                    Text("\(filterCount)")
                        .font(Theme.Font.mono(10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.Color.green700))
                }
            }
            .foregroundColor(active ? Theme.Color.green700 : Theme.Color.ink1)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(active ? Theme.Color.green50 : Theme.Color.paper0)
                    .overlay(
                        Capsule().stroke(
                            active ? Theme.Color.green700.opacity(0.30) : Theme.Color.cardBorder,
                            lineWidth: 1)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active
            ? "並び替えと絞り込み、現在\(mode.ja)、絞り込み\(filterCount)件"
            : "並び替えと絞り込み、現在\(mode.ja)")
        .accessibilityHint("並び順と絞り込み条件を変更します")
    }
}

// MARK: - Empty state

struct EmptyList: View {
    let anyFiltered: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: anyFiltered ? "magnifyingglass" : "tray")
                .font(.system(size: 26))
                .foregroundColor(Theme.Color.ink2)
            Text(anyFiltered ? "該当なし" : "リストは空です")
                .font(Theme.Font.display(16, weight: .bold))
                .foregroundColor(Theme.Color.ink0)
            Text(anyFiltered ? "条件を変えてみてください" : "＋ ボタンから追加できます")
                .font(Theme.Font.sans(13, weight: .regular))
                .foregroundColor(Theme.Color.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.Color.paper0)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.Color.cardBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - ListRow with swipe-to-reveal actions

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ListRow: View {
    let item: BucketItem
    let swipeOpen: Bool
    let onSwipeOpen: (Int) -> Void
    let onSwipeClose: () -> Void
    let onTap: () -> Void

    @EnvironmentObject var store: AppStore
    @State private var dragX: CGFloat = 0
    @State private var dragging = false
    @State private var cardHeight: CGFloat = 0
    @State private var startBase: CGFloat = 0

    private let revealWidth: CGFloat = 152
    private let swipeThresh: CGFloat = 60

    var body: some View {
        ZStack(alignment: .trailing) {
            // Revealed action buttons — stationary behind the card; the card
            // slides left to expose them.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                actionButton(
                    title: item.done ? "戻す" : "達成",
                    icon: item.done ? "arrow.uturn.backward" : "checkmark",
                    bg: item.done ? Theme.Color.green300 : Theme.Color.green700
                ) {
                    store.toggle(id: item.id)
                    close()
                }
                .accessibilityLabel(item.done ? "未達成に戻す" : "達成済みにする")

                actionButton(title: "削除", icon: "trash", bg: Theme.Color.peach700) {
                    store.remove(id: item.id)
                    close()
                }
                .accessibilityLabel("削除")
            }
            // Fill the row so the revealed actions always match the card.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            // sliding body
            rowBody
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: CardHeightKey.self, value: geo.size.height)
                    }
                )
                .offset(x: clampedOffset)
                // simultaneousGesture (not .gesture): a plain .gesture DragGesture
                // claims the touch as soon as it passes minimumDistance and starves
                // the enclosing ScrollView, so a vertical pan that starts on a row
                // never scrolls. Running simultaneously lets the ScrollView keep
                // scrolling; the directional guard in onChanged means the row only
                // moves for horizontal-dominant drags.
                .simultaneousGesture(swipeGesture)
                .contextMenu {
                    if !store.selectionMode {
                        Button {
                            store.toggle(id: item.id)
                        } label: {
                            Label(item.done ? "未達成に戻す" : "達成済みにする",
                                  systemImage: item.done ? "arrow.uturn.backward" : "checkmark.circle")
                        }
                        Button(role: .destructive) {
                            store.remove(id: item.id)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
        }
        // Pin the whole row to the card's actual rendered height. FlowLayout's
        // ideal size can over-report (it estimates a wrap that the real width
        // doesn't trigger); without this pin the ZStack would size to that
        // inflated ideal, leaving the card floating in extra space.
        .frame(height: cardHeight > 0 ? cardHeight : nil)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .stickerShadow()
        .onPreferenceChange(CardHeightKey.self) { cardHeight = $0 }
        .onChange(of: swipeOpen) { _, newValue in
            if !dragging { withAnimation(.easeOut(duration: 0.24)) { dragX = newValue ? -revealWidth : 0 } }
        }
        .onChange(of: store.selectionMode) { _, _ in
            // Entering selection mode closes any half-open swipe.
            withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
        }
    }

    // MARK: row content
    private var rowBody: some View {
        let matchesNow = (item.seasons.isEmpty ? [SeasonTag.any] : item.seasons)
            .contains { $0 == .month(Clock.month) || $0 == .season(Clock.season) }

        return HStack(alignment: .center, spacing: 8) {
            if store.selectionMode {
                RowSelectCircle(selected: store.selection.contains(item.id)) {
                    store.toggleSelection(item.id)
                }
                // Slide in from the left and push the row content right, like Mail.
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if item.done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.Color.green700)
                    }
                    if matchesNow && !item.done {
                        Text("今")
                            .font(Theme.Font.sans(10, weight: .bold))
                            .foregroundColor(Theme.Color.peach700)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4).fill(Theme.Color.peach100)
                            )
                    }
                    Text(item.title)
                        .font(Theme.Font.sans(15.5, weight: item.priority == .top ? .bold : .medium))
                        .foregroundColor(item.done ? Theme.Color.ink3 : Theme.Color.ink0)
                        .strikethrough(item.done, color: Theme.Color.ink3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Single-line chip row — seasons, tags, and provenance share one
                // FlowLayout capped to one line so every row is the same height.
                // Chips that don't fit are dropped rather than wrapped.
                FlowLayout(spacing: 4, lineSpacing: 4, lineLimit: 1) {
                    // Priority leads the chip row so it always survives the
                    // one-line cap, and reads as just another chip — not a badge.
                    PriorityChip(priority: item.priority, dim: item.done)
                    let seasonTags = item.seasons.isEmpty ? [SeasonTag.any] : item.seasons
                    ForEach(Array(seasonTags.prefix(3).enumerated()), id: \.offset) { _, t in
                        SeasonChip(tag: t, dim: item.done)
                    }
                    if seasonTags.count > 3 {
                        Text("+\(seasonTags.count - 3)")
                            .font(Theme.Font.mono(10))
                            .foregroundColor(Theme.Color.ink2)
                    }
                    ForEach(item.tags.prefix(2), id: \.self) { k in
                        TagChip(key: k, dim: item.done)
                    }
                    if item.tags.count > 2 {
                        Text("+\(item.tags.count - 2)")
                            .font(Theme.Font.mono(10))
                            .foregroundColor(Theme.Color.ink2)
                    }
                    if let via = item.via {
                        Text("↗ \(via)")
                            .font(Theme.Font.mono(9.5, weight: .regular))
                            .foregroundColor(Theme.Color.ink2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4).fill(Theme.Color.paper1)
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.Color.hairline, lineWidth: 1))
                            )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12).padding(.trailing, 16)
        .padding(.vertical, 13)
        // Opaque base (hides the swipe action buttons sitting behind the card),
        // with the translucent selection tint layered on top of it.
        .background(
            store.selection.contains(item.id) ? Theme.Color.green700.opacity(0.10) : Color.clear
        )
        .background(Theme.Color.paper0)
        // Hairline card edge. In light it's a faint outline; in dark it's the
        // primary separator — a black stickerShadow is invisible on the dark page,
        // so without this the cards blend into the background. strokeBorder keeps
        // the line inside the bounds so the outer clipShape never trims it.
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Color.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
        .accessibilityElement(children: .combine)
        .accessibilityValue("優先度\(item.priority.ja)")
        // The done/delete actions live behind a custom horizontal drag, which
        // VoiceOver can't reach. Expose them as rotor actions so the same
        // store calls are available without the swipe gesture.
        .accessibilityAction(named: item.done ? "未達成に戻す" : "達成") {
            store.toggle(id: item.id)
        }
        .accessibilityAction(named: "削除") {
            store.remove(id: item.id)
        }
    }

    private func actionButton(title: String, icon: String, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(Theme.Font.sans(11, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(width: 76)
            .frame(maxHeight: .infinity)
            .background(bg)
        }
        .buttonStyle(.plain)
    }

    // MARK: gesture
    private var clampedOffset: CGFloat {
        if store.selectionMode { return 0 }   // no swipe reveal in selection mode
        return max(-revealWidth - 28, min(8, dragX))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard !store.selectionMode else { return }   // no swipe in selection mode
                // Only claim the gesture once the pan is clearly horizontal, so a
                // vertical pan stays with the ScrollView instead of nudging the row.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if !dragging {
                    dragging = true
                    startBase = swipeOpen ? -revealWidth : 0
                }
                dragX = startBase + value.translation.width
            }
            .onEnded { value in
                // Commit based on either distance OR velocity — a quick flick
                // should open even if the finger didn't travel past the
                // visual threshold. iOS-native swipe actions feel this way.
                let predicted = value.predictedEndTranslation.width
                let wasOpen = swipeOpen
                let isOpen = dragX <= -swipeThresh || predicted < -revealWidth * 0.4
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    dragX = isOpen ? -revealWidth : 0
                }
                dragging = false
                if isOpen {
                    if !wasOpen { Haptics.light() }
                    onSwipeOpen(item.id)
                } else {
                    onSwipeClose()
                }
            }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.24)) { dragX = 0 }
        onSwipeClose()
    }

    private func handleTap() {
        if store.selectionMode { store.toggleSelection(item.id); return }
        if swipeOpen || abs(dragX) > 6 { close(); return }
        onTap()
    }
}
