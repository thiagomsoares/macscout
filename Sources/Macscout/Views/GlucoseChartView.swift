import SwiftUI
import MacscoutCore

/// Glucose chart — dot-matrix ("pixel") style: a uniform grid of green dots
/// stacked from the baseline up to each reading, forming the curve's
/// silhouette. Dots fade with age; thresholds, pixel labels, treatment
/// markers and a hover tooltip complete the panel chart.
///
/// Split into layers so pointer movement stays cheap: the dot matrix lives in
/// an `Equatable` canvas that only redraws when data or size change, while the
/// hover line + tooltip render in a lightweight overlay.
struct GlucoseChartView: View {
    @ObservedObject var appState: AppState
    @State private var hovered: HoverTarget?

    /// What the pointer is over: a reading (mid-plot), an insulin dose (the
    /// lane below the plot) or a carb marker (the strip above it).
    enum HoverTarget: Equatable {
        case reading(GlucoseEntry, x: CGFloat)
        case treatment(Treatment, x: CGFloat)
    }

    private var unit: GlucoseUnit { appState.settings.unit }
    private var alertSettings: AlertSettings { appState.settings.alertSettings }

    private func toDisplay(_ mgdl: Double) -> Double { UnitConverter.toUnit(mgdl, unit) }

    private func axisLabel(_ mgdl: Double) -> String {
        let value = toDisplay(mgdl)
        return unit == .mmolL ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    var body: some View {
        GeometryReader { geo in
            let plot = ChartMetrics.plotRect(in: geo.size)
            let geom = ChartGeometry(entries: appState.chartEntries,
                                     alertSettings: alertSettings, plot: plot)

            ZStack(alignment: .topLeading) {
                DotMatrixCanvas(entries: appState.chartEntries,
                                treatments: appState.chartTreatments,
                                alertSettings: alertSettings,
                                plotSize: geo.size)
                    .equatable()

                hoverLayer(in: plot)
                labels(geom: geom, plot: plot)

                switch hovered {
                case .reading(let entry, let x):
                    tooltip(for: entry)
                        .position(x: min(max(x, plot.minX + 30), plot.maxX - 30),
                                  y: plot.minY + 10)
                case .treatment(let treatment, let x):
                    treatmentTooltip(for: treatment)
                        .position(x: min(max(x, plot.minX + 30), plot.maxX - 30),
                                  y: (treatment.insulin ?? 0) > 0 ? plot.maxY - 14 : plot.minY + 28)
                case nil:
                    EmptyView()
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let target: HoverTarget?
                    if location.y > plot.maxY,
                       let dose = geom.nearestTreatment(in: appState.chartTreatments,
                                                        atX: location.x, insulin: true) {
                        // Below the plot: the insulin lane.
                        target = .treatment(dose, x: geom.xPos(of: dose.createdAt))
                    } else if location.y < plot.minY + 14,
                              let carbs = geom.nearestTreatment(in: appState.chartTreatments,
                                                                atX: location.x, insulin: false) {
                        // The strip above the plot: carb markers.
                        target = .treatment(carbs, x: geom.xPos(of: carbs.createdAt))
                    } else {
                        target = geom.entry(atX: location.x).map {
                            .reading($0, x: geom.xPos(of: $0.date))
                        }
                    }
                    if target != hovered { hovered = target } // update only on change
                case .ended:
                    hovered = nil
                }
            }
        }
    }

    // MARK: - Hover layer (cheap: one dashed line)

    private var hoveredX: CGFloat? {
        switch hovered {
        case .reading(_, let x), .treatment(_, let x): return x
        case nil: return nil
        }
    }

    @ViewBuilder
    private func hoverLayer(in plot: CGRect) -> some View {
        if let x = hoveredX {
            Path { path in
                path.move(to: CGPoint(x: x, y: plot.minY))
                path.addLine(to: CGPoint(x: x, y: plot.maxY))
            }
            .stroke(Color.dsPhosphorPale.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
    }

    // MARK: - Labels

    private func labels(geom: ChartGeometry, plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // Y ticks.
            ForEach(geom.yTicks(unit: unit), id: \.self) { tick in
                Text(axisLabel(tick))
                    .font(.pixel(11))
                    .foregroundStyle(Color.dsPhosphorDim)
                    .position(x: ChartMetrics.leftW / 2, y: geom.yPos(of: tick))
            }
            // X ticks on round hours, below the insulin lane.
            ForEach(geom.xTicks, id: \.self) { tick in
                Text(tick, format: .dateTime.hour().minute())
                    .font(.pixel(11))
                    .foregroundStyle(Color.dsPhosphorDim)
                    .position(x: geom.xPos(of: tick), y: plot.maxY + ChartMetrics.bottomH - 9)
            }
            // Threshold values at the trailing edge.
            ForEach([alertSettings.lowThreshold, alertSettings.highThreshold], id: \.self) { threshold in
                Text(axisLabel(threshold))
                    .font(.pixel(11))
                    .foregroundStyle(Color.dsPhosphorDim.opacity(0.8))
                    .position(x: plot.maxX + ChartMetrics.rightW / 2 + 2, y: geom.yPos(of: threshold))
            }
        }
    }

    private func tooltip(for entry: GlucoseEntry) -> some View {
        tooltipCard(title: "\(axisLabel(entry.sgv)) \(entry.direction.arrow)",
                    titleColor: Color.dsPhosphorBright, date: entry.date)
    }

    private func treatmentTooltip(for treatment: Treatment) -> some View {
        let title: String
        if let units = treatment.insulin, units > 0 {
            title = "\(doseFormatter.string(from: units as NSNumber) ?? "\(units)")U"
        } else {
            title = "\(Int(treatment.carbs ?? 0))g"
        }
        return tooltipCard(title: title, titleColor: Color.dsPhosphorPale,
                           date: treatment.createdAt)
    }

    private func tooltipCard(title: String, titleColor: Color, date: Date) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.pixel(11))
                .foregroundStyle(titleColor)
            Text(date, format: .dateTime.hour().minute())
                .font(.system(size: 9))
                .foregroundStyle(Color.dsPhosphorDim)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.dsPhosphorBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.dsInRange.opacity(0.35), lineWidth: 1)
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Shared metrics

/// Layout constants shared by the canvas and the label overlay (points).
private enum ChartMetrics {
    static let cell: CGFloat = 8     // dot grid pitch
    static let dotR: CGFloat = 2.4   // dot radius (diameter/pitch = 0.6)
    static let leftW: CGFloat = 34   // y-axis labels
    static let bottomH: CGFloat = 30 // insulin lane + x-axis labels
    static let rightW: CGFloat = 26  // threshold labels
    static let topH: CGFloat = 16    // room for carb markers

