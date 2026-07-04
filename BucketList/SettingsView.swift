import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var pro: ProStore
    @State private var showPaywall = false
    @State private var legalSheet: LegalKind? = nil

    enum LegalKind: String, Identifiable { case privacy, terms; var id: String { rawValue } }

    // Marketing version (CFBundleShortVersionString) plus build number,
    // read from the bundle so the displayed value never drifts from the
    // shipped binary.
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        if let build, !build.isEmpty, build != short {
            return "v\(short) (\(build))"
        }
        return "v\(short)"
    }

    private var disclosureChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.Color.ink3)
    }

    var body: some View {
        // No NavigationStack here: it would swallow ContentView's bottom
        // safeAreaInset (the floating tab bar) and hide the footer behind it.
        // Privacy / Terms open as sheets instead (see `legalSheet`).
        content
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "設定")

                SettingsGroup(title: "通知") {
                    SettingsRow(label: "シーズン通知",
                                sub: "季節のはじまりにおすすめを通知") {
                        AnyView(Toggle("", isOn: $store.tweaks.seasonNudge)
                            .toggleStyle(SwitchToggleStyle(tint: Theme.Color.green500))
                            .labelsHidden()
                            .accessibilityLabel("シーズン通知"))
                    }
                    SettingsRow(label: "週末リマインド",
                                sub: "金曜の夕方に今週末の候補を通知") {
                        AnyView(Toggle("", isOn: $store.tweaks.weekendNudge)
                            .toggleStyle(SwitchToggleStyle(tint: Theme.Color.green500))
                            .labelsHidden()
                            .accessibilityLabel("週末リマインド"))
                    }
                    SettingsRow(label: "月末リマインド",
                                sub: "今月のものを月末に通知") {
                        AnyView(Toggle("", isOn: $store.tweaks.monthEndNudge)
                            .toggleStyle(SwitchToggleStyle(tint: Theme.Color.green500))
                            .labelsHidden()
                            .accessibilityLabel("月末リマインド"))
                    }
                }

                SettingsGroup(title: "AI 機能") {
                    SettingsRow(label: "自動分類",
                                sub: "追加時に優先度・季節を下書き") {
                        AnyView(Toggle("", isOn: $store.tweaks.autoClassify)
                            .toggleStyle(SwitchToggleStyle(tint: Theme.Color.green500))
                            .labelsHidden()
                            .accessibilityLabel("自動分類"))
                    }
                }

                SettingsGroup(title: "タグ") {
                    SettingsRow(label: "固定タグ",
                                sub: "飲食・旅行・レジャー・お買い物") {
                        AnyView(Text("4")
                            .font(Theme.Font.mono(12, weight: .semibold))
                            .foregroundColor(Theme.Color.ink2))
                    }
                    TagManagerRow()
                }

                if FeatureFlags.proEnabled {
                SettingsGroup(title: "Pro") {
                    if pro.isPro {
                        SettingsRow(label: "Wishes Pro",
                                    sub: "URL取り込みが無制限でご利用いただけます") {
                            AnyView(Text("解放済み")
                                .font(Theme.Font.sans(13, weight: .bold))
                                .foregroundColor(Theme.Color.green700))
                        }
                    } else {
                        Button {
                            Haptics.tap()
                            showPaywall = true
                        } label: {
                            SettingsRow(label: "Pro にアップグレード",
                                        sub: "URLから自動でリストに追加（無制限）") {
                                AnyView(disclosureChevron)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            Haptics.tap()
                            Task { await pro.restore() }
                        } label: {
                            SettingsRow(label: "購入を復元",
                                        sub: "以前に購入された方はこちら") {
                                AnyView(disclosureChevron)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                }

                SettingsGroup(title: "アプリについて") {
                    Button {
                        Haptics.tap()
                        store.replayOnboarding()
                    } label: {
                        SettingsRow(label: "使い方をもう一度見る",
                                    sub: "コンセプトと基本操作のガイド") {
                            AnyView(disclosureChevron)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.tap()
                        legalSheet = .privacy
                    } label: {
                        SettingsRow(label: "プライバシー",
                                    sub: "データの扱いについて") {
                            AnyView(disclosureChevron)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.tap()
                        legalSheet = .terms
                    } label: {
                        SettingsRow(label: "利用規約",
                                    sub: "ご利用にあたって") {
                            AnyView(disclosureChevron)
                        }
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "mailto:jteraoka.biz@gmail.com")!) {
                        SettingsRow(label: "お問い合わせ",
                                    sub: "メールで開発者に連絡") {
                            AnyView(Image(systemName: "envelope")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.Color.ink3))
                        }
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 4) {
                    Text("Wishes")
                        .font(Theme.Font.sans(12, weight: .semibold))
                        .foregroundColor(Theme.Color.ink2)
                    Text(versionText)
                        .font(Theme.Font.mono(10))
                        .foregroundColor(Theme.Color.ink3)
                        .tracking(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28).padding(.top, 28)
                Color.clear.frame(height: 16)
            }
        }
        .onChange(of: store.tweaks.seasonNudge) { _, _ in syncNotifications() }
        .onChange(of: store.tweaks.weekendNudge) { _, _ in syncNotifications() }
        .onChange(of: store.tweaks.monthEndNudge) { _, _ in syncNotifications() }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $legalSheet) { kind in
            NavigationStack {
                Group {
                    switch kind {
                    case .privacy: PrivacyPolicyView()
                    case .terms:   TermsOfUseView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { legalSheet = nil }
                    }
                }
            }
        }
    }

    // Toggling a nudge re-syncs scheduled notifications; the permission
    // prompt appears here (an explicit user action), not at launch.
    private func syncNotifications() {
        NotificationPlanner.sync(tweaks: store.tweaks, items: store.items,
                                 requestIfNeeded: true) {
            store.flash("通知が許可されていません。iOSの設定から許可できます。", duration: 3.0)
        }
    }

}

// MARK: - SettingsGroup / Row primitives

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Font.display(18, weight: .bold))
                .foregroundColor(Theme.Color.ink0)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Theme.Color.paper0)
            )
            .paperShadow()
        }
        .padding(.horizontal, 20)
    }
}

