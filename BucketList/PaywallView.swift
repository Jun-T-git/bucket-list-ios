import SwiftUI

// The Pro paywall. Presented as a sheet from 設定 or when the free auto-import
// allowance runs out. Plain, standard layout (no aggressive sales chrome): a
// short value list, the one-time price, a buy button, restore, and the legally
// required links. Dismisses itself the moment Pro is unlocked.
struct PaywallView: View {
    @EnvironmentObject var pro: ProStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    featureList
                    note
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Theme.Color.pageBackground)
            .safeAreaInset(edge: .bottom) { purchaseBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .font(Theme.Font.sans(15))
                        .foregroundColor(Theme.Color.ink2)
                }
            }
        }
        // Unlocked elsewhere (purchase or restore) → close automatically.
        .onChange(of: pro.isPro) { _, unlocked in
            if unlocked { dismiss() }
        }
        .task { if pro.product == nil { await pro.loadProduct() } }
    }

    // MARK: hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.Color.green700)
                Text("Wishes Pro")
                    .font(Theme.Font.display(24, weight: .bold))
                    .foregroundColor(Theme.Color.ink0)
            }
            Text("URLから、やりたいことを自動でリストに。")
                .font(Theme.Font.sans(15, weight: .medium))
                .foregroundColor(Theme.Color.ink1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            feature(icon: "link",
                    title: "URL取り込みが無制限",
                    body: "気になったページの共有ボタンや、リンクの貼り付けから、ワンタップでリストに追加。")
            feature(icon: "wand.and.stars",
                    title: "AIが自動で下書き",
                    body: "対応端末では、端末内のAIがタイトル・優先度・季節・タグまで自動で補完します。")
            feature(icon: "lock.shield",
                    title: "ずっと端末の中だけ",
                    body: "取り込みもAIもすべて端末内で完結。データが外部に送られることはありません。")
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.Color.paper0))
        .paperShadow()
    }

    private func feature(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.Color.green700)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.Color.green50))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Font.sans(15, weight: .bold))
                    .foregroundColor(Theme.Color.ink0)
                Text(body)
                    .font(Theme.Font.sans(12.5))
                    .foregroundColor(Theme.Color.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var note: some View {
        Text("一度のお支払いで、ずっとお使いいただけます（買い切り）。手入力での追加・閲覧・レポート・通知などの基本機能は、無料のままご利用いただけます。")
            .font(Theme.Font.sans(11.5))
            .foregroundColor(Theme.Color.ink3)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: purchase bar (pinned)

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            if let msg = pro.errorMessage {
                Text(msg)
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundColor(Theme.Color.peach700)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: { Task { await pro.purchase() } }) {
                HStack(spacing: 8) {
                    if pro.working {
                        ProgressView().tint(.white)
                    }
                    Text(buyLabel)
                        .font(Theme.Font.display(17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(Theme.Color.green700))
                .shadow(color: Theme.Color.green700.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(pro.working || pro.product == nil)
            .opacity(pro.product == nil ? 0.5 : 1)

            Button(action: { Task { await pro.restore() } }) {
                Text("購入を復元")
                    .font(Theme.Font.sans(14, weight: .semibold))
                    .foregroundColor(Theme.Color.green700)
            }
            .buttonStyle(.plain)
            .disabled(pro.working)

            HStack(spacing: 14) {
                NavigationLink("利用規約") { TermsOfUseView() }
                NavigationLink("プライバシー") { PrivacyPolicyView() }
            }
            .font(Theme.Font.sans(11.5))
            .foregroundColor(Theme.Color.ink3)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private var buyLabel: String {
        if let price = pro.displayPrice { return "Proにする　\(price)" }
        return "Proにする"
    }
}
