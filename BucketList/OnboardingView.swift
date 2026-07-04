import SwiftUI

// MARK: - OnboardingView
// First-launch walkthrough. Five pages tell the product story:
//   ① ビジョン     — やりたいことをためて、少しずつ叶える
//   ② 回収＋AI     — 他アプリの共有ボタンから1タップ登録、AIが入力を補完
//   ③ レポート     — 達成のふり返り＋ペースに合わせたAIの提案
//   ④ 初期設定     — 名前と今年の目標（数値入力）
//   ⑤ 通知         — AIが適切なタイミングで通知、ここで権限を取得
// Shown once over a fullScreenCover, then dismissed for good via
// store.completeOnboarding(). Replayable from 設定.
//
// All visuals are drawn in SwiftUI (no bundled images/video) and reuse the
// app's own design language: green-only palette, Liquid Glass chrome, spring
// motion. Honors Reduce Motion by revealing content instantly.

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    private let pageCount = 5

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    VisionPage(isActive: page == 0).tag(0)
                    CapturePage(isActive: page == 1).tag(1)
                    ReportPage(isActive: page == 2).tag(2)
                    SetupPage(isActive: page == 3).tag(3)
                    NotifyPage(isActive: page == 4).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)

                footer
            }
        }
    }

    // MARK: top bar (skip)

    private var topBar: some View {
        HStack {
            Spacer()
            if page < pageCount - 1 {
                Button("スキップ") { finish() }
                    .font(Theme.Font.sans(14, weight: .semibold))
                    .foregroundColor(Theme.Color.ink2)
                    .accessibilityHint("オンボーディングを閉じます")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: footer (dots + actions)

    private var footer: some View {
        VStack(spacing: 16) {
            PageDots(count: pageCount, index: page)

            if page < pageCount - 1 {
                PrimaryCTA(title: "次へ") { advance() }
            } else {
                PrimaryCTA(title: "通知をオンにして始める") {
                    enableNotifications()
                    finish()
                }
                Button("あとで設定する") {
                    declineNotifications()
                    finish()
                }
                .font(Theme.Font.sans(14.5, weight: .semibold))
                .foregroundColor(Theme.Color.ink2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    // MARK: actions

    private func advance() {
        Haptics.tap()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            page = min(page + 1, pageCount - 1)
        }
    }

    private func finish() {
        Haptics.success()
        store.completeOnboarding()
    }

    // Request system authorization for the (all-on by default) nudges. Mirrors
    // SettingsView.syncNotifications — the explicit, user-initiated moment.
    private func enableNotifications() {
        NotificationPlanner.sync(tweaks: store.tweaks, items: store.items,
                                 requestIfNeeded: true) {
            store.flash("通知が許可されていません。iOSの設定から許可できます。", duration: 3.0)
        }
    }

    // "あとで" — turn the nudge toggles off so the 設定 switches reflect reality
    // (no permission was granted), avoiding an "ON but silent" mismatch.
    private func declineNotifications() {
        store.tweaks.seasonNudge = false
        store.tweaks.weekendNudge = false
        store.tweaks.monthEndNudge = false
    }

    private var background: some View {
        ZStack {
            Theme.Color.pageBackground
            RadialGradient(colors: [Theme.Color.green50, .clear],
                           center: UnitPoint(x: 0.15, y: 0.10),
                           startRadius: 0, endRadius: 340)
            RadialGradient(colors: [Theme.Color.peach100.opacity(0.7), .clear],
                           center: UnitPoint(x: 0.9, y: 0.92),
                           startRadius: 0, endRadius: 380)
        }
    }
}

// MARK: - Shared page chrome

// A page's title + supporting copy, centered, with consistent spacing.
private struct PageCopy: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(Theme.Font.display(25, weight: .bold))
                .foregroundColor(Theme.Color.ink0)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.Font.sans(15, weight: .regular))
                .foregroundColor(Theme.Color.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.Color.green500 : Theme.Color.paper4)
                    .frame(width: i == index ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(index + 1)/\(count)ページ")
    }
}

private struct PrimaryCTA: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.display(16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(Theme.Color.green700))
        }
        .buttonStyle(.plain)
        .pressScale()
    }
}

