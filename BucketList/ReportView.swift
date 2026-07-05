import SwiftUI

// MARK: - Report data

struct MonthlyBucket: Identifiable {
    let id = UUID()
    let month: Int
    let year: Int
    var top: Int
    var maybe: Int
    var someday: Int
    var total: Int { top + maybe + someday }
}

struct ReportData {
    let hist: [MonthlyBucket]     // continuous timeline: oldest achievement month → this month
    let lifetime: Int            // all-time done count
    let thisYearDone: Int        // current calendar year done count
    let monthsRemaining: Int
    let currentPace: Double
    let projection: Double
    let targetPace: Double
    let gap: Double
    let pendingBySeason: [Season: [BucketItem]]
}

extension AppStore {
    // Aggregated from the user's actual doneAt history — the report only ever
    // shows things that really happened. The summary, pace and 季節 sections are
    // always current-year; the chart spans every month from the first
    // achievement to now (scrollable) and is scoped separately in the view.
    func report(yearGoal: Int) -> ReportData {
        let cal = Clock.calendar
        let doneItems = items.filter(\.done)

        // Continuous month timeline. Floor at the earliest achievement; with no
        // achievements yet, start at January of the current year so the empty
        // chart still reads as "this year so far".
        let earliest = doneItems.compactMap(\.doneAt).min()
            ?? cal.date(from: DateComponents(year: Clock.year, month: 1, day: 1))
            ?? Clock.today
        var hist: [MonthlyBucket] = []
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: earliest)) ?? earliest
        let endAnchor = cal.date(from: cal.dateComponents([.year, .month], from: Clock.today)) ?? Clock.today
        while cursor <= endAnchor {
            hist.append(MonthlyBucket(month: cal.component(.month, from: cursor),
                                      year: cal.component(.year, from: cursor),
                                      top: 0, maybe: 0, someday: 0))
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        for it in doneItems {
            guard let at = it.doneAt else { continue }
            let m = cal.component(.month, from: at)
            let y = cal.component(.year, from: at)
            guard let idx = hist.firstIndex(where: { $0.month == m && $0.year == y }) else { continue }
            switch it.priority {
            case .top: hist[idx].top += 1
            case .maybe: hist[idx].maybe += 1
            case .someday: hist[idx].someday += 1
            }
        }

        let lifetime = doneItems.count
        let thisYearDone = doneItems.filter {
            $0.doneAt.map { cal.component(.year, from: $0) } == Clock.year
        }.count
        let monthsElapsed = Clock.month
        let monthsRemaining = 12 - monthsElapsed
        let currentPace = Double(thisYearDone) / Double(max(1, monthsElapsed))
        let projection = currentPace * 12
        let targetPace = monthsRemaining > 0
            ? Double(max(0, yearGoal - thisYearDone)) / Double(monthsRemaining)
            : 0
        let gap = targetPace - currentPace

        var pending: [Season: [BucketItem]] = [:]
        for s in Season.order { pending[s] = [] }
        for it in items where !it.done {
            let tags = it.normalizedSeasons
            var reached: Set<Season> = []
            for t in tags {
                if case .season(let s) = t { reached.insert(s) }
            }
            if reached.isEmpty {
                reached.insert(Clock.season)
                reached.insert(Clock.nextSeason)
            }
            for s in reached { pending[s, default: []].append(it) }
        }
        for s in Season.order {
            pending[s]?.sort { $0.priority.weight > $1.priority.weight }
        }

        return ReportData(
            hist: hist, lifetime: lifetime, thisYearDone: thisYearDone,
            monthsRemaining: monthsRemaining,
            currentPace: currentPace, projection: projection,
            targetPace: targetPace, gap: gap, pendingBySeason: pending
        )
    }
}

// MARK: - ReportView

struct ReportView: View {
    @EnvironmentObject var store: AppStore

