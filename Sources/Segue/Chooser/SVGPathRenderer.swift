import AppKit

/// Turns an SVG `d` path string (the subset Simple Icons uses: M m L l H h
/// V v C c S s Q q T t A a Z z, absolute and relative) into a CGPath.
/// Arcs are approximated with Béziers. Enough for 24×24 logo marks.
enum SVGPathRenderer {
    static func path(from d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens = tokenize(d)
        var i = 0
        var cmd: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint? = nil
        var lastCmd: Character = "M"

        func num() -> CGFloat? {
            guard i < tokens.count, case .number(let v) = tokens[i] else { return nil }
            i += 1
            return v
        }

        while i < tokens.count {
            if case .command(let c) = tokens[i] { cmd = c; i += 1 }
            else if cmd == "M" { cmd = "L" } else if cmd == "m" { cmd = "l" }
            let rel = cmd.isLowercase
            let base = rel ? current : .zero
            switch cmd.uppercased().first! {
            case "M":
                guard let x = num(), let y = num() else { i = tokens.count; break }
                current = CGPoint(x: base.x + x, y: base.y + y)
                start = current
                path.move(to: current)
                lastControl = nil
            case "L":
                guard let x = num(), let y = num() else { i = tokens.count; break }
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addLine(to: current)
                lastControl = nil
            case "H":
                guard let x = num() else { i = tokens.count; break }
                current = CGPoint(x: (rel ? current.x : 0) + x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = num() else { i = tokens.count; break }
                current = CGPoint(x: current.x, y: (rel ? current.y : 0) + y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let x1 = num(), let y1 = num(), let x2 = num(), let y2 = num(), let x = num(), let y = num() else { i = tokens.count; break }
                let c1 = CGPoint(x: base.x + x1, y: base.y + y1)
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case "S":
                guard let x2 = num(), let y2 = num(), let x = num(), let y = num() else { i = tokens.count; break }
                let c1: CGPoint = ("CcSs".contains(lastCmd) && lastControl != nil)
                    ? CGPoint(x: 2 * current.x - lastControl!.x, y: 2 * current.y - lastControl!.y) : current
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case "Q":
                guard let x1 = num(), let y1 = num(), let x = num(), let y = num() else { i = tokens.count; break }
                let c = CGPoint(x: base.x + x1, y: base.y + y1)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: current, control: c)
                lastControl = c
            case "T":
                guard let x = num(), let y = num() else { i = tokens.count; break }
                let c: CGPoint = ("QqTt".contains(lastCmd) && lastControl != nil)
                    ? CGPoint(x: 2 * current.x - lastControl!.x, y: 2 * current.y - lastControl!.y) : current
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: current, control: c)
                lastControl = c
            case "A":
                guard let rx = num(), let ry = num(), let rot = num(), let large = num(), let sweep = num(), let x = num(), let y = num() else { i = tokens.count; break }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotation: rot, largeArc: large != 0, sweep: sweep != 0)
                current = end
                lastControl = nil
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                i = tokens.count
            }
            lastCmd = cmd
        }
        tokens.removeAll()
        return path
    }

    /// Renders the mark as white on a rounded square of the brand colour.
    static func image(pathData: String, hex: String, size: CGFloat, viewBox: CGFloat = 24) -> NSImage {
        let cg = path(from: pathData)
        let color = Design.color(hex: "#" + hex) ?? .systemBlue
        return NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.saveGState()
            let inset = size * 0.2
            let scale = (size - 2 * inset) / viewBox
            ctx.translateBy(x: inset, y: inset)
            ctx.scaleBy(x: scale, y: scale)
            ctx.addPath(cg)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
            return true
        }
    }

    // MARK: - Tokenizer

    enum Token { case command(Character); case number(CGFloat) }

    static func tokenize(_ d: String) -> [Token] {
        var out: [Token] = []
        var num = ""
        func flush() {
            if !num.isEmpty, let v = Double(num) { out.append(.number(CGFloat(v))) }
            num = ""
        }
        var prevWasExponent = false
        for ch in d {
            if ch.isLetter && !(ch == "e" || ch == "E") {
                flush(); out.append(.command(ch)); prevWasExponent = false
            } else if ch == "-" && !num.isEmpty && !prevWasExponent {
                flush(); num = "-"
            } else if ch == "." && num.contains(".") && !prevWasExponent {
                flush(); num = "."
            } else if ch == "," || ch.isWhitespace {
                flush(); prevWasExponent = false
            } else {
                num.append(ch)
                prevWasExponent = (ch == "e" || ch == "E")
            }
        }
        flush()
        return out
    }

    // MARK: - Arcs (SVG implementation notes, F.6.5)

    static func addArc(to path: CGMutablePath, from p1: CGPoint, to p2: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                       rotation: CGFloat, largeArc: Bool, sweep: Bool) {
        if p1 == p2 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: p2); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (p1.x - p2.x) / 2, dy2 = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        var t = theta1
        for _ in 0..<segments {
            let t2 = t + step
            let alpha = 4 / 3 * tan((t2 - t) / 4)
            func point(_ a: CGFloat) -> CGPoint {
                let x = rx * cos(a), y = ry * sin(a)
                return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
            }
            func deriv(_ a: CGFloat) -> CGPoint {
                let x = -rx * sin(a), y = ry * cos(a)
                return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
            }
            let pStart = point(t), pEnd = point(t2)
            let d1 = deriv(t), d2 = deriv(t2)
            let c1 = CGPoint(x: pStart.x + alpha * d1.x, y: pStart.y + alpha * d1.y)
            let c2 = CGPoint(x: pEnd.x - alpha * d2.x, y: pEnd.y - alpha * d2.y)
            path.addCurve(to: pEnd, control1: c1, control2: c2)
            t = t2
        }
    }
}