// Drives an entrance reveal when the page becomes the active tab, honoring
// Reduce Motion (instant) vs. the app's standard spring.
private struct Reveal: ViewModifier {
    let shown: Bool
    let delay: Double
    let offset: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : offset)
            .animation(reduceMotion ? nil
                       : .spring(response: 0.55, dampingFraction: 0.82).delay(delay),
                       value: shown)
    }
}

private extension View {
    func reveal(_ shown: Bool, delay: Double = 0, offset: CGFloat = 26,
                reduceMotion: Bool) -> some View {
        modifier(Reveal(shown: shown, delay: delay, offset: offset,
                        reduceMotion: reduceMotion))
    }
}

// MARK: - Page ①: Vision (cards stacking up)

private struct VisionPage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            illustration
                .frame(maxHeight: 280)
            Spacer(minLength: 24)
            PageCopy(title: "いつかやりたいを、\nすぐ保存。",
                     message: "「いつかやりたい」を、未来の自分のために保存。少しずつ叶えて、人生をちょっとよくしませんか？")
            Spacer(minLength: 20)
        }
        .onAppear { if isActive { reveal() } }
        .onChange(of: isActive) { _, active in if active { reveal() } }
    }

    private var illustration: some View {
        ZStack {
            miniCard(title: "京都で紅葉を見る",
                     chip: AnyView(SeasonChip(tag: .season(.fall))),
                     priority: .maybe)
                .rotationEffect(.degrees(-7))
                .offset(x: -46, y: 36)
                .reveal(shown, delay: 0.05, offset: 40, reduceMotion: reduceMotion)

            miniCard(title: "海でキャンプ",
                     chip: AnyView(SeasonChip(tag: .season(.summer))),
                     priority: .someday)
                .rotationEffect(.degrees(6))
                .offset(x: 50, y: 8)
                .reveal(shown, delay: 0.15, offset: 40, reduceMotion: reduceMotion)

            miniCard(title: "あの店のランチに行く",
                     chip: AnyView(SeasonChip(tag: .any)),
                     priority: .top)
                .offset(y: -34)
                .reveal(shown, delay: 0.25, offset: 40, reduceMotion: reduceMotion)
        }
        .accessibilityHidden(true)
    }

    private func miniCard(title: String, chip: AnyView, priority: Priority) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.Font.display(15, weight: .bold))
                .foregroundColor(Theme.Color.ink0)
                .lineLimit(1)
            HStack(spacing: 6) {
                PriorityPill(priority: priority)
                chip
            }
        }
        .padding(14)
        .frame(width: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.Color.paper0))
        .floatShadow()
    }

    private func reveal() { shown = true }
}

// MARK: - Page ②: Capture + AI (share → AI drafts the card)

private struct CapturePage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            illustration
                .frame(maxHeight: 280)
            Spacer(minLength: 24)
            PageCopy(title: "登録は、ワンタップ。",
                     message: "他のアプリの共有ボタンから1タップで登録。AIが優先度や季節を補完するから、入力いらず。もちろん、自分で自由に設定することもできます。")
            Spacer(minLength: 20)
        }
        .onAppear { if isActive { reveal() } }
        .onChange(of: isActive) { _, active in if active { reveal() } }
    }

    private var illustration: some View {
        VStack(spacing: 14) {
            // capture entry row
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Color.green700)
                Text("共有 / 手入力で追加")
                    .font(Theme.Font.sans(12.5, weight: .semibold))
                    .foregroundColor(Theme.Color.ink1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Theme.Color.green50)
                .overlay(Capsule().stroke(Theme.Color.green700.opacity(0.18), lineWidth: 1)))
            .reveal(shown, delay: 0.05, reduceMotion: reduceMotion)

            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.Color.ink3)
                .reveal(shown, delay: 0.15, reduceMotion: reduceMotion)

            // the card the chips land on
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("沖縄に行く")
                        .font(Theme.Font.display(16, weight: .bold))
                        .foregroundColor(Theme.Color.ink0)
                    Spacer(minLength: 8)
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("AI候補")
                            .font(Theme.Font.sans(10.5, weight: .bold))
                    }
                    .foregroundColor(Theme.Color.green700)
                    .reveal(shown, delay: 0.30, offset: 8, reduceMotion: reduceMotion)
                }
                HStack(spacing: 6) {
                    PriorityChip(priority: .top)
                        .reveal(shown, delay: 0.40, offset: 14, reduceMotion: reduceMotion)
                    SeasonChip(tag: .season(.summer))
                        .reveal(shown, delay: 0.50, offset: 14, reduceMotion: reduceMotion)
                    TagChip(key: "travel")
                        .reveal(shown, delay: 0.60, offset: 14, reduceMotion: reduceMotion)
                }
            }
            .padding(16)
            .frame(width: 250, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Color.paper0))
            .floatShadow()
            .reveal(shown, delay: 0.22, reduceMotion: reduceMotion)
        }
        .accessibilityHidden(true)
    }

    private func reveal() { shown = true }
}