    // Which achievement year the report is focused on. @State survives tab
    // switches, so it's explicitly reset to 今年 in onAppear — "今年" is the
    // default story; reaching back is an explicit tap.
    @State private var scope: YearScope = .year(Clock.year)

    var body: some View {
        let years = store.achievementYears
        let r = store.report(yearGoal: store.goal(forYear: Clock.year))
        let footerPrefix: String = {
            switch scope {
            case .all: return "累計"
            case .year(let y): return y == Clock.year ? "今年" : "\(y)年に"
            }
        }()
        let periodLabel: String = {
            switch scope {
            case .all: return "全期間"
            case .year(let y): return y == Clock.year ? "今年" : "\(y)年"
            }
        }()
        let periodGoal: Int = {
            switch scope {
            case .year(let y): return store.goal(forYear: y)
            case .all: return years.reduce(0) { $0 + store.goal(forYear: $1) }
            }
        }()
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "レポート")

                // Summary, pace and seasons are always current-year — fixed.
                AchievementSummaryCard(r: r)
                    .padding(.horizontal, 20)

                // 達成ペース — the ONLY area the period selector scopes.
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "達成ペース", sub: nil)
                    // Always visible so the period switch is discoverable; with
                    // only this year's data it shows 今年 / 全期間.
                    YearScopeSelector(years: years, scope: $scope)
                    if r.lifetime > 0 {
                        MonthlyStackChart(hist: r.hist, footerPrefix: footerPrefix,
                                          footerCount: scopeCount(scope, r), scope: scope)
                            .padding(.horizontal, 20)
                    } else {
                        EmptyChartCard()
                            .padding(.horizontal, 20)
                    }
                    // Period-scoped figures: current backlog, the period's
                    // achievements, and the period's goal (editable per year).
                    PeriodStatsCard(
                        periodLabel: periodLabel,
                        openCount: store.items.filter { !$0.done }.count,
                        doneCount: scopeCount(scope, r),
                        goal: periodGoal,
                        editYear: { if case .year(let y) = scope { return y } else { return nil } }(),
                        onSetGoal: { y, v in store.setGoal(v, forYear: y) }
                    )
                    .padding(.horizontal, 20)
                }

                SectionTitle(title: "目標との差", sub: nil)
                PaceCard(r: r, goal: store.goal(forYear: Clock.year),
                         onGoalChange: { v in store.setGoal(v, forYear: Clock.year) })
                    .padding(.horizontal, 20)

                SectionTitle(title: "これからの季節", sub: nil)
                VStack(spacing: 10) {
                    ForEach(Season.upcoming(from: Clock.season), id: \.self) { s in
                        SeasonPlanCard(
                            season: s,
                            items: r.pendingBySeason[s] ?? []
                        )
                    }
                }
                .padding(.horizontal, 20)

                Color.clear.frame(height: 16)
            }
        }
        // @State persists across tab switches; reset to 今年 on every appear so
        // the report always opens on the current year, as intended.
        .onAppear { scope = .year(Clock.year) }
    }

    // Done count for the chart's selected period — the chip scope only ever
    // feeds the 達成ペース area, never the rest of the tab.
    private func scopeCount(_ scope: YearScope, _ r: ReportData) -> Int {
        switch scope {
        case .all: return r.lifetime
        case .year(let y): return r.hist.filter { $0.year == y }.reduce(0) { $0 + $1.total }
        }
    }

}

// MARK: - YearScopeSelector
// Standard capsule chips (single-select) matching the filter sheet. Order:
// 今年 → newer … older years → 全期間, with 今年 (leading) selected by default.
struct YearScopeSelector: View {
    let years: [Int]
    @Binding var scope: YearScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(years.reversed(), id: \.self) { y in
                    let label = y == Clock.year ? "今年" : "\(y)"
                    chip(label: label, selected: scope == .year(y)) { scope = .year(y) }
                }
                chip(label: "全期間", selected: scope == .all) { scope = .all }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(label)
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundColor(selected ? .white : Theme.Color.ink0)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? Theme.Color.green700 : Theme.Color.paper0)
                        .overlay(Capsule()
                            .stroke(selected ? .clear : Theme.Color.cardBorder, lineWidth: 1))
                )
                // Keep the compact pill look but a comfortable 44pt tap target.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - AchievementSummaryCard