    static func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: leftW, y: topH,
               width: max(size.width - leftW - rightW, 50),
               height: max(size.height - topH - bottomH, 50))
    }
}

// MARK: - Dot matrix canvas

/// The expensive layer: target band, thresholds, dot columns and treatment
/// markers. `Equatable` so pointer-driven parent updates skip the redraw.
private struct DotMatrixCanvas: View, Equatable {
    let entries: [GlucoseEntry] // oldest-first (chartEntries order)
    let treatments: [Treatment]
    let alertSettings: AlertSettings
    let plotSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            let plot = ChartMetrics.plotRect(in: size)
            let geom = ChartGeometry(entries: entries, alertSettings: alertSettings, plot: plot)
            let trace = Color.dsInRange

            // Target-range band.
            let bandTop = geom.yPos(of: alertSettings.highThreshold)
            let bandBottom = geom.yPos(of: alertSettings.lowThreshold)
            let band = CGRect(x: plot.minX, y: bandTop, width: plot.width, height: bandBottom - bandTop)
            ctx.fill(Path(band), with: .color(trace.opacity(0.06)))

            // Threshold rows: pixel-dotted lines.
            for threshold in [alertSettings.lowThreshold, alertSettings.highThreshold] {
                var line = Path()
                let yPos = geom.yPos(of: threshold)
                line.move(to: CGPoint(x: plot.minX, y: yPos))
                line.addLine(to: CGPoint(x: plot.maxX, y: yPos))
                ctx.stroke(line, with: .color(Color.dsPhosphorDim.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }

            // Dot matrix: one path per column (uniform opacity), bright tip
            // dot. Out-of-range readings turn semantic: dots poking above the
            // high line go yellow; a low reading paints its whole (short)
            // column red.
            let cell = ChartMetrics.cell
            let dotR = ChartMetrics.dotR
            let baseline = plot.maxY - cell / 2
            let highY = geom.yPos(of: alertSettings.highThreshold)
            for column in geom.columns(cell: cell) {
                let alpha = 0.35 + 0.65 * column.recency
                let isLow = column.sgv < alertSettings.lowThreshold
                let isHigh = column.sgv > alertSettings.highThreshold

                var greenBody = Path()
                var accentBody = Path()
                for row in 0..<max(column.dotCount - 1, 0) {
                    let cy = baseline - CGFloat(row) * cell
                    let rect = CGRect(x: column.x - dotR, y: cy - dotR,
                                      width: dotR * 2, height: dotR * 2)
                    if isLow || (isHigh && cy < highY) {
                        accentBody.addEllipse(in: rect)
                    } else {
                        greenBody.addEllipse(in: rect)
                    }
                }
                ctx.fill(greenBody, with: .color(trace.opacity(alpha)))
                if !accentBody.isEmpty {
                    let accent = isLow ? Color.dsLow : Color.dsHigh
                    ctx.fill(accentBody, with: .color(accent.opacity(alpha)))
                }

                // Silhouette tip: same size, brighter — phosphor in range,
                // semantic color out of range.
                let tipY = baseline - CGFloat(column.dotCount - 1) * cell
                let tip = CGRect(x: column.x - dotR, y: tipY - dotR,
                                 width: dotR * 2, height: dotR * 2)
                let tipColor: Color = isLow ? .dsLow : isHigh ? .dsHigh : .dsPhosphorBright
                ctx.fill(Path(ellipseIn: tip),
                         with: .color(tipColor.opacity(0.45 + 0.55 * column.recency)))
            }

            // Treatment markers: carbs = pale triangle floating above the
            // matrix, insulin = pale circle at the baseline.
            for marker in geom.treatmentMarkers(treatments) {
                switch marker.kind {
                case .carbs(let grams):
                    var tri = Path()
                    tri.move(to: CGPoint(x: marker.x, y: marker.y - 5))
                    tri.addLine(to: CGPoint(x: marker.x - 5, y: marker.y + 4))
                    tri.addLine(to: CGPoint(x: marker.x + 5, y: marker.y + 4))
                    tri.closeSubpath()
                    ctx.fill(tri, with: .color(Color.dsPhosphorPale))
                    let label = Text("\(grams)g").font(.pixel(11)).foregroundStyle(Color.dsPhosphorDim)
                    ctx.draw(ctx.resolve(label), at: CGPoint(x: marker.x, y: marker.y - 14), anchor: .center)
                case .insulin(let units):
                    // Dose-weighted: the bigger the bolus, the more opaque
                    // (and slightly larger) the dot. Floor of 0.4 keeps AID
                    // microboluses visible; the radius always beats the
                    // matrix dots (2.4) so markers never drown in the
                    // baseline row. Labels only from 1 U up.
                    let weight = min(units / 4.0, 1.0)
                    let r = 2.6 + CGFloat(min(units, 6.0) / 6.0) * 1.6
                    let rect = CGRect(x: marker.x - r, y: marker.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect),
                             with: .color(Color.dsPhosphorPale.opacity(0.4 + 0.6 * weight)))
                    if units >= 1.0 {
                        let label = Text("\(units as NSNumber, formatter: insulinFormatter)U")
                            .font(.pixel(11)).foregroundStyle(Color.dsPhosphorDim)
                        ctx.draw(ctx.resolve(label), at: CGPoint(x: marker.x + r + 3, y: marker.y),
                                 anchor: .leading)
                    }
                }
            }
        }
    }
}