// MARK: - Page ③: Report (look back + AI proposes what's next)
// Two halves, matching the real ReportView: the bar chart is the retrospective
// 達成ペース; the card below is the timing-aware proposal — its labels mirror the
// app's TimingSuggestion framelines ("今週末におすすめ" / "{季節}が終わる前に").

private struct ReportPage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    // Relative bar heights (last = tallest), drawn from a flat baseline.
    private let bars: [CGFloat] = [30, 52, 42, 70, 88]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            illustration
                .frame(maxHeight: 300)
            Spacer(minLength: 22)
            PageCopy(title: "ふり返って、\n次の一歩へ。",
                     message: "達成はレポートでふり返り。今のペースに合わせて、次にやるとよいことをAIが提案します。")
            Spacer(minLength: 20)
        }
        .onAppear { if isActive { reveal() } }
        .onChange(of: isActive) { _, active in if active { reveal() } }
    }

    private var illustration: some View {
        VStack(spacing: 16) {
            // ふり返り — this year's achievements
            VStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("今年 達成")
                        .font(Theme.Font.sans(12, weight: .bold))
                }
                .foregroundColor(Theme.Color.green700)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Theme.Color.green50))

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(bars.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Theme.Color.green300, Theme.Color.green500],
                                startPoint: .bottom, endPoint: .top))
                            .frame(width: 26, height: shown ? bars[i] : 0)
                            .animation(reduceMotion ? nil
                                       : .spring(response: 0.55, dampingFraction: 0.72)
                                           .delay(0.12 + Double(i) * 0.07),
                                       value: shown)
                    }
                }
                .frame(height: 92, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.Color.paper4).frame(height: 2)
                }
            }
            .reveal(shown, delay: 0.05, offset: 10, reduceMotion: reduceMotion)

            // これから — AI proposes the next thing by timing
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("AIのおすすめ")
                        .font(Theme.Font.sans(11, weight: .bold))
                }
                .foregroundColor(Theme.Color.green700)

                suggestRow(when: "今週末に", title: "海でキャンプ")
                suggestRow(when: "夏が終わる前に", title: "花火大会に行く")
            }
            .padding(14)
            .frame(width: 250, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Color.paper0))
            .floatShadow()
            .reveal(shown, delay: 0.45, reduceMotion: reduceMotion)
        }
        .accessibilityHidden(true)
    }

    private func suggestRow(when: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(when)
                .font(Theme.Font.sans(10.5, weight: .bold))
                .foregroundColor(Theme.Color.green700)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Color.green50))
            Text(title)
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundColor(Theme.Color.ink0)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func reveal() { shown = true }
}

// MARK: - Page ④: Initial setup (name + yearly goal)

private struct SetupPage: View {
    let isActive: Bool
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var goalFocused: Bool
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 8)
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundColor(Theme.Color.green500)
                    .rotationEffect(.degrees(shown && !reduceMotion ? 0 : -12), anchor: .bottom)
                    .animation(reduceMotion ? nil
                               : .spring(response: 0.5, dampingFraction: 0.4), value: shown)
                    .padding(.top, 12)
                    .accessibilityHidden(true)

                PageCopy(title: "準備は、これだけ。",
                         message: "あとから設定でいつでも変えられます。")
                    .padding(.top, 18)

                VStack(spacing: 18) {
                    fieldNameRow
                    Divider().overlay(Theme.Color.hairline)
                    goalRow
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.Color.paper0))
                .floatShadow()
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .reveal(shown, delay: 0.05, reduceMotion: reduceMotion)

                Spacer(minLength: 20)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { goalFocused = false }
                    .font(Theme.Font.sans(15, weight: .semibold))
            }
        }
        .onAppear { if isActive { reveal() } }
        .onChange(of: isActive) { _, active in if active { reveal() } }
    }

    private var fieldNameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("お名前（呼び方）")
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundColor(Theme.Color.ink2)
            TextField("あなた", text: $store.tweaks.userName)
                .font(Theme.Font.display(17, weight: .semibold))
                .foregroundColor(Theme.Color.ink0)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        }
    }

    private var goalRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今年の目標")
                    .font(Theme.Font.sans(14.5, weight: .semibold))
                    .foregroundColor(Theme.Color.ink0)
                Text("達成したい数の目安")
                    .font(Theme.Font.sans(11.5))
                    .foregroundColor(Theme.Color.ink2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                TextField("100", value: $store.tweaks.yearGoal, format: .number)
                    .keyboardType(.numberPad)
                    .focused($goalFocused)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.Font.display(22, weight: .bold))
                    .foregroundColor(Theme.Color.green700)
                    .frame(width: 80)
                Text("件")
                    .font(Theme.Font.sans(14, weight: .medium))
                    .foregroundColor(Theme.Color.ink2)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Color.green50))
        }
    }

    private func reveal() { shown = true }
}