// At-a-glance達成サマリー — レポートを開いてすぐ累計と今年の達成が読める
// 先頭カード。数字の見た目は「目標との差」の PaceStat と揃えてある。
struct AchievementSummaryCard: View {
    let r: ReportData

    var body: some View {
        Group {
            if r.lifetime == 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ここから始まります")
                        .font(Theme.Font.display(18, weight: .bold))
                        .foregroundColor(Theme.Color.ink0)
                        .accessibilityAddTraits(.isHeader)
                    Text("ひとつ達成すると、ここに記録されていきます。")
                        .font(Theme.Font.sans(13, weight: .regular))
                        .foregroundColor(Theme.Color.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    stat(label: "これまで", value: r.lifetime,
                         sub: "累計の達成", color: Theme.Color.green700)
                    Rectangle().fill(Theme.Color.hairline)
                        .frame(width: 1, height: 46)
                    stat(label: "今年", value: r.thisYearDone,
                         sub: "年間ペース \(Int(r.projection.rounded())) 件",
                         color: Theme.Color.green500)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Theme.Color.paper0)
        )
        .stickerShadow()
    }

    private func stat(label: String, value: Int, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Font.mono(10))
                .foregroundColor(Theme.Color.ink2)
                .tracking(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(Theme.Font.display(30, weight: .bold))
                    .foregroundColor(color)
                Text("件")
                    .font(Theme.Font.sans(11, weight: .medium))
                    .foregroundColor(Theme.Color.ink2)
            }
            Text(sub)
                .font(Theme.Font.hand(12))
                .foregroundColor(Theme.Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - PeriodStatsCard
// Three figures for the period chosen in 達成ペース: the current open backlog
// (period-independent), that period's achievements, and that period's goal.
// The goal is tappable to edit when a single year is selected.
struct PeriodStatsCard: View {
    let periodLabel: String       // "今年" / "2025年" / "全期間"
    let openCount: Int
    let doneCount: Int
    let goal: Int
    let editYear: Int?            // non-nil → goal is editable for this year
    let onSetGoal: (Int, Int) -> Void

    @State private var editingGoal = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            stat(label: "未達成", value: openCount, sub: "現在",
                 color: Theme.Color.ink0)
            divider
            stat(label: "達成", value: doneCount, sub: periodLabel,
                 color: Theme.Color.green700)
            divider
            goalStat
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Theme.Color.paper0)
        )
        .stickerShadow()
        .sheet(isPresented: $editingGoal) {
            if let y = editYear {
                GoalPickerSheet(
                    title: "\(periodLabel)の目標",
                    initial: goal,
                    range: 1...100,
                    onCommit: { v in onSetGoal(y, v) },
                    onClose: { editingGoal = false }
                )
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder private var goalStat: some View {
        if editYear != nil {
            Button {
                Haptics.tap()
                editingGoal = true
            } label: {
                statContent(label: "目標", value: goal,
                            sub: "タップで変更", color: Theme.Color.green500)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(periodLabel)の目標")
            .accessibilityValue("\(goal)件")
            .accessibilityHint("タップして目標の件数を変更します")
        } else {
            stat(label: "目標", value: goal, sub: periodLabel,
                 color: Theme.Color.green500)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.Color.hairline).frame(width: 1, height: 46)
    }

    private func stat(label: String, value: Int, sub: String, color: Color) -> some View {
        statContent(label: label, value: value, sub: sub, color: color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statContent(label: String, value: Int, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Font.mono(10))
                .foregroundColor(Theme.Color.ink2)
                .tracking(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(Theme.Font.display(28, weight: .bold))
                    .foregroundColor(color)
                Text("件")
                    .font(Theme.Font.sans(11, weight: .medium))
                    .foregroundColor(Theme.Color.ink2)
            }
            Text(sub)
                .font(Theme.Font.hand(12))
                .foregroundColor(Theme.Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Friendly placeholder for a chart with no data yet — a blank axis frame
// would read as broken.
struct EmptyChartCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 24))
                .foregroundColor(Theme.Color.ink3)
            Text("まだデータがありません")
                .font(Theme.Font.display(15, weight: .bold))
                .foregroundColor(Theme.Color.ink1)
            Text("リストのチェックを入れると、月ごとに記録されます")
                .font(Theme.Font.sans(12, weight: .regular))
                .foregroundColor(Theme.Color.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Theme.Color.paper0)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.Color.hairline, lineWidth: 1)
                )
        )
    }
}