struct SettingsRow: View {
    let label: String
    let sub: String?
    let control: () -> AnyView

    init(label: String, sub: String?, @ViewBuilder control: @escaping () -> AnyView) {
        self.label = label; self.sub = sub; self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Font.sans(14.5, weight: .semibold))
                    .foregroundColor(Theme.Color.ink0)
                if let sub {
                    Text(sub)
                        .font(Theme.Font.sans(11.5, weight: .regular))
                        .foregroundColor(Theme.Color.ink2)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 12)
        .overlay(
            Rectangle().fill(Theme.Color.hairline)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
        // Merge label + sub + control so VoiceOver announces e.g.
        // 「シーズン通知, … , スイッチ, オン」 instead of an unnamed switch.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - TagManagerRow

struct TagManagerRow: View {
    @EnvironmentObject var store: AppStore
    @State private var adding = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("カスタムタグ")
                    .font(Theme.Font.sans(14.5, weight: .semibold))
                    .foregroundColor(Theme.Color.ink0)
                Spacer()
                Text("\(store.customTags.count) / \(Tags.maxCustom)")
                    .font(Theme.Font.mono(11))
                    .foregroundColor(Theme.Color.ink2)
            }
            ForEach(store.customTags) { t in
                CustomTagEditRow(tag: t)
            }
            if adding {
                HStack(spacing: 8) {
                    Text("#")
                        .font(Theme.Font.mono(13, weight: .medium))
                        .foregroundColor(Theme.Color.green500)
                    TextField("新しいタグ", text: $draft)
                        .font(Theme.Font.sans(13, weight: .semibold))
                        .onSubmit { commit() }
                    Button("追加") { commit() }
                        .font(Theme.Font.sans(13, weight: .semibold))
                        .foregroundColor(Theme.Color.green700)
                    Button("キャンセル") { adding = false; draft = "" }
                        .font(Theme.Font.sans(13))
                        .foregroundColor(Theme.Color.ink2)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    Capsule().stroke(Theme.Color.green500, lineWidth: 2)
                        .background(Capsule().fill(Theme.Color.paper0))
                )
            }
            if !adding && store.customTags.count < Tags.maxCustom {
                Button { adding = true } label: {
                    Text("＋ カスタムタグを追加")
                        .font(Theme.Font.sans(13, weight: .medium))
                        .foregroundColor(Theme.Color.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(
                            Capsule().stroke(Theme.Color.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
    }

    private func commit() {
        let v = draft.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { _ = store.addCustomTag(v) }
        draft = ""; adding = false
    }
}

struct CustomTagEditRow: View {
    let tag: TagDef
    @EnvironmentObject var store: AppStore
    @State private var editing = false
    @State private var draft = ""
    @State private var showDeleteConfirm = false

    // How many items currently carry this tag — surfaced in the confirmation so
    // the cascading removal isn't a surprise.
    private var usageCount: Int {
        store.items.filter { $0.tags.contains(tag.key) }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("#")
                .font(Theme.Font.mono(13, weight: .medium))
                .foregroundColor(Theme.Color.green700.opacity(0.6))
            if editing {
                TextField("名前", text: $draft, onCommit: commit)
                    .font(Theme.Font.sans(13, weight: .semibold))
            } else {
                Text(tag.ja)
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundColor(Theme.Color.green700)
                Spacer(minLength: 12)
                Button { draft = tag.ja; editing = true } label: {
                    Text("編集")
                        .font(Theme.Font.sans(12, weight: .semibold))
                        .foregroundColor(Theme.Color.ink2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("「\(tag.ja)」を編集")
                // Generous gap so the destructive button isn't a mis-tap away.
                Spacer().frame(width: 8)
                Button { showDeleteConfirm = true } label: {
                    Text("削除")
                        .font(Theme.Font.sans(12, weight: .semibold))
                        .foregroundColor(Theme.Color.peach700)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("「\(tag.ja)」を削除")
            }
            if editing {
                Spacer(minLength: 8)
                Button("OK", action: commit)
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundColor(Theme.Color.green700)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            Capsule().fill(Theme.Color.green50)
                .overlay(Capsule().stroke(Theme.Color.green700.opacity(0.20), lineWidth: 1))
        )
        // Deleting a tag strips it from every item that uses it — confirm first.
        .confirmationDialog("「\(tag.ja)」を削除しますか？",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(usageCount > 0 ? "削除（\(usageCount)件から外れます）" : "削除",
                   role: .destructive) {
                store.removeCustomTag(key: tag.key)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            if usageCount > 0 {
                Text("このタグを使っている\(usageCount)件からも外れます。")
            }
        }
    }

    private func commit() {
        store.renameCustomTag(key: tag.key, to: draft)
        editing = false
    }
}

// MARK: - Legal / info screens (in-app text, no external URLs)

/// Shared scaffold for the simple in-app document screens so Privacy and
/// Terms share the same readable layout and Dynamic Type behaviour.
private struct LegalScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(Theme.Font.display(24, weight: .bold))
                    .foregroundColor(Theme.Color.ink0)
                    .accessibilityAddTraits(.isHeader)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(Theme.Color.paper1.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegalParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.Font.sans(14.5, weight: .regular))
            .foregroundColor(Theme.Color.ink1)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        LegalScreen(title: "プライバシー") {
            LegalParagraph("Wishes は、あなたのプライバシーを最優先に設計しています。本アプリは、できる限り情報を外部に出さないことを基本方針としています。")
            LegalParagraph("作成したリストや設定などのデータは、すべてお使いの端末内（App Group のローカル領域）に保存されます。アカウント登録は不要で、外部のサーバーへデータを送信することはありません。")
            LegalParagraph("広告の表示、行動のトラッキング、利用状況の解析（アナリティクス）は一切行いません。第三者にデータを提供・販売することもありません。")
            LegalParagraph("共有・貼り付けたリンクについては、タイトルやタグを下書きとして補完するために、端末内からそのリンク先のサイトのみにアクセスして内容を読み取ります。読み取った内容そのものを保存することはなく、下書きの作成のみに利用します。")
            LegalParagraph("AI による整形・分類の処理も、すべて端末内（オンデバイス）で動作します。あなたの入力内容が外部のAIサービスへ送られることはありません。")
            LegalParagraph("アプリを削除すると、端末内に保存されたデータも削除されます。")
            LegalParagraph("運営者：TeraTech\nお問い合わせ：jteraoka.biz@gmail.com")
        }
    }
}

struct TermsOfUseView: View {
    var body: some View {
        LegalScreen(title: "利用規約") {
            LegalParagraph("本利用規約は、Wishes（以下「本アプリ」）の利用条件を定めるものです。本アプリをご利用いただいた場合、本規約に同意したものとみなします。")
            LegalParagraph("本アプリは、現状有姿（提供時点のあるがままの状態）で提供されます。開発者は、本アプリの完全性・正確性・有用性・特定目的への適合性について、明示・黙示を問わず一切の保証を行いません。")
            LegalParagraph("本アプリのデータは端末内に保存されます。端末の故障・紛失・OSの不具合・アプリの削除などによるデータの消失について、開発者は責任を負いません。重要な情報はご自身でも控えをお取りください。")
            LegalParagraph("本アプリの利用に起因または関連して生じたいかなる損害についても、法令で許容される範囲において、開発者は責任を負わないものとします。")
            LegalParagraph("本規約の内容は、必要に応じて改定されることがあります。改定後に本アプリをご利用いただいた場合、改定後の規約に同意したものとみなします。")
        }
    }
}
