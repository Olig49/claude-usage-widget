import AppKit
import UsageCore

/// Draws the menu bar image with every display option the Windows widget has: Rings or
/// Combined style per account, what goes inside and next to each ring, size, spacing,
/// account names and dividers. Colours resolve at draw time, so it follows a light or dark menu bar.
enum RingRenderer {
    static let height: CGFloat = 22

    struct Metrics {
        let ring: CGFloat, thick: CGFloat, innerThick: CGFloat
        let inFont: CGFloat, nextFont: CGFloat, smallFont: CGFloat, nameFont: CGFloat
        /// Large: the reset time goes on a second row under a caption or percentage.
        let twoRows: Bool
        let sideGap: CGFloat, ringGap: CGFloat
    }

    static func metrics(_ c: AppConfig) -> Metrics {
        let gaps: (CGFloat, CGFloat)
        switch c.spacingMode {
        case .tight: gaps = (6, 3)
        case .normal: gaps = (10, 5)
        case .wide: gaps = (16, 9)
        }
        switch c.sizeMode {
        case .compact:
            return Metrics(ring: 16, thick: 2.2, innerThick: 1.6, inFont: 6.8, nextFont: 10, smallFont: 8,
                           nameFont: 10, twoRows: false, sideGap: gaps.0, ringGap: gaps.1)
        case .normal:
            return Metrics(ring: 18, thick: 2.4, innerThick: 1.8, inFont: 7.4, nextFont: 11, smallFont: 8.5,
                           nameFont: 11, twoRows: false, sideGap: gaps.0, ringGap: gaps.1)
        case .large:
            return Metrics(ring: 20, thick: 2.6, innerThick: 2, inFont: 8, nextFont: 9.5, smallFont: 8,
                           nameFont: 11, twoRows: true, sideGap: gaps.0, ringGap: gaps.1)
        }
    }

    static func color(for pct: Double?) -> NSColor {
        guard let pct else { return .secondaryLabelColor }
        switch Severity(pct: pct) {
        case .ok: return .systemGreen
        case .warn: return .systemOrange
        case .high: return .systemRed
        }
    }

    // MARK: Layout pieces

    private enum DialState { case value, loading, problem }

    private struct TextLine {
        let text: String
        let font: NSFont
        let color: NSColor
        /// A small coloured dot before the text (combined dials): filled = middle limit, hollow = ring.
        var marker: (NSColor, Bool)?
    }

    private enum Piece {
        case gap(CGFloat)
        case divider
        case text([TextLine])
        case ring(pct: Double?, state: DialState, inside: String?, m: Metrics)
        case dial(outer: Double?, inner: Double?, innerAsRing: Bool, inside: String?, m: Metrics)

        func width() -> CGFloat {
            switch self {
            case .gap(let w): return w
            case .divider: return 1
            case .ring(_, _, _, let m), .dial(_, _, _, _, let m): return m.ring
            case .text(let lines):
                return lines.map { line in
                    textSize(line.text, line.font).width + (line.marker != nil ? 9 : 0)
                }.max() ?? 0
            }
        }
    }

    // MARK: Building