// MARK: - SectionTitle

struct SectionTitle: View {
    let title: String
    let sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.Font.display(18, weight: .bold))
                .foregroundColor(Theme.Color.ink0)
                .accessibilityAddTraits(.isHeader)
            if let sub {
                Text(sub).font(Theme.Font.sans(12, weight: .regular))
                    .foregroundColor(Theme.Color.ink2)
            }
        }
        .padding(.horizontal, 20)
    }
}

// A vertical hairline used to mark a year boundary inside the scrollable chart.
private struct VLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        return p
    }
}

// MARK: - MonthlyStackChart
// Cumulative running totals as single-color bars. The whole timeline (first
// achievement → now) scrolls horizontally so the user can pan back one step at
// a time; `scope` decides where it auto-scrolls to. A 月 / 年 toggle switches
// the bar granularity between per-month and per-year columns.

enum ChartGranularity: String, CaseIterable, Hashable {
    case month, year
    var ja: String { self == .month ? "月" : "年" }
}

struct MonthlyStackChart: View {
    let hist: [MonthlyBucket]
    let footerPrefix: String   // "今年" / "2025年に" / "累計"
    let footerCount: Int
    let scope: YearScope

    @State private var granularity: ChartGranularity = .month

    private let colSpacing: CGFloat = 6

    // One rendered bar — already carries cumulative totals and display flags.
    private struct StackColumn: Identifiable {
        let id: Int
        let label: String       // "6" (month) or "2025" (year)
        let yearMark: String?   // "'26" tick above January in month view
        let isYearStart: Bool   // draw the dashed break line (month view)
        let isCurrent: Bool      // highlight as "now"
        let year: Int
        let top, maybe, someday: Int
        var total: Int { top + maybe + someday }
    }