// MARK: - Page ⑤: Notification permission (timely AI nudges)

private struct NotifyPage: View {
    let isActive: Bool
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 16)

                PageCopy(title: "いつかを、その時に。",
                         message: "AIがその時々で「次にやること」を、やりたいことの名前つきでお知らせします。")

                notificationPreview
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .reveal(shown, delay: 0.08, reduceMotion: reduceMotion)

                togglesCard
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .reveal(shown, delay: 0.18, reduceMotion: reduceMotion)

                privacyNote
                    .padding(.horizontal, 32)
                    .padding(.top, 22)
                    .reveal(shown, delay: 0.24, reduceMotion: reduceMotion)

                Spacer(minLength: 20)
            }
        }
        .onAppear { if isActive { reveal() } }
        .onChange(of: isActive) { _, active in if active { reveal() } }
    }

    // A faux lock-screen surface carrying one real-looking iOS banner. The copy
    // mirrors NotificationPlanner.weekendCopy so the preview matches reality.
    private var notificationPreview: some View {
        notificationBanner(time: "今",
                           title: "今週末はどう過ごす？",
                           message: "今週末は「あの店のランチに行く」、いかがですか？")
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Theme.Color.green50, Theme.Color.peach100.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            )
    }

    // Styled to read as a system notification (frosted material, app icon,
    // app name + time), not as one of the app's own cards.
    private func notificationBanner(time: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Theme.Color.green500, Theme.Color.green700],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "checklist")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Wishes")
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .foregroundColor(Theme.Color.ink2)
                        .tracking(0.3)
                    Spacer()
                    Text(time)
                        .font(Theme.Font.sans(11))
                        .foregroundColor(Theme.Color.ink3)
                }
                Text(title)
                    .font(Theme.Font.sans(13.5, weight: .bold))
                    .foregroundColor(Theme.Color.ink0)
                Text(message)
                    .font(Theme.Font.sans(12.5))
                    .foregroundColor(Theme.Color.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement(children: .combine)
    }

    // Honest, concise privacy line. Avoids "完全オフライン/一切通信しない" claims —
    // opening a shared link still reaches out from the device.
    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Color.ink3)
            Text("データは端末内にのみ保存。アカウント不要で、広告やトラッキングはありません。AIは端末内で動作します。")
                .font(Theme.Font.sans(11.5))
                .foregroundColor(Theme.Color.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var togglesCard: some View {
        VStack(spacing: 0) {
            nudgeRow("シーズン通知", "季節のはじまりにおすすめを通知",
                     isOn: $store.tweaks.seasonNudge)
            Divider().overlay(Theme.Color.hairline)
            nudgeRow("週末リマインド", "金曜の夕方に今週末の候補を通知",
                     isOn: $store.tweaks.weekendNudge)
            Divider().overlay(Theme.Color.hairline)
            nudgeRow("月末リマインド", "今月のものを月末に通知",
                     isOn: $store.tweaks.monthEndNudge)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.Color.paper0))
        .floatShadow()
    }

    private func nudgeRow(_ label: String, _ sub: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Font.sans(14.5, weight: .semibold))
                    .foregroundColor(Theme.Color.ink0)
                Text(sub)
                    .font(Theme.Font.sans(11.5))
                    .foregroundColor(Theme.Color.ink2)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle(tint: Theme.Color.green500))
                .labelsHidden()
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)。\(sub)")
    }

    private func reveal() { shown = true }
}
