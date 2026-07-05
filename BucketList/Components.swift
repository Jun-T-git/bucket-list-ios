import SwiftUI

// MARK: - ScreenHeader
// Shared header for every top-level tab (リスト / レポート / 設定). A single
// title line — the tab's own name — at one consistent size and padding, so
// switching tabs reads as one app rather than three separate screens.
struct ScreenHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Font.display(22, weight: .bold))
            .foregroundColor(Theme.Color.ink0)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16).padding(.bottom, 8)
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        // Cap the toast to the screen width minus side margins so a long
        // message wraps (up to 2 lines) instead of running off-screen. Short
        // messages still hug their content because maxWidth only sets a ceiling.
        let maxTextW = UIScreen.main.bounds.width - 96
        return HStack(spacing: 12) {
            Text(message)
                .font(Theme.Font.display(13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: maxTextW)
            if let actionLabel, let action {
                Button {
                    Haptics.tap()
                    action()
                } label: {
                    Text(actionLabel)
                        .font(Theme.Font.sans(12.5, weight: .bold))
                        .foregroundColor(Theme.Color.sun300)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(
                            Capsule().stroke(Theme.Color.sun300.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionLabel)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Theme.Color.toastSurface)
        )
        .floatShadow()
        .fixedSize(horizontal: false, vertical: true)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - PriorityPill

struct PriorityPill: View {
    let priority: Priority
    var size: Size = .sm

    enum Size { case sm, md }

    var body: some View {
        let pad: EdgeInsets = size == .sm
            ? .init(top: 5, leading: 10, bottom: 5, trailing: 10)
            : .init(top: 7, leading: 14, bottom: 7, trailing: 14)
        let fs: CGFloat = size == .sm ? 11 : 13

        HStack(spacing: 6) {
            Circle().fill(Color.white).frame(width: 7, height: 7)
            Text(priority.ja)
                .font(Theme.Font.sans(fs, weight: priority == .top ? .bold : .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(pad)
        .background(Capsule().fill(priority.color))
    }
}

// MARK: - SeasonChip

struct SeasonChip: View {
    let tag: SeasonTag
    var dim: Bool = false

    var body: some View {
        let bg: Color = {
            if case .any = tag { return Theme.Color.paper1 }
            return Theme.Color.paper2
        }()
        return Text(tag.ja)
            .font(Theme.Font.sans(11, weight: .medium))
            .foregroundColor(dim ? Theme.Color.ink3 : Theme.Color.ink1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(bg)
                    .overlay(Capsule().stroke(Theme.Color.cardBorder, lineWidth: 1))
            )
            .fixedSize()
    }
}

struct SeasonChipsRow: View {
    let seasons: [SeasonTag]
    var max: Int = 3
    var dim: Bool = false

    var body: some View {
        let tags = seasons.isEmpty ? [SeasonTag.any] : seasons
        let shown = Array(tags.prefix(max))
        let more = tags.count - shown.count
        FlowLayout(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, t in
                SeasonChip(tag: t, dim: dim)
            }
            if more > 0 {
                Text("+\(more)")
                    .font(Theme.Font.mono(10))
                    .foregroundColor(Theme.Color.ink2)
            }
        }
    }
}

// MARK: - PriorityChip

// Display-only chip for the list row. Mirrors SeasonChip's neutral capsule so
// priority sits alongside seasons / tags as one of the row's chips — never as a
// control. The small green dot + 高/中/低 label matches the priority affordance
// already used on the filter / add screens, so the app reads one language.
struct PriorityChip: View {
    let priority: Priority
    var dim: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dim ? Theme.Color.ink3 : priority.color)
                .frame(width: 7, height: 7)
            Text(priority.ja)
                .font(Theme.Font.sans(11, weight: .medium))
                .foregroundColor(dim ? Theme.Color.ink3 : Theme.Color.ink1)
        }
        .padding(.leading, 7).padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Theme.Color.paper2)
                .overlay(Capsule().stroke(Theme.Color.cardBorder, lineWidth: 1))
        )
        .fixedSize()
    }
}

// MARK: - TagChip

struct TagChip: View {
    let key: String
    var dim: Bool = false
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 2) {
            Text("#")
                .font(Theme.Font.mono(11, weight: .medium))
                .foregroundColor((dim ? Theme.Color.ink3 : Theme.Color.green700).opacity(0.55))
            Text(store.tagMeta(for: key).ja)
                .font(Theme.Font.sans(11, weight: .semibold))
                .foregroundColor(dim ? Theme.Color.ink3 : Theme.Color.green700)
        }
        .padding(.leading, 7).padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(dim ? Theme.Color.paper2 : Theme.Color.green50)
                .overlay(Capsule().stroke(
                    dim ? Theme.Color.cardBorder : Theme.Color.green700.opacity(0.20),
                    lineWidth: 1))
        )
        .fixedSize()
    }
}