    var body: some View {
        let cols = columns()
        let maxV = max(3, cols.last?.total ?? 0)
        let rowH: CGFloat = 130
        let padTop: CGFloat = 18
        let barMax = rowH - padTop
        let target = targetIndex(cols)
        let colWidth: CGFloat = granularity == .month ? 24 : 46

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Spacer()
                granularityToggle
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .bottom, spacing: colSpacing) {
                            ForEach(cols) { c in
                                bar(c: c, max: maxV, barMax: barMax)
                                    .frame(width: colWidth)
                                    .overlay(alignment: .leading) {
                                        if c.isYearStart {
                                            VLine()
                                                .stroke(Theme.Color.cardBorder,
                                                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                                .frame(width: 1)
                                                .offset(x: -(colSpacing / 2))
                                        }
                                    }
                                    .id(c.id)
                            }
                        }
                        .frame(height: rowH)

                        HStack(spacing: colSpacing) {
                            ForEach(cols) { c in
                                VStack(spacing: 0) {
                                    if let ym = c.yearMark {
                                        Text(ym)
                                            .font(Theme.Font.mono(8))
                                            .foregroundColor(Theme.Color.ink3)
                                    }
                                    Text(c.label)
                                        .font(Theme.Font.mono(9, weight: c.isCurrent ? .bold : .regular))
                                        .foregroundColor(c.isCurrent ? Theme.Color.peach700 : Theme.Color.ink3)
                                }
                                .frame(width: colWidth)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onAppear {
                    // Defer so layout exists before scrolling to the latest step.
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .trailing)
                    }
                }
                .onChange(of: target) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newValue, anchor: .trailing)
                    }
                }
                .onChange(of: granularity) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(target, anchor: .trailing)
                        }
                    }
                }
            }

            HStack(spacing: 2) {
                Text("\(footerPrefix) ")
                Text("\(footerCount)")
                    .font(Theme.Font.display(13, weight: .bold))
                    .foregroundColor(Theme.Color.green700)
                Text(" 件達成")
            }
            .font(Theme.Font.sans(12.5, weight: .medium))
            .foregroundColor(Theme.Color.ink1)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Theme.Color.paper2)
            )
        }
        .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Theme.Color.paper0)
        )
        .paperShadow()
        // 全期間 reads best as one bar per year; a single year as months. The
        // user can still flip the toggle afterward.
        .onAppear { if scope == .all { granularity = .year } }
        .onChange(of: scope) { _, ns in granularity = ns == .all ? .year : .month }
    }

    // 月 / 年 segmented toggle — standard granularity switch.
    private var granularityToggle: some View {
        HStack(spacing: 0) {
            ForEach(ChartGranularity.allCases, id: \.self) { g in
                Button {
                    Haptics.select()
                    granularity = g
                } label: {
                    Text(g.ja)
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .foregroundColor(granularity == g ? .white : Theme.Color.ink2)
                        .frame(width: 40, height: 44)
                        .background(granularity == g ? Theme.Color.green700 : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(g == .month ? "月表示" : "年表示")
                .accessibilityAddTraits(granularity == g ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(Theme.Color.paper2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
    }

    // Cumulative columns for the chosen granularity. Month view is one column
    // per recorded month; year view collapses each calendar year into one.
    private func columns() -> [StackColumn] {
        switch granularity {
        case .month:
            var out: [StackColumn] = []
            var t = 0, m = 0, s = 0
            for (idx, h) in hist.enumerated() {
                t += h.top; m += h.maybe; s += h.someday
                let yearStart = idx == 0 || h.year != hist[idx - 1].year
                out.append(StackColumn(
                    id: idx,
                    label: "\(h.month)",
                    yearMark: yearStart ? "'\(h.year % 100)" : nil,
                    isYearStart: idx > 0 && yearStart,
                    isCurrent: h.year == Clock.year && h.month == Clock.month,
                    year: h.year, top: t, maybe: m, someday: s))
            }
            return out
        case .year:
            var order: [Int] = []
            var agg: [Int: (Int, Int, Int)] = [:]
            for h in hist {
                if agg[h.year] == nil { order.append(h.year); agg[h.year] = (0, 0, 0) }
                agg[h.year]!.0 += h.top; agg[h.year]!.1 += h.maybe; agg[h.year]!.2 += h.someday
            }
            var out: [StackColumn] = []
            var t = 0, m = 0, s = 0
            for (idx, y) in order.enumerated() {
                let c = agg[y] ?? (0, 0, 0)
                t += c.0; m += c.1; s += c.2
                out.append(StackColumn(
                    id: idx,
                    label: "\(y)",
                    yearMark: nil,
                    isYearStart: false,
                    isCurrent: y == Clock.year,
                    year: y, top: t, maybe: m, someday: s))
            }
            return out
        }
    }

    // Where the chart parks: the end of the selected year (or the latest column
    // for 今年 / すべて). Works for both granularities via the column's year.
    private func targetIndex(_ cols: [StackColumn]) -> Int {
        switch scope {
        case .all:
            return max(0, cols.count - 1)
        case .year(let y):
            return cols.lastIndex(where: { $0.year == y }) ?? max(0, cols.count - 1)
        }
    }

    private func bar(c: StackColumn, max: Int, barMax: CGFloat) -> some View {
        let barH = CGFloat(c.total) / CGFloat(max) * barMax
        let tot = c.total
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(c.isCurrent ? Theme.Color.green700 : Theme.Color.green500)
                .frame(maxWidth: 18)
                .frame(height: barH)

            if tot > 0 {
                Text("\(tot)")
                    .font(Theme.Font.display(10, weight: .bold))
                    .foregroundColor(c.isCurrent ? Theme.Color.peach700 : Theme.Color.ink1)
                    .offset(y: -(barH + 8))
            }
            if c.isCurrent {
                Circle().fill(Theme.Color.peach700)
                    .frame(width: 5, height: 5)
                    .offset(y: -(barMax + 4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - PaceCard

struct PaceCard: View {
    let r: ReportData
    let goal: Int
    let onGoalChange: (Int) -> Void

    @State private var editingGoal = false

    var body: some View {
        let remaining = max(0, goal - r.thisYearDone)
        let onTrack = r.projection >= Double(goal)
        let gapMsg = onTrack
            ? "このまま行けば届きます"
            : "あと月 \(String(format: "%.1f", max(0, r.gap))) 件で届きます"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                PaceStat(label: "今のペース",
                         valueMain: String(format: "%.1f", r.currentPace),
                         valueUnit: "件/月",
                         sub: "年間 \(Int(r.projection.rounded())) 件のペース",
                         color: Theme.Color.green500)
                PaceStat(label: "目標のペース",
                         valueMain: String(format: "%.1f", r.targetPace),
                         valueUnit: "件/月",
                         sub: "残り \(remaining) 件 / \(r.monthsRemaining)ヶ月",
                         color: onTrack ? Theme.Color.green300 : Theme.Color.peach700)
            }
            .padding(.bottom, 14)
            Rectangle().fill(Theme.Color.hairline).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: onTrack ? "checkmark.circle.fill" : "flag")
                    .font(.system(size: 13))
                    .foregroundColor(onTrack ? Theme.Color.green500 : Theme.Color.ink3)
                Text(gapMsg)
                    .font(Theme.Font.sans(14, weight: .medium))
                    .foregroundColor(onTrack ? Theme.Color.green700 : Theme.Color.ink1)
            }
            .padding(.top, 12).padding(.bottom, 14)

            Button {
                Haptics.tap()
                editingGoal = true
            } label: {
                HStack {
                    Text("今年の目標")
                        .font(Theme.Font.sans(14, weight: .semibold))
                        .foregroundColor(Theme.Color.ink1)
                    Spacer()
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text("\(goal)")
                            .font(Theme.Font.display(16, weight: .bold))
                            .foregroundColor(Theme.Color.ink0)
                        Text("件")
                            .font(Theme.Font.sans(10, weight: .medium))
                            .foregroundColor(Theme.Color.ink2)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Color.ink3)
                        .padding(.leading, 3)
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Theme.Color.paper1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("今年の目標")
            .accessibilityValue("\(goal)件")
            .accessibilityHint("タップして目標の件数を変更します")
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Theme.Color.paper0)
        )
        .stickerShadow()
        .sheet(isPresented: $editingGoal) {
            GoalPickerSheet(
                initial: goal,
                range: 1...100,
                onCommit: onGoalChange,
                onClose: { editingGoal = false }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }
}

struct PaceStat: View {
    let label: String
    let valueMain: String
    let valueUnit: String
    let sub: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Font.mono(10))
                .foregroundColor(Theme.Color.ink2)
                .tracking(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueMain)
                    .font(Theme.Font.display(30, weight: .bold))
                    .foregroundColor(color)
                Text(valueUnit)
                    .font(Theme.Font.sans(11, weight: .medium))
                    .foregroundColor(Theme.Color.ink2)
            }
            Text(sub)
                .font(Theme.Font.hand(12))
                .foregroundColor(Theme.Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Standard iOS wheel picker for the yearly goal — lets the user spin straight
// to any value instead of tapping +/− one at a time.
struct GoalPickerSheet: View {
    let title: String
    let initial: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void
    let onClose: () -> Void

    @State private var selection: Int

    init(title: String = "今年の目標", initial: Int, range: ClosedRange<Int>,
         onCommit: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.title = title
        self.initial = initial
        self.range = range
        self.onCommit = onCommit
        self.onClose = onClose
        _selection = State(initialValue: Swift.min(Swift.max(initial, range.lowerBound), range.upperBound))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("キャンセル") {
                    Haptics.tap()
                    onClose()
                }
                .font(Theme.Font.sans(15))
                .foregroundColor(Theme.Color.ink2)
                Spacer()
                Text(title)
                    .font(Theme.Font.display(16, weight: .bold))
                Spacer()
                Button("完了") {
                    Haptics.tap()
                    onCommit(selection)
                    onClose()
                }
                .font(Theme.Font.sans(15, weight: .semibold))
                .foregroundColor(Theme.Color.green700)
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 4)

            Picker(title, selection: $selection) {
                ForEach(Array(range), id: \.self) { v in
                    Text("\(v) 件").tag(v)
                }
            }
            .pickerStyle(.wheel)
            .onChange(of: selection) { _, _ in Haptics.select() }
        }
        .background(Theme.Color.pageBackground)
    }
}

// MARK: - SeasonPlanCard

struct SeasonPlanCard: View {
    let season: Season
    let items: [BucketItem]

    private var tint: Color {
        switch season {
        case .spring: return Theme.Color.green50
        case .summer: return Theme.Color.sun100
        case .fall:   return Theme.Color.peach100
        case .winter: return Theme.Color.paper2
        }
    }

    private var isCurrent: Bool { season == Clock.season }

    var body: some View {
        let top3 = Array(items.prefix(3))
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(season.ja)
                            .font(Theme.Font.display(22, weight: .bold))
                            .foregroundColor(Theme.Color.ink0)
                            .accessibilityAddTraits(.isHeader)
                        Text(season.monthsDisplay)
                            .font(Theme.Font.mono(9, weight: .semibold))
                            .foregroundColor(Theme.Color.ink2)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(items.count)")
                            .font(Theme.Font.display(28, weight: .bold))
                            .foregroundColor(items.isEmpty ? Theme.Color.ink3 : Theme.Color.ink0)
                        Text("件 予定")
                            .font(Theme.Font.sans(11, weight: .medium))
                            .foregroundColor(Theme.Color.ink2)
                    }
                }
                .frame(width: 108, alignment: .leading)
                .padding(.trailing, 12)
                .overlay(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 6))
                        p.addLine(to: CGPoint(x: 0, y: 70))
                    }
                    .stroke(Theme.Color.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 1).offset(x: 110),
                    alignment: .leading
                )
                VStack(alignment: .leading, spacing: 5) {
                    if top3.isEmpty {
                        Text("予定はありません。")
                            .font(Theme.Font.hand(13))
                            .foregroundColor(Theme.Color.ink2)
                    }
                    ForEach(top3) { it in
                        HStack(spacing: 7) {
                            Circle().fill(it.priority.color).frame(width: 7, height: 7)
                            Text(it.title)
                                .font(Theme.Font.sans(13, weight: it.priority == .top ? .bold : .medium))
                                .foregroundColor(it.priority == .top ? Theme.Color.ink0 : Theme.Color.ink1)
                                .lineLimit(1)
                        }
                    }
                    if items.count > 3 {
                        Text("+ あと\(items.count - 3)件")
                            .font(Theme.Font.mono(10))
                            .foregroundColor(Theme.Color.ink2)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            if isCurrent {
                Text("今")
                    .font(Theme.Font.sans(10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Color.green700))
                    .offset(x: -10, y: -7)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14).fill(tint)
        )
        .paperShadow()
    }
}
