import SwiftUI

// The confirm sheet shown by the share extension. A shared URL is turned into
// an editable "やりたいこと" candidate on-device (Foundation Models when
// available, rule-based otherwise). Saving writes straight to the shared App
// Group store.
//
// The form body is the shared `ItemForm` — identical to the in-app add/edit
// sheet. Two things differ by context: the chrome (system share sheet → nav bar)
// and the AI flow. Sharing a link signals intent, so a successful background
// reading is AUTO-ADOPTED here (no preview/反映) — but only the fields the user
// hasn't edited, and only when the link could actually be read. A non-URL or an
// unreadable link leaves the keyword draft in place and shows a small notice.
struct ShareComposeView: View {
    let initialTitle: String
    let url: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var priority: Priority = .maybe
    @State private var seasons: [SeasonTag] = [.any]
    @State private var tags: [String] = []        // tag keys
    @State private var memo = ""
    @State private var urlInput = ""

    @State private var allTags: [TagDef] = Tags.defaults

    @State private var useAuto = true
    @State private var isGenerating = false
    @State private var candidate: ItemCandidate?
    @State private var prewarmed = false
    @State private var urlState: URLState = .idle
    @State private var autoTask: Task<Void, Never>? = nil
    @State private var genTask: Task<Void, Never>? = nil
    @State private var lastQueriedURL = ""

    // Which fields the user has edited by hand. The auto-adopted reading only
    // fills fields NOT in here, so a background read never clobbers a manual edit.
    @State private var touched: Set<TouchedField> = []
    @State private var applying = false
    @State private var saveError = false

    enum TouchedField: Hashable { case title, priority, seasons, tags }
    enum URLState { case idle, invalidFormat, generating, ok, failed, blockedFree }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func markTouched(_ f: TouchedField) {
        if !applying { touched.insert(f) }
    }

    private var urlNotice: String? {
        switch urlState {
        case .invalidFormat: return "URLの形式で入力してください"
        case .failed:        return "このリンクを読み取れませんでした。内容を手入力してください。"
        case .ok:            return (candidate?.shouldConfirm == true) ? "情報が少なめです。内容をご確認ください。" : nil
        case .blockedFree:   return "無料の自動取り込みは上限に達しました。アプリで Pro にすると無制限になります。内容は手入力でそのまま保存できます。"
        default:             return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ItemForm(
                    title: $title,
                    memo: $memo,
                    priority: Binding(get: { priority },
                                      set: { priority = $0; markTouched(.priority) }),
                    seasons: Binding(get: { seasons },
                                     set: { seasons = $0; markTouched(.seasons) }),
                    tags: Binding(get: { tags },
                                  set: { tags = $0; markTouched(.tags) }),
                    allTags: allTags,
                    onAddCustomTag: addCustomTagLocally,
                    urlText: $urlInput,
                    onUrlChanged: handleUrlChanged,
                    onUrlSubmit: { autoTask?.cancel(); onUrlSettled() },
                    isGenerating: isGenerating,
                    urlNotice: urlNotice,
                    onTitleBeganEditing: { markTouched(.title) }
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(Theme.Color.pageBackground)
            .navigationTitle("Wishesに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { onCancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: start)
            .onDisappear { autoTask?.cancel(); genTask?.cancel() }
            .alert("保存できませんでした", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("保存中に問題が発生しました。アプリを開いてからもう一度お試しください。")
            }
        }
    }

    // MARK: - Logic

    private func start() {
        // Make sure the file-coordinated store is seeded from any legacy blobs
        // before we read it, then load the user's current custom tags.
        SharedStore.migrateLegacyIfNeeded()
        allTags = Tags.defaults + SharedStore.snapshot().customTags
        let tweaks = Storage.loadTweaks() ?? Tweaks()
        useAuto = tweaks.autoClassify
        urlInput = url ?? ""   // seed the editable URL field with the shared link
        // Seed an instant, savable draft (shared page title + offline keyword
        // classifier) so the sheet is editable and saveable right away.
        applyManualDefaults()
        // With a URL, read it in the background and auto-adopt a successful result.
        let raw = urlInput.trimmingCharacters(in: .whitespaces)
        if !raw.isEmpty {
            prewarmed = true
            OnDeviceModel.prewarm()
            onUrlSettled()
        }
    }

    private func handleUrlChanged(_ v: String) {
        if !prewarmed, !v.trimmingCharacters(in: .whitespaces).isEmpty {
            prewarmed = true
            OnDeviceModel.prewarm()
        }
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
            urlState = .idle; isGenerating = false; lastQueriedURL = ""
            return
        }
        guard URLSafety.looksLikeWebURL(raw) else {
            genTask?.cancel()
            urlState = .invalidFormat; isGenerating = false
            return
        }
        guard raw != lastQueriedURL else { return }
        // Pro soft-gate: the extension can't run StoreKit, so it reads the
        // entitlement + free allowance mirrored into the shared App Group. Out
        // of free reads (and not Pro) → skip the automatic reading and keep the
        // hand-seeded draft saveable; nudge toward Pro in the app.
        if !Storage.canAutoCapture {
            genTask?.cancel()
            isGenerating = false
            urlState = .blockedFree
            lastQueriedURL = raw
            return
        }
        lastQueriedURL = raw
        urlState = .generating
        withAnimation(.easeInOut(duration: 0.2)) { isGenerating = true }
        genTask?.cancel()
        genTask = Task {
            let c = await CandidateGenerator.make(rawURL: raw, memo: memo, existingTags: allTags)
            await MainActor.run {
                // Only the result for the URL still in the field wins.
                guard raw == urlInput.trimmingCharacters(in: .whitespaces) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isGenerating = false
                    candidate = c
                    if c.readable {
                        // A successful read consumes one free import (no-op for Pro).
                        Storage.consumeFreeCapture()
                        applyAI(c)       // auto-adopt: fills only untouched fields
                        urlState = .ok
                    } else {
                        // Couldn't read — keep the keyword draft, just warn.
                        urlState = .failed
                    }
                }
            }
        }
    }

