import SwiftUI

struct DetailSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openURL) private var openURL
    let item: BucketItem
    let onClose: () -> Void
    let onEdit: (BucketItem) -> Void

    // `item` is the sheet's snapshot — read the live copy so the done state and
    // achievement date reflect edits made while the sheet is open.
    private var live: BucketItem { store.items.first { $0.id == item.id } ?? item }

    // Year-month chosen for an as-yet-unachieved item. Once the item is done the
    // picker edits the stored `doneAt` directly instead of this draft.
    @State private var pendingDate = Clock.today

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    SectionLabel(text: "達成日")
                    YearMonthPicker(
                        date: Binding(
                            get: { live.done ? (live.doneAt ?? Clock.today) : pendingDate },
                            set: { newDate in
                                if live.done { store.setDoneAt(id: item.id, date: newDate) }
                                else { pendingDate = newDate }
                            }
                        ),
                        latest: Clock.today
                    )
                    SectionLabel(text: "優先度")
                    PriorityPill(priority: item.priority, size: .md)
                    SectionLabel(text: "シーズン")
                    SeasonChipsRow(seasons: item.seasons, max: 8, dim: item.done)
                    if !item.tags.isEmpty {
                        SectionLabel(text: "タグ")
                        TagChipsRow(tags: item.tags, max: 8, dim: item.done)
                    }
                    if let via = item.via {
                        viaCard(via: via)
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 24).padding(.top, 14)
            }
            footer
        }
        .background(Theme.Color.pageBackground)
        .onAppear { pendingDate = live.doneAt ?? Clock.today }
    }

    private var header: some View {
        HStack {
            Button("閉じる") {
                Haptics.tap()
                onClose()
            }
                .font(Theme.Font.sans(15))
                .foregroundColor(Theme.Color.ink2)
            Spacer()
            Text("詳細")
                .font(Theme.Font.display(17, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("編集") {
                Haptics.tap()
                onEdit(item)
            }
                .font(Theme.Font.sans(15, weight: .semibold))
                .foregroundColor(Theme.Color.green700)
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 8)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(Theme.Font.display(24, weight: .bold))
                .foregroundColor(item.done ? Theme.Color.ink3 : Theme.Color.ink0)
                .strikethrough(item.done, color: Theme.Color.ink3)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Theme.Color.hairline)
                .frame(height: 1.5)
            if !item.meta.isEmpty {
                Text(item.meta)
                    .font(Theme.Font.sans(14.5, weight: .medium))
                    .foregroundColor(Theme.Color.ink1)
            }
        }
    }

    // The saved link is why the item exists ("東京行ったらこの店") — make the
    // whole card open it instead of decorating with an inert arrow.
    private func viaCard(via: String) -> some View {
        let link = item.url.flatMap { raw -> URL? in
            let s = raw.contains("://") ? raw : "https://" + raw
            return URL(string: s)
        }
        return Button {
            guard let link else { return }
            Haptics.light()
            openURL(link)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(item.priority.color)
                    Text(String(via.prefix(1)))
                        .font(Theme.Font.display(14, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(via) から保存")
                        .font(Theme.Font.sans(12, weight: .medium))
                        .foregroundColor(Theme.Color.ink2)
                    Text(item.url ?? "shared.example.com/...")
                        .font(Theme.Font.mono(11))
                        .foregroundColor(Theme.Color.ink1)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("↗").foregroundColor(Theme.Color.ink3).font(.system(size: 18))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Theme.Color.paper0)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.Color.hairline, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(link == nil)
        .accessibilityLabel("\(via) で保存元を開く")
    }

    private var footer: some View {
        Button {
            if live.done {
                store.toggle(id: item.id)   // un-achieve; keeps the stored date
            } else {
                // Achieve with the year-month the user picked above, then close so
                // the celebration toast and the list's check-off animation aren't
                // hidden behind the sheet.
                store.markDone(id: item.id, date: pendingDate)
                onClose()
            }
        } label: {
            Text(live.done ? "未達成に戻す" : "達成済みにする")
                .font(Theme.Font.display(17, weight: .bold))
                .foregroundColor(live.done ? Theme.Color.ink0 : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule().fill(live.done ? Theme.Color.paper2 : Theme.Color.green700)
                )
                .shadow(color: live.done ? .clear : Theme.Color.green700.opacity(0.25),
                        radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 22)
    }
}
