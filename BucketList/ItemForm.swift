import SwiftUI
import UIKit

// MARK: - ItemForm
// The single, shared body for creating / editing a "やりたいこと". Both entry
// points embed it so their input UX never drifts: the in-app add/edit sheet
// (AddEditSheet) and the share extension (ShareComposeView). It is presentation
// only — no AppStore, no Storage — driven entirely by bindings + closures, so
// the standalone share extension (which has no AppStore) renders the exact same
// controls as the app.
//
// Layout (identical in both): hero title → メモ → URL area → 優先度 (capsule) →
// シーズン (pills + 月で指定 grid) → タグ (chips + ＋追加). The only things the
// two callers vary are passed in: how the URL area is shown (editable field vs
// a given-link preview) and the surrounding chrome (header / nav bar), which
// stays outside this view.
struct ItemForm: View {

    // Editable fields. Callers pass wrapped bindings whose setters record
    // "touched", so this view never needs to know about auto/AI state.
    @Binding var title: String
    @Binding var memo: String
    @Binding var priority: Priority
    @Binding var seasons: [SeasonTag]
    @Binding var tags: [String]

    // Tag catalog + custom-tag creation, AppStore-free. onAddCustomTag returns
    // the new (or existing) tag key, or nil if it couldn't be added.
    let allTags: [TagDef]
    let onAddCustomTag: (String) -> String?

    // URL / AI capture area. The user never triggers generation: entering a URL
    // auto-generates in the background (onUrlChanged debounces; onUrlSubmit fires
    // immediately). The result is surfaced either as a preview the user adopts
    // with one tap (in-app), or auto-applied upstream (share → preview is nil).
    @Binding var urlText: String
    var onUrlChanged: (String) -> Void = { _ in }
    var onUrlSubmit: () -> Void = {}
    let isGenerating: Bool
    var preview: AIPreview? = nil
    var onApplyPreview: () -> Void = {}
    var onDismissPreview: () -> Void = {}
    // Small warning shown directly under the URL field (invalid format /
    // couldn't read / low-info). Owned by the caller's URL state machine.
    var urlNotice: String? = nil

    // Title field config.
    var autofocusTitle: Bool = false
    var onTitleBeganEditing: () -> Void = {}

    // A read-only summary of an AI reading, shown in the in-app preview card.
    struct AIPreview {
        let title: String
        let priority: Priority
        let seasons: [SeasonTag]
        let tags: [String]
        let lowConfidence: Bool
    }