    static func image(config c: AppConfig, accounts: [AccountConfig], usage: [String: AccountUsage],
                      now: Date = Date()) -> NSImage {
        let m = metrics(c)
        let initials = c.initials()
        let names: NamesMode = c.namesMode ?? (accounts.count > 1 ? .left : .hidden)
        var pieces: [Piece] = []

        if accounts.isEmpty {
            pieces = [.ring(pct: nil, state: .loading, inside: nil, m: m)]
        }

        for (i, a) in accounts.enumerated() {
            if i > 0 {
                if c.showDividers == true {
                    pieces += [.gap(m.sideGap / 2), .divider, .gap(m.sideGap / 2)]
                } else {
                    pieces.append(.gap(m.sideGap))
                }
            }
            let nameLine = [TextLine(text: a.menuBarName, font: .systemFont(ofSize: m.nameFont, weight: .semibold),
                                     color: .labelColor)]
            if names == .left { pieces += [.text(nameLine), .gap(4)] }
            pieces += group(a, usage: usage[a.name], config: c, initials: initials[a.name] ?? "?", m: m, now: now)
            if names == .right { pieces += [.gap(4), .text(nameLine)] }
        }

        let width = ceil(max(pieces.reduce(0) { $0 + $1.width() }, m.ring))
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for p in pieces {
                draw(p, x: x)
                x += p.width()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// One account's rings (or dial) and the text beside them.
    private static func group(_ a: AccountConfig, usage u: AccountUsage?, config c: AppConfig, initials: String,
                              m: Metrics, now: Date) -> [Piece] {
        guard let u, u.hasData else {
            let state: DialState = (u == nil || u?.status == .loading) ? .loading : .problem
            return [.ring(pct: nil, state: state, inside: state == .problem ? "!" : nil, m: m)]
        }
        let inside = c.insideMode
        let next = c.nextMode

        if a.styleMode == .combined {
            let pieKey = c.pieKey(for: a)
            let ringKey: LimitKey = pieKey == .fiveHour ? .sevenDay : .fiveHour
            let pieW = u.window(pieKey, now: now), ringW = u.window(ringKey, now: now)
            // Same as Windows: with percentages a pie fills the middle; otherwise an inner ring,
            // with the initials in the centre when Inside is Initials.
            var pieces: [Piece] = [.dial(outer: ringW.pct, inner: pieW.pct, innerAsRing: inside != .percent,
                                         inside: inside == .initials ? initials : nil, m: m)]
            if next != .none || m.twoRows {
                let font = NSFont.monospacedDigitSystemFont(ofSize: min(m.nextFont, 9), weight: .bold)
                let lines = [LimitKey.fiveHour, .sevenDay].map { k -> TextLine in
                    let w = u.window(k, now: now)
                    var text = next == .none ? "" : nextText(next, window: w, caption: c.caption(k), now: now)
                    if m.twoRows && next != .resetin && next != .resetat {
                        let r = Format.resetIn(w.reset, now: now)
                        if !r.isEmpty { text += text.isEmpty ? r : " \u{00B7} \(r)" }
                    }
                    return TextLine(text: text, font: font, color: .labelColor, marker: (color(for: w.pct), k == pieKey))
                }
                pieces += [.gap(4), .text(lines)]
            }
            return pieces
        }

        var pieces: [Piece] = []
        let keys = a.limitKeys.filter { u.window($0, now: now).pct != nil }
        for (j, key) in keys.enumerated() {
            if j > 0 { pieces.append(.gap(m.ringGap)) }
            let w = u.window(key, now: now)
            let insideText: String?
            switch inside {
            case .none: insideText = nil
            case .initials: insideText = initials
            case .percent: insideText = w.pct.map { "\(Int($0.rounded()))" }
            }
            pieces.append(.ring(pct: w.pct, state: .value, inside: insideText, m: m))
            if next != .none {
                var lines = [TextLine(text: nextText(next, window: w, caption: c.caption(key), now: now),
                                      font: .systemFont(ofSize: m.nextFont, weight: next == .caption ? .semibold : .bold),
                                      color: next == .caption ? .secondaryLabelColor : .labelColor)]
                if m.twoRows && (next == .caption || next == .percent) {
                    let r = Format.resetIn(w.reset, now: now)
                    if !r.isEmpty {
                        lines.append(TextLine(text: r, font: .systemFont(ofSize: m.smallFont), color: .secondaryLabelColor))
                    }
                }
                pieces += [.gap(3), .text(lines)]
            }
        }
        if pieces.isEmpty { pieces = [.ring(pct: nil, state: .problem, inside: "!", m: m)] }
        return pieces
    }

    /// The text next to a ring in the given mode (Windows: Get-NextText).
    static func nextText(_ mode: NextMode, window w: UsageWindow, caption: String, now: Date) -> String {
        switch mode {
        case .none: return ""
        case .caption: return caption
        case .percent: return w.pct.map { Format.percent($0) } ?? "\u{2013}"
        case .resetin:
            let t = Format.resetIn(w.reset, now: now)
            return t.isEmpty ? "\u{2013}" : t
        case .resetat:
            let t = Format.resetAt(w.reset, now: now)
            return t.isEmpty ? "\u{2013}" : t
        }
    }

    // MARK: Drawing

    private static func draw(_ p: Piece, x: CGFloat) {
        switch p {
        case .gap:
            break
        case .divider:
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
            NSRect(x: x, y: 4, width: 1, height: height - 8).fill()
        case .text(let lines):
            let heights = lines.map { textSize($0.text, $0.font).height }
            var y = (height + heights.reduce(0, +)) / 2
            for (line, h) in zip(lines, heights) {
                y -= h
                var tx = x
                if let marker = line.marker {
                    let (c, filled) = marker
                    let dot = NSRect(x: x, y: y + (h - 6) / 2, width: 6, height: 6)
                    let path = NSBezierPath(ovalIn: filled ? dot : dot.insetBy(dx: 0.7, dy: 0.7))
                    if filled { c.setFill(); path.fill() } else { c.setStroke(); path.lineWidth = 1.4; path.stroke() }
                    tx += 9
                }
                (line.text as NSString).draw(at: NSPoint(x: tx, y: y),
                                             withAttributes: [.font: line.font, .foregroundColor: line.color])
            }
        case .ring(let pct, let state, let inside, let m):
            let rect = NSRect(x: x, y: (height - m.ring) / 2, width: m.ring, height: m.ring)
            drawTrack(rect, thick: m.thick)
            if state == .value { drawArc(rect, pct: pct, thick: m.thick) }
            let text = state == .loading ? "\u{00B7}" : inside
            if let text, !text.isEmpty {
                let isLetters = text.rangeOfCharacter(from: .letters) != nil && text != "!"
                var size = text.count >= 3 ? m.inFont - 1.2 : m.inFont
                if isLetters && text.count == 1 { size += 1.2 }
                let font = isLetters ? NSFont.systemFont(ofSize: size, weight: .bold)
                    : NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
                let color: NSColor = state == .value ? .labelColor : .secondaryLabelColor
                let s = textSize(text, font)
                (text as NSString).draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2),
                                        withAttributes: [.font: font, .foregroundColor: color])
            }
        case .dial(let outer, let inner, let innerAsRing, let inside, let m):
            let rect = NSRect(x: x, y: (height - m.ring) / 2, width: m.ring, height: m.ring)
            drawTrack(rect, thick: m.thick)
            drawArc(rect, pct: outer, thick: m.thick)
            // Middle limit: an inner ring when percentages are on, else a pie.
            let innerSize = m.ring - 2 * m.thick - 3
            let innerRect = NSRect(x: rect.midX - innerSize / 2, y: rect.midY - innerSize / 2,
                                   width: innerSize, height: innerSize)
            if innerAsRing {
                drawTrack(innerRect, thick: m.innerThick)
                drawArc(innerRect, pct: inner, thick: m.innerThick)
                if let inside, !inside.isEmpty {
                    let font = NSFont.systemFont(ofSize: max(5, m.inFont - 1.5), weight: .bold)
                    let s = textSize(inside, font)
                    (inside as NSString).draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2),
                                              withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
                }
            } else {
                NSColor.labelColor.withAlphaComponent(0.15).setFill()
                NSBezierPath(ovalIn: innerRect).fill()
                drawPie(innerRect, pct: inner)
            }
        }
    }

    private static func drawTrack(_ rect: NSRect, thick: CGFloat) {
        let track = NSBezierPath(ovalIn: rect.insetBy(dx: thick / 2, dy: thick / 2))
        track.lineWidth = thick
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        track.stroke()
    }

    /// Flat caps and an exact sweep: round caps stick out and make 91% look like 95%.
    private static func drawArc(_ rect: NSRect, pct: Double?, thick: CGFloat) {
        guard let pct, pct > 0 else { return }
        let circle = rect.insetBy(dx: thick / 2, dy: thick / 2)
        color(for: pct).setStroke()
        if pct >= 100 {
            // A 360-degree arc can collapse to nothing; draw the full circle instead.
            let full = NSBezierPath(ovalIn: circle)
            full.lineWidth = thick
            full.stroke()
            return
        }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: circle.midX, y: circle.midY), radius: circle.width / 2,
                      startAngle: 90, endAngle: 90 - 360 * CGFloat(pct) / 100, clockwise: true)
        arc.lineWidth = thick
        arc.lineCapStyle = .butt
        arc.stroke()
    }

    private static func drawPie(_ rect: NSRect, pct: Double?) {
        guard let pct, pct > 0 else { return }
        color(for: pct).setFill()
        if pct >= 100 {
            NSBezierPath(ovalIn: rect).fill()
            return
        }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let pie = NSBezierPath()
        pie.move(to: center)
        pie.line(to: NSPoint(x: center.x, y: rect.maxY))
        pie.appendArc(withCenter: center, radius: rect.width / 2, startAngle: 90,
                      endAngle: 90 - 360 * CGFloat(pct) / 100, clockwise: true)
        pie.close()
        pie.fill()
    }

    private static func textSize(_ s: String, _ font: NSFont) -> NSSize {
        (s as NSString).size(withAttributes: [.font: font])
    }

    // MARK: Tooltip

    /// Hover text for the menu bar item: each shown account, its limits and resets.
    static func tooltip(config c: AppConfig, accounts: [AccountConfig], usage: [String: AccountUsage],
                        now: Date = Date()) -> String {
        if accounts.isEmpty { return "Claude usage: no accounts yet. Click to set one up." }
        return accounts.map { a in
            var lines = [a.displayName]
            if let u = usage[a.name] {
                if u.status.isProblem, let e = u.error {
                    lines.append("  \(e)")
                } else {
                    for key in LimitKey.allCases {
                        let w = u.window(key, now: now)
                        guard let pct = w.pct else { continue }
                        var line = "  \(c.caption(key)): \(Format.percent(pct))"
                        let r = Format.resetIn(w.reset, now: now)
                        if !r.isEmpty { line += ", resets \(r)" }
                        lines.append(line)
                    }
                    if a.styleMode == .combined {
                        lines.append("  Middle: \(c.caption(c.pieKey(for: a))), ring: the other window")
                    }
                }
            } else {
                lines.append("  Loading\u{2026}")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }
}