struct TagChipsRow: View {
    let tags: [String]
    var max: Int = 3
    var dim: Bool = false

    var body: some View {
        let shown = Array(tags.prefix(max))
        let more = tags.count - shown.count
        FlowLayout(spacing: 4) {
            ForEach(shown, id: \.self) { k in
                TagChip(key: k, dim: dim)
            }
            if more > 0 {
                Text("+\(more)")
                    .font(Theme.Font.mono(10))
                    .foregroundColor(Theme.Color.ink2)
            }
        }
    }
}

// MARK: - Check (standard done toggle)

// Selection circle shown only in selection mode (Mail-style). Empty ring when
// unselected, filled green with a white check when selected. Done state is
// shown separately by the green check next to the title.
struct RowSelectCircle: View {
    let selected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(selected ? Theme.Color.green700 : Color.clear)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().stroke(selected ? Color.clear : Theme.Color.ink3, lineWidth: 2)
                    )
                if selected {
                    CheckmarkShape()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 11)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.14), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "選択中" : "未選択")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("タップして選択")
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Convert viewBox 18×14 path to rect-relative.
        var p = Path()
        let sx = rect.width / 18, sy = rect.height / 14
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }
        p.move(to: pt(1.5, 6))
        p.addQuadCurve(to: pt(5.5, 10.5), control: pt(3.5, 7))
        p.addQuadCurve(to: pt(8, 11), control: pt(6.5, 12.5))
        p.addQuadCurve(to: pt(16.5, 1.5), control: pt(12, 5))
        return p
    }
}

// MARK: - FlowLayout / SectionLabel
// Moved to ItemForm.swift (a file shared by both the app and the share
// extension) so the standalone extension can use them too. Components.swift
// stays app-only because TagChip/TagChipsRow below depend on AppStore.

// MARK: - Press scale modifier

struct PressScale: ViewModifier {
    @State private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
            // Visual-only press feedback. `perform:` is intentionally empty — this
            // does NOT replace tap handling (the underlying Button/onTapGesture owns
            // that), it only tracks the pressing state to drive the scale. Kept as a
            // long-press observer so it layers on top of a real control without
            // swallowing its tap. Behaviour is unchanged; CTA call sites that want a
            // standard hit target should rely on their own Button, not this modifier.
            .onLongPressGesture(minimumDuration: 0.001, maximumDistance: .infinity, pressing: { pressed = $0 }, perform: {})
    }
}
extension View {
    func pressScale() -> some View { modifier(PressScale()) }
}

// MARK: - Year-month picker
// A native DatePicker always exposes a day component, but achievements only ever
// need 年月 (the report aggregates by year+month). This shows a compact
// "2026年 6月" button that expands into two standard wheels. The bound date is
// normalised to the 1st of the chosen month and never exceeds `latest`.
struct YearMonthPicker: View {
    @Binding var date: Date
    var latest: Date = Clock.today
    @State private var expanded = false

    private var cal: Calendar { Clock.calendar }
    private var year: Int { cal.component(.year, from: date) }
    private var month: Int { cal.component(.month, from: date) }
    private var latestYear: Int { cal.component(.year, from: latest) }
    private var latestMonth: Int { cal.component(.month, from: latest) }
    private var years: [Int] { Array((latestYear - 10)...latestYear) }
    // Cap the months in the latest year so a future month can't be selected.
    private var months: [Int] { Array(1...(year == latestYear ? latestMonth : 12)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    // String(year) avoids the locale thousands separator (2,026年).
                    Text("\(String(year))年 \(month)月")
                        .font(Theme.Font.sans(15, weight: .semibold))
                        .foregroundColor(Theme.Color.ink0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Color.ink3)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.Color.paper2))
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: 0) {
                    Picker("年", selection: Binding(
                        get: { year },
                        set: { commit(year: $0, month: month) }
                    )) {
                        ForEach(years, id: \.self) { Text("\(String($0))年").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Picker("月", selection: Binding(
                        get: { month },
                        set: { commit(year: year, month: $0) }
                    )) {
                        ForEach(months, id: \.self) { Text("\($0)月").tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 140)
                .tint(Theme.Color.green700)
            }
        }
    }

    private func commit(year y: Int, month m: Int) {
        let clampedMonth = (y == latestYear) ? min(m, latestMonth) : m
        var c = DateComponents()
        c.year = y; c.month = clampedMonth; c.day = 1
        if let d = cal.date(from: c) { date = d }
    }
}