    @State private var addingTag = false
    @State private var tagDraft = ""
    // Focus for the SwiftUI text fields. The keyboard toolbar's 完了 clears it,
    // which dismisses whichever of these is active. (The title uses a UIKit
    // field with no SwiftUI keyboard accessory, so the toolbar only surfaces for
    // these — clearing focus covers every case the button is visible.)
    enum Field: Hashable { case url, memo, tag }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleField
            urlAreaView
            SectionLabel(text: "優先度")
            prioritySegment
            SectionLabel(text: "シーズン")
            seasonPicker
            SectionLabel(text: "タグ")
            tagSection
            // メモは最も補助的な項目なので最後に置く。
            SectionLabel(text: "メモ")
            memoField
            Color.clear.frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                // フィールド種別に依存しない汎用ディスミス。タイトル(UIKit)・
                // URL・メモ・タグなど、今フォーカスされている first responder を
                // 一律で解除する（memoFocused だけでは URL 等が閉じなかった）。
                Button("完了") { dismissKeyboard() }
                    .font(Theme.Font.sans(15, weight: .semibold))
            }
        }
    }

    // Extension-safe keyboard dismissal: clearing SwiftUI focus resigns the
    // active field. (UIApplication.shared is unavailable in the share extension,
    // which also compiles this shared view.)
    private func dismissKeyboard() {
        focusedField = nil
    }

    // Shared rounded paper1 field chrome for the single-/multi-line text inputs
    // (URL + メモ), so the two containers can't drift apart.
    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12).fill(Theme.Color.paper1)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Color.hairline, lineWidth: 1))
    }

    // MARK: title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Select-all on focus so an AI-suggested title can be overwritten
                // by typing immediately — no need to delete it first.
                SelectAllTextField(
                    placeholder: "例 · オーロラ",
                    text: $title,
                    font: .systemFont(ofSize: 22, weight: .bold),
                    textColor: UIColor(Theme.Color.ink0),
                    autofocus: autofocusTitle,
                    returnKey: .done,
                    maxLength: ItemCandidate.titleMaxLength,
                    onBeganEditing: onTitleBeganEditing
                )
                .frame(height: 30)
                if isGenerating { ProgressView() }
            }
            Rectangle().fill(Theme.Color.hairline)
                .frame(height: 1.5)
        }
    }

    // MARK: memo (auxiliary — last field)

    private var memoField: some View {
        // A multi-line note area (textarea), not a single-line input. Shows a few
        // lines tall by default and grows; text sits at the top-left.
        TextField("メモ（任意）", text: $memo, axis: .vertical)
            .lineLimit(3...8)
            .font(Theme.Font.sans(14.5, weight: .medium))
            .foregroundColor(Theme.Color.ink1)
            .focused($focusedField, equals: .memo)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(fieldBackground)
    }

    // MARK: URL area
    // Editable URL field with no action button — entering a URL auto-generates
    // in the background. The status (読み取り中…) and, in-app, a preview card
    // are the only feedback; the user's only action is the 1-tap ［反映］.

    private var urlAreaView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundColor(Theme.Color.ink2)
                TextField("URLを貼り付け（任意）", text: $urlText)
                    .focused($focusedField, equals: .url)
                    .font(Theme.Font.sans(14, weight: .medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit(onUrlSubmit)
                    .onChange(of: urlText) { _, v in onUrlChanged(v) }
                if isGenerating {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("読み取り中…")
                            .font(Theme.Font.sans(12, weight: .medium))
                            .foregroundColor(Theme.Color.ink2)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(fieldBackground)

            if let urlNotice { noticeRow(urlNotice) }
            if let preview { previewCard(preview) }
        }
    }

    // In-app: the AI reading, surfaced for the user to adopt with one tap.
    private func previewCard(_ p: AIPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("このリンクから")
                .font(Theme.Font.sans(11, weight: .regular))
                .foregroundColor(Theme.Color.ink2)
                .tracking(0.6).textCase(.uppercase)

            previewRow("タイトル", value: p.title.isEmpty ? "（なし）" : p.title)
            previewRow("優先度", value: p.priority.ja, dotColor: p.priority.color)
            previewRow("シーズン", value: p.seasons.map(\.ja).joined(separator: "・"))
            previewRow("タグ", value: tagLabels(p.tags))
            if p.lowConfidence {
                Text("情報が少なめです。内容を確認してください。")
                    .font(Theme.Font.sans(11.5, weight: .medium))
                    .foregroundColor(Theme.Color.ink2)
            }

            HStack(spacing: 10) {
                Button(action: onApplyPreview) {
                    Text("反映")
                        .font(Theme.Font.sans(14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.Color.green700))
                }
                .buttonStyle(.plain)
                Button(action: onDismissPreview) {
                    Text("閉じる")
                        .font(Theme.Font.sans(14, weight: .medium))
                        .foregroundColor(Theme.Color.ink2)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Theme.Color.paper0)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.Color.green700.opacity(0.30), lineWidth: 1))
        )
    }

    private func previewRow(_ label: String, value: String, dotColor: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(Theme.Font.sans(12, weight: .medium))
                .foregroundColor(Theme.Color.ink2)
                .frame(width: 56, alignment: .leading)
            if let dotColor {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            Text(value)
                .font(Theme.Font.sans(13.5, weight: .semibold))
                .foregroundColor(Theme.Color.ink0)
            Spacer(minLength: 0)
        }
    }

    private func tagLabels(_ keys: [String]) -> String {
        let labels = keys.map { key in allTags.first(where: { $0.key == key })?.ja ?? key }
        return labels.isEmpty ? "（なし）" : labels.joined(separator: "・")
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundColor(Theme.Color.ink2)
            Text(text)
                .font(Theme.Font.sans(12, weight: .medium))
                .foregroundColor(Theme.Color.ink2)
        }
    }

    // MARK: priority
    // A plain three-way segment (高 / 中 / 低).
    private var prioritySegment: some View {
        HStack(spacing: 4) {
            ForEach(Priority.order, id: \.self) { p in
                let on = priority == p
                Button {
                    if !on { Haptics.select() }
                    priority = p
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(p.color).frame(width: 8, height: 8)
                        Text(p.ja)
                            .font(Theme.Font.display(13, weight: on ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(on ? p.color : Theme.Color.ink2)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        on ? AnyView(Capsule().fill(Theme.Color.paper0).paperShadow())
                           : AnyView(Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.Color.paper2))
    }

    // MARK: seasons

    private var seasonPicker: some View {
        FlowLayout(spacing: 6) {
            ForEach(Season.order, id: \.self) { s in
                seasonPill(.season(s))
            }
            seasonPill(.any, label: "いつでも", anyStyle: true)
        }
    }

    private func seasonPill(_ tag: SeasonTag, label: String? = nil, anyStyle: Bool = false) -> some View {
        let on = seasons.contains(tag)
        let bg: Color = on ? (anyStyle ? Theme.Color.ink0 : Theme.Color.green700) : .white
        let fg: Color = on ? .white : (anyStyle ? Theme.Color.ink2 : Theme.Color.ink0)
        return Button {
            toggleSeason(tag)
        } label: {
            Text(label ?? tag.ja)
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundColor(fg)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    Capsule().fill(bg)
                        .overlay(Capsule().stroke(on ? .clear : Theme.Color.cardBorder, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleSeason(_ tag: SeasonTag) {
        var current = Set(seasons)
        if tag == .any {
            current = [.any]
        } else {
            current.remove(.any)
            if current.contains(tag) { current.remove(tag) } else { current.insert(tag) }
            if current.isEmpty { current.insert(.any) }
        }
        seasons = Array(current)
        Haptics.select()
    }

    // MARK: tags

    private var customTagCount: Int { allTags.filter { !$0.builtin }.count }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(allTags) { t in
                    tagChip(for: t)
                }
                if addingTag {
                    HStack(spacing: 2) {
                        Text("#")
                            .font(Theme.Font.mono(13, weight: .medium))
                            .foregroundColor(Theme.Color.green500)
                        TextField("新しいタグ", text: $tagDraft)
                            .focused($focusedField, equals: .tag)
                            .font(Theme.Font.sans(13, weight: .semibold))
                            .frame(width: 80)
                            .onSubmit { commitTag() }
                    }
                    .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 4)
                    .background(
                        Capsule().stroke(Theme.Color.green500, lineWidth: 2)
                            .background(Capsule().fill(Theme.Color.paper0))
                    )
                }
                if !addingTag, customTagCount < Tags.maxCustom {
                    Button { addingTag = true } label: {
                        Text("＋ 追加")
                            .font(Theme.Font.sans(13, weight: .medium))
                            .foregroundColor(Theme.Color.ink2)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().stroke(Theme.Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else if !addingTag {
                    // At the limit, explain why there's no ＋追加 instead of just
                    // hiding it silently.
                    Text("上限\(Tags.maxCustom)件")
                        .font(Theme.Font.sans(13, weight: .medium))
                        .foregroundColor(Theme.Color.ink3)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.Color.paper2))
                }
            }
            Text("カスタムタグ \(customTagCount) / \(Tags.maxCustom)")
                .font(Theme.Font.mono(10))
                .foregroundColor(customTagCount >= Tags.maxCustom ? Theme.Color.peach700 : Theme.Color.ink3)
        }
    }

    private func tagChip(for t: TagDef) -> some View {
        let on = tags.contains(t.key)
        return Button {
            if on { tags.removeAll { $0 == t.key } } else { tags.append(t.key) }
        } label: {
            HStack(spacing: 4) {
                Text("#")
                    .font(Theme.Font.mono(13, weight: .medium))
                    .opacity(on ? 0.7 : 0.5)
                Text(t.ja)
                    .font(Theme.Font.sans(13, weight: .semibold))
            }
            .foregroundColor(on ? .white : Theme.Color.green700)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                Capsule().fill(on ? Theme.Color.green700 : Theme.Color.paper0)
                    .overlay(Capsule()
                        .stroke(on ? .clear : Theme.Color.green700.opacity(0.30), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func commitTag() {
        let v = tagDraft.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { addingTag = false; tagDraft = ""; return }
        if let key = onAddCustomTag(v), !tags.contains(key) { tags.append(key) }
        tagDraft = ""; addingTag = false
    }
}

// MARK: - Shared layout helpers
// Moved here from Components.swift so BOTH the app and the share extension can
// use them (Components.swift stays app-only because it depends on AppStore).

// Simple horizontal-wrap layout used by chips/tags. Wraps as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    // When set, the layout never grows past this many lines — subviews that
    // would wrap beyond it are dropped (not placed), so the height stays fixed
    // and chips are never sliced mid-pill.
    var lineLimit: Int? = nil

    final class Cache {
        var lastBoundsWidth: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let proposedW = proposal.width
        let maxWidth: CGFloat = {
            if let w = proposedW, w.isFinite, w > 0 { return w }
            if cache.lastBoundsWidth > 0 { return cache.lastBoundsWidth }
            return .infinity
        }()
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, totalW: CGFloat = 0, line = 1
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth, x > 0 {
                if let lim = lineLimit, line >= lim { break }
                totalW = max(totalW, x - spacing)
                x = 0; y += lineH + lineSpacing; lineH = 0; line += 1
            }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        totalW = max(totalW, x - spacing)
        return CGSize(width: min(totalW, maxWidth.isFinite ? maxWidth : totalW), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        cache.lastBoundsWidth = bounds.width
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineH: CGFloat = 0, line = 1
        var stopped = false
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if !stopped, x + sz.width > bounds.minX + maxWidth, x > bounds.minX {
                if let lim = lineLimit, line >= lim {
                    stopped = true
                } else {
                    x = bounds.minX; y += lineH + lineSpacing; lineH = 0; line += 1
                }
            }
            if stopped {
                // Park overflow well off-screen so it isn't drawn.
                s.place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.minY), proposal: ProposedViewSize(sz))
                continue
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}

// Small uppercase section label used in the sheets.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.sans(11, weight: .regular))
            .foregroundColor(Theme.Color.ink2)
            .tracking(0.6)
            .textCase(.uppercase)
    }
}