    // Auto-adopt the reading, but never overwrite a field the user edited.
    private func applyAI(_ c: ItemCandidate) {
        applying = true
        if !touched.contains(.title) { title = c.title }
        if !touched.contains(.priority) { priority = c.priority }
        applySeasonsTags(c.seasons, c.tags,
                         applySeasons: !touched.contains(.seasons),
                         applyTags: !touched.contains(.tags))
        urlInput = c.bestURL?.absoluteString ?? urlInput
        lastQueriedURL = urlInput.trimmingCharacters(in: .whitespaces)
        applying = false
    }

    // Non-LLM defaults: the shared page title plus the keyword classifier
    // (offline, not the model). Seeds the form before the reading lands.
    private func applyManualDefaults() {
        applying = true
        title = initialTitle
        if useAuto {
            priority = Classifier.priority(initialTitle)
            applySeasonsTags(Classifier.seasons(initialTitle), Classifier.tags(initialTitle))
        } else {
            priority = .maybe
            seasons = [.any]; tags = []
        }
        applying = false
    }

    private func applySeasonsTags(_ newSeasons: [SeasonTag], _ newTags: [String],
                                  applySeasons: Bool = true, applyTags: Bool = true) {
        if applySeasons {
            seasons = newSeasons.isEmpty ? [.any] : newSeasons   // keep month precision
        }
        if applyTags {
            tags = TagValidator.validate(newTags, against: allTags)
        }
    }

    // Custom-tag add without an AppStore — mirrors AppStore.addCustomTag but
    // persists through the shared, file-coordinated store. The host app picks it
    // up on foreground via AppStore.reload() → SharedStore.load().
    private func addCustomTagLocally(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = allTags.first(where: { $0.ja == trimmed }) { return existing.key }
        let custom = allTags.filter { !$0.builtin }
        guard custom.count < Tags.maxCustom else { return nil }
        // UUID key (collision-free) appended via a coordinated read-modify-write
        // so a concurrent host save can't clobber it.
        let key = "c-" + UUID().uuidString
        SharedStore.mutate { doc in
            if !doc.customTags.contains(where: { $0.key == key }) {
                doc.customTags.append(TagDef(key: key, ja: trimmed, builtin: false))
            }
        }
        allTags = Tags.defaults + SharedStore.snapshot().customTags
        return key
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Only persist the link if it actually looks like a URL.
        let link = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedURL = URLSafety.looksLikeWebURL(link) ? link : nil

        // Append through a coordinated read-modify-write: the id is computed
        // from the freshly-read document and the new item is merged in, so a
        // simultaneous host write can't drop either side's changes.
        let ok = SharedStore.mutate { doc in
            let id = (doc.items.map(\.id).max() ?? 0) + 1
            let item = BucketItem(
                id: id, title: trimmed, priority: priority,
                seasons: seasons.isEmpty ? [.any] : seasons,
                tags: tags, meta: memo.trimmingCharacters(in: .whitespacesAndNewlines),
                done: false, doneAt: nil, via: "共有", url: savedURL,
                savedAt: BucketItem.savedAtFormatter.string(from: Clock.today)
            )
            doc.items.insert(item, at: 0)
        }
        // Only dismiss the share sheet as "saved" when the write actually
        // succeeded; otherwise warn instead of losing the item silently.
        if ok { onSave() } else { saveError = true }
    }
}