private let insulinFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.maximumFractionDigits = 1
    f.minimumFractionDigits = 0
    return f
}()

/// Tooltip dose formatter: two decimals so microboluses read exactly (0.05U).
private let doseFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 0
    return f
}()

// MARK: - Geometry

/// Time/value ↔ point mapping for the current data + plot rect. Cheap to
/// build (a few O(n) scans); columns are derived on demand by the canvas.
private struct ChartGeometry {
    let entries: [GlucoseEntry] // oldest-first
    let plot: CGRect
    let start: Date
    let end: Date
    let loMgdl: Double
    let hiMgdl: Double

    init(entries: [GlucoseEntry], alertSettings: AlertSettings, plot: CGRect) {
        self.entries = entries
        self.plot = plot
        let now = Date()
        // Oldest-first order: bounds come straight from the ends.
        start = (entries.first?.date ?? now.addingTimeInterval(-3600)).addingTimeInterval(-120)
        end = (entries.last?.date ?? now).addingTimeInterval(120)
        var lo = alertSettings.lowThreshold
        var hi = alertSettings.highThreshold
        for entry in entries {
            lo = min(lo, entry.sgv)
            hi = max(hi, entry.sgv)
        }
        loMgdl = max(20, lo - 25)
        hiMgdl = hi + 25
    }

    var span: TimeInterval { max(end.timeIntervalSince(start), 1) }

