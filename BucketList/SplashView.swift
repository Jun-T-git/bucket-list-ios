import SwiftUI

// MARK: - SplashView
// Cold-launch splash. Mirrors the app icon's story so the launch reads as a
// continuation of the icon the user just tapped: a yellow highlighter stroke
// sweeps in → the green check draws itself → two sparkles pop → the wordmark
// rises. Then the whole thing fades into the app (onFinish).
//
// Drawn entirely in SwiftUI (no images) on the app's own page wash, so the
// transition from the static generated launch screen and into ContentView is
// seamless. Honors Reduce Motion by presenting the final frame and holding
// briefly instead of animating.

struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Animation stages, advanced in sequence from .task.
    @State private var highlight: CGFloat = 0   // marker sweep   0→1
    @State private var check: CGFloat = 0       // checkmark draw 0→1
    @State private var sparkles = false         // stars pop
    @State private var wordmark = false         // text rises
    @State private var lift = false             // gentle overall settle
    @State private var didFinish = false        // guards against double onFinish

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 26) {
                mark
                    .frame(width: 168, height: 168)
                    .scaleEffect(lift ? 1 : 0.86)

                VStack(spacing: 7) {
                    Text("Wishes")
                        .font(Theme.Font.display(26, weight: .bold))
                        .foregroundColor(Theme.Color.ink0)
                    Text("「いつか」をちゃんと叶えよう。")
                        .font(Theme.Font.sans(14, weight: .medium))
                        .foregroundColor(Theme.Color.ink2)
                }
                .opacity(wordmark ? 1 : 0)
                .offset(y: wordmark ? 0 : 12)
            }
            .offset(y: -8)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Wishes")
        .accessibilityHint("タップで起動")
        .task { await play() }
    }

    // Calls onFinish exactly once, whether reached by the sequence or a tap.
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }

    // MARK: brand mark (highlighter + check + sparkles)

    private var mark: some View {
        ZStack {
            // Yellow highlighter stroke — swept in left→right behind the check.
            Capsule(style: .continuous)
                .fill(Theme.Color.sun300)
                .frame(width: 150, height: 46)
                .rotationEffect(.degrees(-3))
                .offset(y: 30)
                .scaleEffect(x: highlight, anchor: .leading)
                .opacity(highlight > 0 ? 1 : 0)

            // Green check — drawn on via path trim.
            CheckShape()
                .trim(from: 0, to: check)
                .stroke(Theme.Color.green700,
                        style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            // Sparkles — same two-tone, top-right placement as the icon.
            sparkle(color: Theme.Color.sun500, size: 26)
                .offset(x: 30, y: -66)
                .scaleEffect(sparkles ? 1 : 0)
                .rotationEffect(.degrees(sparkles ? 0 : -45))
            sparkle(color: Theme.Color.peach500, size: 38)
                .offset(x: 66, y: -50)
                .scaleEffect(sparkles ? 1 : 0)
                .rotationEffect(.degrees(sparkles ? 0 : 60))
        }
    }

    private func sparkle(color: Color, size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundColor(color)
    }

    // MARK: background — identical wash to ContentView for a seamless reveal.

    private var background: some View {
        ZStack {
            Theme.Color.pageBackground
            RadialGradient(colors: [Theme.Color.green50, .clear],
                           center: UnitPoint(x: 0.15, y: 0.08),
                           startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Theme.Color.peach100, .clear],
                           center: UnitPoint(x: 0.88, y: 0.92),
                           startRadius: 0, endRadius: 360)
        }
    }

    // MARK: sequence

    private func play() async {
        guard !reduceMotion else {
            highlight = 1; check = 1; sparkles = true; wordmark = true; lift = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            finish()
            return
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { lift = true }

        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.easeOut(duration: 0.3)) { highlight = 1 }

        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.easeOut(duration: 0.4)) { check = 1 }
        Haptics.tap()

        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { sparkles = true }
        Haptics.light()

        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { wordmark = true }

        try? await Task.sleep(nanoseconds: 400_000_000)
        finish()
    }
}

// A two-segment checkmark with the long, lifted upstroke from the app icon.
// Coordinates are normalized to the layout rect so trim() draws it in order
// (left tip → valley → top-right).
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.55))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.82))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.20))
        return p
    }
}

#Preview {
    SplashView(onFinish: {})
}
