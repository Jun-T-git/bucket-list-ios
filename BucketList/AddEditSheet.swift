import SwiftUI

// MARK: - AddEditSheet
// In-app "new item" / "edit existing" sheet. The form body is the shared
// `ItemForm`; this view owns the chrome (header + delete + sticky 保存 footer),
// the AppStore wiring, and the URL→AI flow.
//
// AI flow (in-app): entering a URL auto-generates a reading in the background.
// A successful reading is shown as a preview the user adopts with one tap (反映);
// nothing changes until then. Non-URLs / unreadable links surface a small notice
// instead of a junk preview.

struct AddEditSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var pro: ProStore
    let editingItem: BucketItem?
    let onClose: () -> Void

    // Shown when the free auto-import allowance is spent and the user enters a
    // URL. The link stays in the field — manual saving is never blocked.
    @State private var showPaywall = false

    @State private var title = ""
    @State private var note = ""
    @State private var priorityChoice: PriorityChoice = .auto
    @State private var seasonsManual: [SeasonTag]? = nil
    @State private var tagsManual: [String]? = nil
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    // Signature of the editable state when the sheet opened, to detect unsaved
    // changes before discarding (cancel / swipe-to-dismiss).
    @State private var initialSig = ""

    // URL → background AI reading (surfaced as a preview, applied on 反映).
    @State private var urlInput = ""
    @State private var isGenerating = false
    @State private var pendingCandidate: ItemCandidate? = nil
    @State private var prewarmed = false
    @State private var urlState: URLState = .idle
    @State private var autoTask: Task<Void, Never>? = nil   // debounce
    @State private var genTask: Task<Void, Never>? = nil     // in-flight fetch
    @State private var lastQueriedURL = ""

    enum URLState { case idle, invalidFormat, generating, ok, failed, lowConfidence }

    enum PriorityChoice: Equatable {
        case auto
        case explicit(Priority)
        var value: Priority? {
            if case .explicit(let p) = self { return p }
            return nil
        }
    }

    private var isEditing: Bool { editingItem != nil }

    // Editable-state fingerprint; compared against `initialSig` to know whether
    // there are unsaved changes worth confirming before discard.
    private func signature() -> String {
        let p = priorityChoice.value.map(\.rawValue) ?? "auto"
        // Sort the multi-select keys so a mere re-ordering of the same set (e.g.
        // toggling a season rebuilds the array order) doesn't read as a change
        // and trigger a spurious "破棄しますか？" on close.
        let s = seasonsManual?.map(\.storageKey).sorted().joined(separator: ",") ?? "nil"
        let t = tagsManual?.sorted().joined(separator: ",") ?? "nil"
        return [title, note, urlInput, p, s, t].joined(separator: "\u{241F}")
    }
    private var isDirty: Bool { signature() != initialSig }

    private func attemptClose() {
        if isDirty { showDiscardConfirm = true } else { onClose() }
    }

    // Keyword-classifier drafts that follow the title until the user picks.
    // The Classifier is run ONCE per title change (in recomputeAIDraft, wired to
    // onChange(of: title)) and cached here; the bindings/submit read the cache so
    // a single keystroke no longer triggers many Classifier passes per render.
    @State private var aiPrioCache: Priority = .maybe
    @State private var aiSeasonsCache: [SeasonTag] = [.any]
    @State private var aiTagsCache: [String] = []

    private var aiPrio: Priority { aiPrioCache }
    private var aiSeasons: [SeasonTag] { aiSeasonsCache }
    private var aiTags: [String] { aiTagsCache }

    private func recomputeAIDraft() {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            aiPrioCache = .maybe
            aiSeasonsCache = [.any]
            aiTagsCache = []
        } else {
            aiPrioCache = Classifier.priority(title)
            aiSeasonsCache = Classifier.seasons(title)
            aiTagsCache = Classifier.tags(title)
        }
    }

    private var previewModel: ItemForm.AIPreview? {
        pendingCandidate.map {
            ItemForm.AIPreview(
                title: $0.title,
                priority: $0.priority,
                seasons: $0.seasons.isEmpty ? [.any] : $0.seasons,
                tags: $0.tags,
                lowConfidence: $0.shouldConfirm
            )
        }
    }

    private var urlNotice: String? {
        switch urlState {
        case .invalidFormat: return "URLの形式で入力してください"
        case .failed:        return "このリンクを読み取れませんでした。URLをご確認ください。"
        case .lowConfidence: return "内容を自動で読み取れませんでした。タイトルを入力してください。"
        default:             return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                ItemForm(
                    title: $title,
                    memo: $note,
                    priority: Binding(
                        get: { priorityChoice.value ?? aiPrio },
                        set: { priorityChoice = .explicit($0) }
                    ),
                    seasons: Binding(
                        get: { seasonsManual ?? aiSeasons },
                        set: { seasonsManual = $0 }
                    ),
                    tags: Binding(
                        get: { tagsManual ?? aiTags },
                        set: { tagsManual = $0 }
                    ),
                    allTags: store.allTags,
                    onAddCustomTag: { store.addCustomTag($0) },
                    urlText: $urlInput,
                    onUrlChanged: handleUrlChanged,
                    onUrlSubmit: { autoTask?.cancel(); onUrlSettled() },
                    isGenerating: isGenerating,
                    preview: previewModel,
                    onApplyPreview: applyPreview,
                    onDismissPreview: { pendingCandidate = nil },
                    urlNotice: urlNotice,
                    autofocusTitle: !isEditing && !Screenshots.isOn
                )
                .padding(.horizontal, 24)
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Color.pageBackground)
        .onAppear { populateState() }
        // Refresh the cached keyword draft only when the title actually changes,
        // not on every render / binding read.
        .onChange(of: title) { _, _ in recomputeAIDraft() }
        .onDisappear { autoTask?.cancel(); genTask?.cancel() }
        // Block swipe-to-dismiss while there are unsaved edits; the user must use
        // キャンセル, which then confirms the discard.
        .interactiveDismissDisabled(isDirty)
        .alert("削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) {
                if let it = editingItem {
                    store.remove(id: it.id)
                    onClose()
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("変更を破棄しますか？",
                            isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("変更を破棄", role: .destructive) { onClose() }
            Button("編集を続ける", role: .cancel) {}
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: header

    private var header: some View {
        HStack {
            Button("キャンセル", action: attemptClose)
                .font(Theme.Font.sans(15))
                .foregroundColor(Theme.Color.ink2)
            Spacer()
            Text(isEditing ? "編集" : "新規追加")
                .font(Theme.Font.display(17, weight: .bold))
            Spacer()
            if editingItem != nil {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Text("削除")
                        .font(Theme.Font.sans(15, weight: .semibold))
                        .foregroundColor(Theme.Color.peach700)
                }
                .accessibilityHint("確認のあと削除します")
            } else {
                Color.clear.frame(width: 44)
            }
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 8)
    }

    // MARK: URL → background AI reading

    private func handleUrlChanged(_ v: String) {
        if !prewarmed, !v.trimmingCharacters(in: .whitespaces).isEmpty {
            prewarmed = true
            OnDeviceModel.prewarm()
        }
        // Debounce: only act once the URL settles.
        autoTask?.cancel()
        autoTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await MainActor.run { onUrlSettled() }
        }
    }

    private func onUrlSettled() {
        let raw = urlInput.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty {
            genTask?.cancel()
            urlState = .idle; isGenerating = false; pendingCandidate = nil; lastQueriedURL = ""
            return
        }
        guard URLSafety.looksLikeWebURL(raw) else {
            genTask?.cancel()
            urlState = .invalidFormat; isGenerating = false; pendingCandidate = nil
            return
        }
        guard raw != lastQueriedURL else { return }   // already read this URL
        // Pro gate: automatic reading is a Pro feature with a small free
        // allowance. Out of free reads (and not Pro) → offer Pro instead of
        // reading; the URL stays put so the user can still save by hand.
        if !pro.isPro && !Storage.canAutoCapture {
            genTask?.cancel()
            isGenerating = false
            pendingCandidate = nil
            urlState = .idle
            showPaywall = true
            return
        }
        lastQueriedURL = raw
        pendingCandidate = nil
        urlState = .generating
        withAnimation(.easeInOut(duration: 0.2)) { isGenerating = true }
        let memo = note
        let tags = store.allTags
        genTask?.cancel()
        genTask = Task {
            let c = await CandidateGenerator.make(rawURL: raw, memo: memo, existingTags: tags)
            await MainActor.run {
                // Only the result for the URL still in the field wins — drops
                // stale results from a deleted / replaced URL.
                guard raw == urlInput.trimmingCharacters(in: .whitespaces) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isGenerating = false
                    if c.readable && !c.shouldConfirm {
                        // A successful read consumes one free import (no-op for Pro).
                        Storage.consumeFreeCapture()
                        pendingCandidate = c
                        urlState = .ok
                        Haptics.success()
                    } else if c.readable {
                        // Read the link but couldn't confidently name it — don't
                        // offer a placeholder preview to adopt; ask the user to fill
                        // the title in. No free import is spent for a non-result.
                        pendingCandidate = nil
                        urlState = .lowConfidence
                        Haptics.warning()
                    } else {
                        pendingCandidate = nil
                        urlState = .failed
                        Haptics.warning()
                    }
                }
            }
        }
    }

    // 反映 — the user adopts the reading with one tap. Mirrors ShareComposeView's
    // applyAI: only fields the user hasn't edited are filled, so a manual edit is
    // never clobbered. "Edited" reuses this sheet's existing dirty model — a
    // non-empty title, an explicit priority choice, or a non-nil manual
    // seasons/tags override.
    private func applyPreview() {
        guard let c = pendingCandidate else { return }
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            title = c.title
        }
        if priorityChoice.value == nil {
            priorityChoice = .explicit(c.priority)
        }
        if seasonsManual == nil {
            seasonsManual = c.seasons.isEmpty ? [.any] : c.seasons
        }
        if tagsManual == nil {
            tagsManual = c.tags
        }
        // Write the canonical URL back; mark it read so the field change doesn't
        // kick off another generation.
        urlInput = c.bestURL?.absoluteString ?? urlInput
        lastQueriedURL = urlInput.trimmingCharacters(in: .whitespaces)
        pendingCandidate = nil
        urlState = .ok
        Haptics.light()
    }

    // MARK: footer

    private var footer: some View {
        Button(action: submit) {
            Text("保存")
                .font(Theme.Font.display(17, weight: .bold))
                .foregroundColor(canSubmit ? .white : Theme.Color.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule().fill(canSubmit ? Theme.Color.green700 : Theme.Color.paper3)
                )
                .shadow(color: canSubmit ? Theme.Color.green700.opacity(0.25) : .clear,
                        radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 22)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        let resolvedPrio = priorityChoice.value ?? aiPrio
        let resolvedSeasons = seasonsManual ?? aiSeasons
        let resolvedTags = tagsManual ?? aiTags
        // Only persist the link if it actually looks like a URL — never store a
        // stray word / note typed into the field as a (broken) link.
        let link = urlInput.trimmingCharacters(in: .whitespaces)
        let resolvedURL = URLSafety.looksLikeWebURL(link) ? link : nil
        if let editing = editingItem {
            store.update(
                id: editing.id,
                title: title.trimmingCharacters(in: .whitespaces),
                priority: resolvedPrio,
                seasons: resolvedSeasons,
                tags: resolvedTags,
                meta: note.trimmingCharacters(in: .whitespaces),
                url: resolvedURL
            )
        } else {
            store.add(
                title: title.trimmingCharacters(in: .whitespaces),
                priority: resolvedPrio,
                seasons: resolvedSeasons,
                tags: resolvedTags,
                meta: note.trimmingCharacters(in: .whitespaces),
                via: resolvedURL != nil ? "URL" : nil,
                url: resolvedURL
            )
        }
        onClose()
    }

    private func populateState() {
        if let it = editingItem {
            title = it.title
            note = it.meta
            priorityChoice = .explicit(it.priority)
            seasonsManual = it.seasons
            tagsManual = it.tags
            urlInput = it.url ?? ""
            // Don't auto-read an existing item's saved URL on open.
            lastQueriedURL = it.url ?? ""
            urlState = .idle
        } else {
            note = ""
            // Manual-first: sentinel "auto" values let the keyword classifier's
            // draft follow the title as the user types, until they tap a choice.
            priorityChoice = .auto
            seasonsManual = nil
            tagsManual = nil
        }
        recomputeAIDraft()
        initialSig = signature()
    }
}
