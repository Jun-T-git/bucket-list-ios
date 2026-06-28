import SwiftUI

struct ViewOptionsSheet: View {
    @EnvironmentObject var store: AppStore
    let onClose: () -> Void

    var body: some View {
        let counts = store.filterCounts()
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    axisBlock(title: "並び替え") {
                        FlowLayout(spacing: 6) {
                            ForEach(SortMode.allCases) { m in
                                sortChip(m)
                            }
                        }
                    }
                    axisBlock(title: "順序") {
                        FlowLayout(spacing: 6) {
                            directionChip(false)
                            directionChip(true)
                        }
                    }

                    Divider()
                        .background(Theme.Color.hairline)
                        .padding(.vertical, 2)

                    axisBlock(title: "状態") {
                        FlowLayout(spacing: 6) {
                            ForEach(ItemStatus.allCases) { s in
                                statusChip(s, count: counts.statuses[s] ?? 0)
                            }
                        }
                    }
                    // Achievement-year scope — only surfaces once there are
                    // achievements from a past year to reach back to. Scopes the
                    // done items shown; open plans are unaffected.
                    if store.achievementYears.count > 1 {
                        axisBlock(title: "達成した年") {
                            FlowLayout(spacing: 6) {
                                ForEach(store.achievementYears.reversed(), id: \.self) { y in
                                    yearChip(.year(y), label: y == Clock.year ? "今年" : "\(y)")
                                }
                                yearChip(.all, label: "全期間")
                            }
                        }
                    }
                    axisBlock(title: "優先度") {
                        FlowLayout(spacing: 6) {
                            ForEach(Priority.order, id: \.self) { p in
                                priorityChip(p, count: counts.priority[p] ?? 0)
                            }
                        }
                    }
                    axisBlock(title: "シーズン") {
                        FlowLayout(spacing: 6) {
                            ForEach(Season.order, id: \.self) { s in
                                seasonChip(.season(s), count: counts.seasons[.season(s)] ?? 0)
                            }
                            seasonChip(.any, count: counts.seasons[.any] ?? 0)
                        }
                    }
                    axisBlock(title: "タグ") {
                        FlowLayout(spacing: 6) {
                            ForEach(store.allTags) { t in
                                tagChip(t, count: counts.tags[t.key] ?? 0)
                            }
                        }
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 22).padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.Color.pageBackground)
    }

    private var header: some View {
        // The year scope counts as a clearable filter when it's not the default
        // (今年), so "すべて解除" also resets it.
        let canClear = !store.filters.isEmpty || store.achievementYear != .year(Clock.year)
        return HStack {
            Button {
                Haptics.light()
                store.filters.clear()
                store.achievementYear = .year(Clock.year)
            } label: {
                Text("すべて解除")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundColor(canClear ? Theme.Color.peach700 : Theme.Color.ink3Soft)
            }
            .disabled(!canClear)
            .accessibilityHint("選択中の絞り込みをすべて解除します")
            Spacer()
            Text("並び替え・絞り込み")
                .font(Theme.Font.display(16, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("閉じる") {
                Haptics.tap()
                onClose()
            }
                .font(Theme.Font.sans(15))
                .foregroundColor(Theme.Color.ink2)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 8)
    }

    private func axisBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.Font.mono(10))
                .foregroundColor(Theme.Color.ink2)
                .tracking(0.9)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Sort field — single-select. Exactly one is always active.
    private func sortChip(_ m: SortMode) -> some View {
        let on = store.sortMode == m
        return Button {
            Haptics.select()
            store.sortMode = m
        } label: {
            Text(m.ja)
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundColor(on ? .white : Theme.Color.ink0)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(
                    Capsule().fill(on ? Theme.Color.green700 : Theme.Color.paper0)
                        .overlay(Capsule()
                            .stroke(on ? .clear : Theme.Color.cardBorder, lineWidth: 1))
                )
                // Compact pill, but a 44pt tap target to guard against mis-taps.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // Sort direction — labels adapt to the chosen field (e.g. 新しい順 / 古い順).
    private func directionChip(_ ascending: Bool) -> some View {
        let labels = store.sortMode.directionLabels
        let label = ascending ? labels.up : labels.down
        let on = store.sortAscending == ascending
        return Button {
            Haptics.select()
            store.sortAscending = ascending
        } label: {
            HStack(spacing: 4) {
                Image(systemName: ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(Theme.Font.sans(13, weight: .semibold))
            }
            .foregroundColor(on ? .white : Theme.Color.ink0)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                Capsule().fill(on ? Theme.Color.green700 : Theme.Color.paper0)
                    .overlay(Capsule()
                        .stroke(on ? .clear : Theme.Color.cardBorder, lineWidth: 1))
            )
            // Compact pill, but a 44pt tap target to guard against mis-taps.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("\(label)で並べる")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // 達成した年 — single-select; 今年 is the default. Same capsule styling as
    // the other chips.
    private func yearChip(_ scope: YearScope, label: String) -> some View {
        let on = store.achievementYear == scope
        return Button {
            Haptics.select()
            store.achievementYear = scope
        } label: {
            Text(label)
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundColor(on ? .white : Theme.Color.ink0)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(
                    Capsule().fill(on ? Theme.Color.green700 : Theme.Color.paper0)
                        .overlay(Capsule()
                            .stroke(on ? .clear : Theme.Color.cardBorder, lineWidth: 1))
                )
                // Compact pill, but a 44pt tap target to guard against mis-taps.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func statusChip(_ s: ItemStatus, count: Int) -> some View {
        let on = store.filters.statuses.contains(s)
        let dim = count == 0 && !on
        return Button {
            Haptics.select()
            if store.filters.statuses.contains(s) { store.filters.statuses.remove(s) }
            else { store.filters.statuses.insert(s) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: s == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(on ? .white : (s == .done ? Theme.Color.green500 : Theme.Color.ink2))
                Text(s.ja)
                    .font(Theme.Font.sans(13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Font.mono(10))
                        .foregroundColor(on ? Color.white.opacity(0.7) : Theme.Color.ink2)
                }
            }
            .foregroundColor(on ? .white : (dim ? Theme.Color.ink3Soft : Theme.Color.ink0))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                Capsule().fill(on ? Theme.Color.green700 : Theme.Color.paper0)
                    .overlay(Capsule()
                        .stroke(on ? .clear : (dim ? Theme.Color.hairline : Theme.Color.cardBorder), lineWidth: 1))
            )
            .opacity(dim ? 0.55 : 1.0)
            // Compact pill, but a 44pt tap target to guard against mis-taps.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(dim)
    }

    private func priorityChip(_ p: Priority, count: Int) -> some View {
        let on = store.filters.priority.contains(p)
        let dim = count == 0 && !on
        return Button {
            Haptics.select()
            if store.filters.priority.contains(p) { store.filters.priority.remove(p) }
            else { store.filters.priority.insert(p) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(on ? .white : p.color).frame(width: 8, height: 8)
                Text(p.ja)
                    .font(Theme.Font.sans(13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Font.mono(10))
                        .foregroundColor(on ? Color.white.opacity(0.7) : Theme.Color.ink2)
                }
            }
            .foregroundColor(on ? .white : (dim ? Theme.Color.ink3Soft : Theme.Color.ink0))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                Capsule().fill(on ? p.color : Theme.Color.paper0)
                    .overlay(Capsule()
                        .stroke(on ? .clear : (dim ? Theme.Color.hairline : Theme.Color.cardBorder), lineWidth: 1))
            )
            .opacity(dim ? 0.55 : 1.0)
            // Compact pill, but a 44pt tap target to guard against mis-taps.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(dim)
    }

    private func seasonChip(_ tag: SeasonTag, count: Int) -> some View {
        let on = store.filters.seasons.contains(tag)
        let dim = count == 0 && !on
        let isCurrent: Bool = (tag == .season(Clock.season))
        let label: String = {
            if case .any = tag { return "いつでも" }
            return tag.ja
        }()
        return Button {
            Haptics.select()
            if store.filters.seasons.contains(tag) { store.filters.seasons.remove(tag) }
            else { store.filters.seasons.insert(tag) }
        } label: {
            HStack(spacing: 5) {
                if isCurrent {
                    Text("今")
                        .font(Theme.Font.sans(10, weight: .bold))
                        .foregroundColor(on ? Color.white.opacity(0.7) : Theme.Color.green700)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(on ? Color.white.opacity(0.15) : Theme.Color.green700.opacity(0.10))
                        )
                }
                Text(label)
                    .font(Theme.Font.sans(13, weight: on || isCurrent ? .bold : .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Font.mono(10))
                        .foregroundColor(on ? Color.white.opacity(0.7) : Theme.Color.ink2)
                }
            }
            .foregroundColor(on ? .white : (dim ? Theme.Color.ink3Soft : Theme.Color.ink0))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                Capsule().fill(on ? Theme.Color.green700 : Theme.Color.paper0)
                    .overlay(
                        Capsule().stroke(
                            on ? .clear
                               : (isCurrent ? Theme.Color.green700.opacity(0.45)
                                            : (dim ? Theme.Color.hairline : Theme.Color.cardBorder)),
                            lineWidth: isCurrent ? 1.5 : 1)
                    )
            )
            .opacity(dim ? 0.55 : 1.0)
            // Compact pill, but a 44pt tap target to guard against mis-taps.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(dim)
    }

    private func tagChip(_ t: TagDef, count: Int) -> some View {
        let on = store.filters.tags.contains(t.key)
        let dim = count == 0 && !on
        return Button {
            Haptics.select()
            if store.filters.tags.contains(t.key) { store.filters.tags.remove(t.key) }
            else { store.filters.tags.insert(t.key) }
        } label: {
            HStack(spacing: 4) {
                Text("#")
                    .font(Theme.Font.mono(13, weight: .medium))
                    .opacity(on ? 0.7 : 0.5)
                Text(t.ja)
                    .font(Theme.Font.sans(13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Font.mono(10))
                        .foregroundColor(on ? Color.white.opacity(0.7) : Theme.Color.ink2)
                }
            }
            .foregroundColor(on ? .white : (dim ? Theme.Color.ink3Soft : Theme.Color.green700))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                Capsule().fill(on ? Theme.Color.green700 : Theme.Color.paper0)
                    .overlay(Capsule()
                        .stroke(on ? .clear : Theme.Color.green700.opacity(dim ? 0.06 : 0.25), lineWidth: 1))
            )
            .opacity(dim ? 0.55 : 1.0)
            // Compact pill, but a 44pt tap target to guard against mis-taps.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(dim)
    }
}