    func xPos(of date: Date) -> CGFloat {
        plot.minX + plot.width * CGFloat(date.timeIntervalSince(start) / span)
    }

    func yPos(of mgdl: Double) -> CGFloat {
        let frac = (mgdl - loMgdl) / max(hiMgdl - loMgdl, 1)
        return plot.maxY - plot.height * CGFloat(frac)
    }

    struct Column {
        let x: CGFloat
        let dotCount: Int
        let recency: Double // 0 oldest → 1 newest
        let sgv: Double     // reading behind the column (range coloring)
    }

    /// One dot column per grid cell; value comes from the nearest reading.
    /// Cells with no reading within 10 min are skipped — honest gaps.
    /// Two-pointer over the time-sorted entries: O(entries + columns).
    func columns(cell: CGFloat) -> [Column] {
        guard !entries.isEmpty else { return [] }
        var result: [Column] = []
        let baseline = plot.maxY - cell / 2
        var i = 0
        var x = plot.minX + cell / 2
        while x < plot.maxX {
            let t = start.addingTimeInterval(TimeInterval((x - plot.minX) / plot.width) * span)
            while i + 1 < entries.count,
                  abs(entries[i + 1].date.timeIntervalSince(t)) <= abs(entries[i].date.timeIntervalSince(t)) {
                i += 1
            }
            let nearest = entries[i]
            if abs(nearest.date.timeIntervalSince(t)) <= 600 {
                let topY = yPos(of: nearest.sgv)
                let dotCount = max(1, Int((baseline - topY) / cell) + 1)
                result.append(Column(x: x, dotCount: dotCount,
                                     recency: Double((x - plot.minX) / plot.width),
                                     sgv: nearest.sgv))
            }
            x += cell
        }
        return result
    }

    func entry(atX x: CGFloat) -> GlucoseEntry? {
        guard x >= plot.minX, x <= plot.maxX, !entries.isEmpty else { return nil }
        let t = start.addingTimeInterval(TimeInterval((x - plot.minX) / plot.width) * span)
        return entries.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }
    }

    /// Closest insulin (or carb) treatment within 12 pt of `x`, if any.
    func nearestTreatment(in treatments: [Treatment], atX x: CGFloat, insulin: Bool) -> Treatment? {
        var best: (treatment: Treatment, distance: CGFloat)?
        for treatment in treatments {
            let amount = insulin ? (treatment.insulin ?? 0) : (treatment.carbs ?? 0)
            guard amount > 0, treatment.createdAt >= start, treatment.createdAt <= end else { continue }
            let distance = abs(xPos(of: treatment.createdAt) - x)
            if distance <= 12, distance < (best?.distance ?? .infinity) {
                best = (treatment, distance)
            }
        }
        return best?.treatment
    }

    /// Ticks on round hours, stepped so 3h/6h/12h/24h windows all get 3–6 labels.
    var xTicks: [Date] {
        let hours = span / 3600
        let stepHours: Double = hours <= 3.5 ? 1 : hours <= 7 ? 2 : hours <= 13 ? 3 : 6
        let step = stepHours * 3600
        var tick = Date(timeIntervalSince1970: ceil(start.timeIntervalSince1970 / step) * step)
        var ticks: [Date] = []
        while tick <= end {
            ticks.append(tick)
            tick = tick.addingTimeInterval(step)
        }
        return ticks
    }

    func yTicks(unit: GlucoseUnit) -> [Double] {
        let step: Double = unit == .mmolL ? 36 : 50 // 2 mmol/L in mg/dL
        var ticks: [Double] = []
        var v = ceil(loMgdl / step) * step
        while v <= hiMgdl {
            ticks.append(v)
            v += step
        }
        return ticks
    }

    enum MarkerKind { case carbs(Int), insulin(Double) }
    struct Marker { let x: CGFloat; let y: CGFloat; let kind: MarkerKind }

    func treatmentMarkers(_ treatments: [Treatment]) -> [Marker] {
        treatments.compactMap { treatment in
            guard treatment.createdAt >= start, treatment.createdAt <= end else { return nil }
            let x = xPos(of: treatment.createdAt)
            if let grams = treatment.carbs, grams > 0 {
                // Floats in the top margin above the dot matrix.
                return Marker(x: x, y: plot.minY + 8, kind: .carbs(Int(grams)))
            }
            if let units = treatment.insulin, units > 0 {
                // Sits in its own lane just below the plot, clearly separated
                // from the dot matrix.
                return Marker(x: x, y: plot.maxY + 7, kind: .insulin(units))
            }
            return nil
        }
    }
}
