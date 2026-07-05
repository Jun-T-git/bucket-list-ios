import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    @State private var addOpen = false
    @State private var editingItem: BucketItem? = nil
    @State private var openItem: BucketItem? = nil
    @State private var optionsOpen = false
    @State private var doneSheetOpen = false
    @State private var attrSheetOpen = false
    @State private var deleteConfirm = false
    // Splash is skipped in screenshot mode so captures aren't covered.
    @State private var showSplash = !Screenshots.isOn
    #if DEBUG
    // Screenshot-only: presents a filled Share-Extension / AI-capture form.
    @State private var ssForm: ScreenshotFormMock.Kind? = nil
    #endif

    private var showSelectionBar: Bool {
        store.selectedTab == .home && store.selectionMode
    }

    private var showFAB: Bool {
        store.selectedTab == .home && !addOpen && openItem == nil
            && !optionsOpen && !store.selectionMode
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Page background — radial wash on top of paper1.
            backgroundWash.ignoresSafeArea()

            // Active screen. ScrollViews inside automatically respect the
            // bottom safeAreaInset (tab bar + FAB) so content always clears.
            Group {
                switch store.selectedTab {
                case .home:
                    HomeView(
                        onTap: { item in openItem = item },
                        onOpenOptions: { optionsOpen = true }
                    )
                case .records:
                    ReportView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 16) {
                    if showSelectionBar {
                        SelectionActionIcons(
                            onToggleDone: { doneSheetOpen = true },
                            onEditAttrs: { attrSheetOpen = true },
                            onDelete: { deleteConfirm = true }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if showFAB {
                        FloatingAddButton {
                            editingItem = nil
                            addOpen = true
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 20)
                        .transition(.scale.combined(with: .opacity))
                    }
                    CustomTabBar(selected: $store.selectedTab)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 12)
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: showFAB)
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: showSelectionBar)
            }

            // Toast — anchored just under the top safe area.
            if !store.toast.isEmpty {
                ToastView(
                    message: store.toast,
                    actionLabel: store.toastUndoLabel,
                    action: store.toastUndo == nil ? nil : { store.runToastUndo() }
                )
                .padding(.top, 8)
                .allowsHitTesting(store.toastUndo != nil)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: store.toast)
            }

            // Cold-launch splash — sits above everything, plays once, then
            // fades into the app.
            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onAppear {
            // Screenshot mode: open the requested capture screen.
            if Screenshots.screen == "add" { addOpen = true }
            #if DEBUG
            if Screenshots.screen == "share" { ssForm = .share }
            if Screenshots.screen == "addai" { ssForm = .aicapture }
            #endif
        }
        .sheet(isPresented: $addOpen) {
            AddEditSheet(editingItem: editingItem) {
                addOpen = false
                editingItem = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $openItem) { item in
            DetailSheet(item: item,
                        onClose: { openItem = nil },
                        onEdit: { it in
                            openItem = nil
                            editingItem = it
                            // small delay so the swap reads cleanly
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                addOpen = true
                            }
                        })
            // Detail is a glance, not a destination — medium keeps the list
            // in peripheral view; pull up for the full sheet.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $optionsOpen) {
            ViewOptionsSheet(onClose: { optionsOpen = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $doneSheetOpen) {
            BulkDoneSheet(onClose: { doneSheetOpen = false })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $attrSheetOpen) {
            BulkAttributesSheet(onClose: { attrSheetOpen = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("選択した\(store.selection.count)件を削除しますか？",
                            isPresented: $deleteConfirm, titleVisibility: .visible) {
            Button("\(store.selection.count)件を削除", role: .destructive) {
                store.removeMany(ids: store.selection)
                store.setSelectionMode(false)
            }
            Button("キャンセル", role: .cancel) {}
        }
        // First-launch walkthrough — covers the whole app until completed, then
        // never reappears on its own (store.completeOnboarding persists a flag).
        .fullScreenCover(isPresented: Binding(
            get: { store.showOnboarding && !showSplash },
            set: { store.showOnboarding = $0 }
        )) {
            OnboardingView()
                .environmentObject(store)
        }
        // Surfaced when the saved store was present but unreadable at launch.
        // We deliberately did NOT overwrite it with seed/empty data, so the file
        // stays intact for recovery — tell the user rather than silently wiping.
        .alert("データを読み込めませんでした",
               isPresented: Binding(get: { store.storageUnreadable },
                                    set: { store.storageUnreadable = $0 })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("保存されたリストを開けませんでした。データは消さずに保持しています。アプリを再起動しても表示されない場合は、お手数ですがお問い合わせください。")
        }
        #if DEBUG
        .fullScreenCover(item: $ssForm) { kind in
            ScreenshotFormMock(kind: kind).environmentObject(store)
        }
        #endif
    }

    private var backgroundWash: some View {
        ZStack {
            Theme.Color.pageBackground
            RadialGradient(
                colors: [Theme.Color.green50, .clear],
                center: UnitPoint(x: 0.15, y: 0.08),
                startRadius: 0, endRadius: 320
            )
            RadialGradient(
                colors: [Theme.Color.peach100, .clear],
                center: UnitPoint(x: 0.88, y: 0.92),
                startRadius: 0, endRadius: 360
            )
        }
    }
}

// MARK: - SelectionActionIcons
// Mail-style bottom actions: three independent icon buttons (toggle done /
// edit attributes / delete). Cancel & select-all live in the header (CountStrip).
struct SelectionActionIcons: View {
    @EnvironmentObject var store: AppStore
    var onToggleDone: () -> Void
    var onEditAttrs: () -> Void
    var onDelete: () -> Void

    var body: some View {
        let empty = store.selection.isEmpty
        HStack(spacing: 0) {
            iconButton("checkmark.circle", "達成状態", Theme.Color.green700,
                       disabled: empty, action: onToggleDone)
            iconButton("slider.horizontal.3", "属性", Theme.Color.green700,
                       disabled: empty, action: onEditAttrs)
            iconButton("trash", "削除", Theme.Color.peach700,
                       disabled: empty, action: onDelete)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func iconButton(_ icon: String, _ label: String, _ tint: Color,
                            disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 52, height: 52)
                    .glass(in: Circle())
                    .floatShadow()
                Text(label)
                    .font(Theme.Font.sans(11, weight: .semibold))
                    .foregroundColor(Theme.Color.ink2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

// MARK: - BulkDoneSheet
// Reached from the "達成状態" icon. Bulk-marks the selection done (with an
// optional achievement date, default today) or back to not-done.
struct BulkDoneSheet: View {
    @EnvironmentObject var store: AppStore
    @State private var date: Date = Clock.today
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "達成状態を変更", onClose: onClose)
            VStack(alignment: .leading, spacing: 18) {
                Text("\(store.selection.count)件に適用されます。")
                    .font(Theme.Font.sans(13, weight: .medium))
                    .foregroundColor(Theme.Color.ink2)

                HStack(alignment: .top, spacing: 10) {
                    Text("達成日")
                        .font(Theme.Font.sans(14, weight: .medium))
                        .foregroundColor(Theme.Color.ink1)
                        .padding(.top, 10)
                    YearMonthPicker(date: $date, latest: Clock.today)
                    Spacer(minLength: 0)
                }

                Button {
                    store.setDone(ids: store.selection, done: true, date: date)
                    finishSelection()
                } label: {
                    Text("達成にする")
                        .font(Theme.Font.display(16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Capsule().fill(Theme.Color.green700))
                }
                .buttonStyle(.plain)

                Button {
                    store.setDone(ids: store.selection, done: false)
                    finishSelection()
                } label: {
                    Text("未達成に戻す")
                        .font(Theme.Font.sans(15, weight: .semibold))
                        .foregroundColor(Theme.Color.ink0)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Capsule().fill(Theme.Color.paper2))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 14)
            Spacer(minLength: 0)
        }
        .background(Theme.Color.pageBackground)
    }

    // Leave selection mode and dismiss after a bulk done/undone action.
    private func finishSelection() {
        store.setSelectionMode(false)
        onClose()
    }
}

// MARK: - BulkAttributesSheet
// Reached from the "属性" icon. Bulk-edits priority and tags for the selection.
// Priority overwrites all selected. Tags are edited per-tag (others untouched):
//   .all  — every selected item has it → tap removes from all (check)
//   .some — only some have it          → tap adds to all       (dash)
//   .none — none have it               → tap adds to all       (#)
struct BulkAttributesSheet: View {
    @EnvironmentObject var store: AppStore
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "属性を一括編集", onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(store.selection.count)件に適用されます。")
                        .font(Theme.Font.sans(13, weight: .medium))
                        .foregroundColor(Theme.Color.ink2)

                    SectionLabel(text: "優先度")
                    let cur = store.priorityCoverage(in: store.selection)
                    HStack(spacing: 8) {
                        ForEach(Priority.order) { p in
                            priorityButton(p, selected: cur == p)
                        }
                    }

                    SectionLabel(text: "タグ")
                    FlowLayout(spacing: 6) {
                        ForEach(store.allTags) { t in
                            tagChip(for: t)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 14)
            }
        }
        .background(Theme.Color.pageBackground)
    }

    private func priorityButton(_ p: Priority, selected: Bool) -> some View {
        Button {
            store.setPriority(p, for: store.selection)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(selected ? Color.white : p.color).frame(width: 7, height: 7)
                Text(p.ja)
                    .font(Theme.Font.sans(13, weight: .semibold))
            }
            .foregroundColor(selected ? .white : Theme.Color.ink1)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(
                Capsule().fill(selected ? Theme.Color.green700 : Theme.Color.paper0)
                    .overlay(Capsule().stroke(selected ? .clear : Theme.Color.cardBorder, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func tagChip(for t: TagDef) -> some View {
        let cov = store.tagCoverage(t.key, in: store.selection)
        let isAll = cov == .all
        return Button {
            if isAll { store.removeTag(t.key, from: store.selection) }
            else { store.addTag(t.key, to: store.selection) }
        } label: {
            HStack(spacing: 4) {
                tagGlyph(cov)
                Text(t.ja).font(Theme.Font.sans(13, weight: .semibold))
            }
            .foregroundColor(isAll ? .white : Theme.Color.green700)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isAll ? Theme.Color.green700
                          : (cov == .some ? Theme.Color.green100 : Theme.Color.paper0))
                    .overlay(Capsule()
                        .stroke(isAll ? .clear : Theme.Color.green700.opacity(0.30), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.ja)
        .accessibilityAddTraits(isAll ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func tagGlyph(_ cov: TagCoverage) -> some View {
        switch cov {
        case .all:  Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
        case .some: Image(systemName: "minus").font(.system(size: 11, weight: .bold)).opacity(0.7)
        case .none: Text("#").font(Theme.Font.mono(13, weight: .medium)).opacity(0.5)
        }
    }
}

// MARK: - SheetHeader (shared centered title + 完了)
struct SheetHeader: View {
    let title: String
    var onClose: () -> Void
    var body: some View {
        HStack {
            Spacer()
            Text(title).font(Theme.Font.display(17, weight: .bold))
            Spacer()
            Button("完了") { Haptics.tap(); onClose() }
                .font(Theme.Font.sans(15, weight: .semibold))
                .foregroundColor(Theme.Color.green700)
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 10)
    }
}

// MARK: - CustomTabBar

struct CustomTabBar: View {
    @Binding var selected: AppStore.Tab

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.home, label: "リスト", icon: "checklist")
            tabButton(.records, label: "レポート", icon: "chart.bar.fill")
            tabButton(.settings, label: "設定", icon: "gearshape.fill")
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .glass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .floatShadow()
        // バー矩形全体でタップを受け止め、角丸の外側など透明部分から
        // 背後のリストへタップが抜けて誤操作になるのを防ぐ。
        .contentShape(Rectangle())
    }

    private func tabIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .regular))
            .foregroundColor(active ? Theme.Color.green500 : Theme.Color.ink2)
            .frame(width: 24, height: 24)
    }

    private func tabButton(_ tab: AppStore.Tab, label: String, icon iconName: String) -> some View {
        let on = selected == tab
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { selected = tab }
        } label: {
            VStack(spacing: 4) {
                tabIcon(iconName, active: on).frame(width: 24, height: 24)
                Text(label)
                    .font(Theme.Font.sans(11, weight: on ? .bold : .medium))
                    .foregroundColor(on ? Theme.Color.green500 : Theme.Color.ink2)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - FAB

struct FloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text("＋")
                .font(Theme.Font.display(30, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(Theme.Color.green500)
                )
                .shadow(color: Theme.Color.green700.opacity(0.32), radius: 11, x: 0, y: 10)
                .shadow(color: Theme.Color.green700, radius: 0, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .pressScale()
        .accessibilityLabel("追加")
        .accessibilityHint("新しいやりたいことを追加します")
    }
}

#if DEBUG
// MARK: - Screenshot form mock (DEBUG only)
// Presents the shared ItemForm pre-filled, styled as either the Share Extension
// compose sheet (「Wishesに追加」) or the in-app add sheet mid-AI-capture, so App
// Store marketing screenshots can show those flows. Never compiled into Release.
struct ScreenshotFormMock: View {
    enum Kind: String, Identifiable { case share, aicapture; var id: String { rawValue } }
    let kind: Kind
    @EnvironmentObject var store: AppStore

    @State private var title: String
    @State private var memo = ""
    @State private var priority: Priority
    @State private var seasons: [SeasonTag]
    @State private var tags: [String]
    @State private var urlText: String

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .share:
            _title    = State(initialValue: "ブルーボトルコーヒー 清澄白河")
            _priority = State(initialValue: .maybe)
            _seasons  = State(initialValue: [.any])
            _tags     = State(initialValue: ["food", "c-relax"])
            _urlText  = State(initialValue: "maps.apple.com/place/bluebottle")
        case .aicapture:
            _title    = State(initialValue: "")
            _priority = State(initialValue: .maybe)
            _seasons  = State(initialValue: [.any])
            _tags     = State(initialValue: [])
            _urlText  = State(initialValue: "https://youtu.be/kanazawa-trip")
        }
    }

    private var preview: ItemForm.AIPreview? {
        guard kind == .aicapture else { return nil }
        return ItemForm.AIPreview(
            title: "ひがし茶屋街を散歩する",
            priority: .maybe,
            seasons: [.season(.spring)],
            tags: ["travel", "leisure"],
            lowConfidence: false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ItemForm(
                    title: $title, memo: $memo,
                    priority: $priority, seasons: $seasons, tags: $tags,
                    allTags: store.allTags,
                    onAddCustomTag: { _ in nil },
                    urlText: $urlText,
                    isGenerating: false,
                    preview: preview,
                    autofocusTitle: false
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(Theme.Color.pageBackground)
            .navigationTitle(kind == .share ? "Wishesに追加" : "新規追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") {} }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {}.fontWeight(.semibold)
                }
            }
        }
    }
}
#endif
