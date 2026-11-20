import SwiftUI
import AppKit

/// Pip, the mascot. Drawn in code on a 120 × 150 grid so it stays crisp at any size.
struct PipView: View {
    enum Pose { case idle, stretch, cheer, sleepy }

    var pose: Pose = .idle
    var color: Color = AccentChoice.tangerine.color
    /// Gentle up-and-down bob.
    var bob = false

    @State private var up = false

    var body: some View {
        Canvas { context, size in
            PipPainter(pose: pose, color: color).draw(in: context, size: size)
        }
        .aspectRatio(120.0 / 150.0, contentMode: .fit)
        .offset(y: bob && up ? -5 : 0)
        .onAppear {
            guard bob else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                up = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct PipPainter {
    let pose: PipView.Pose
    let color: Color
    var ink: Color = Theme.ink

    func draw(in ctx: GraphicsContext, size: CGSize) {
        let s = min(size.width / 120, size.height / 150)
        let ox = (size.width - 120 * s) / 2
        let oy = (size.height - 150 * s) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        func stroke(_ path: Path, _ c: Color, _ width: CGFloat) {
            ctx.stroke(path, with: .color(c),
                       style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
        }

        func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat = 7) {
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            stroke(path, ink, width)
        }

        func ellipse(_ c: CGPoint, rx: CGFloat, ry: CGFloat, fill: Color, strokeWidth: CGFloat = 0) {
            let rect = CGRect(x: c.x - rx * s, y: c.y - ry * s, width: rx * 2 * s, height: ry * 2 * s)
            let path = Path(ellipseIn: rect)
            ctx.fill(path, with: .color(fill))
            if strokeWidth > 0 { stroke(path, ink, strokeWidth) }
        }

        func curve(_ a: CGPoint, control: CGPoint, _ b: CGPoint, color c: Color, width: CGFloat = 4) {
            var path = Path()
            path.move(to: a)
            path.addQuadCurve(to: b, control: control)
            stroke(path, c, width)
        }

        func sparkle(_ c: CGPoint, size k0: CGFloat, fill: Color) {
            let k = k0 * s
            let q = k0 * 0.3 * s
            var path = Path()
            path.move(to: CGPoint(x: c.x, y: c.y - k))
            path.addLine(to: CGPoint(x: c.x + q, y: c.y - q))
            path.addLine(to: CGPoint(x: c.x + k, y: c.y))
            path.addLine(to: CGPoint(x: c.x + q, y: c.y + q))
            path.addLine(to: CGPoint(x: c.x, y: c.y + k))
            path.addLine(to: CGPoint(x: c.x - q, y: c.y + q))
            path.addLine(to: CGPoint(x: c.x - k, y: c.y))
            path.addLine(to: CGPoint(x: c.x - q, y: c.y - q))
            path.closeSubpath()
            ctx.fill(path, with: .color(fill))
            stroke(path, ink, 3)
        }

        let cheer = pose == .cheer
        let dy: CGFloat = cheer ? -6 : 0

        // Sparkles behind everything when cheering.
        if cheer {
            sparkle(p(18, 22), size: 10, fill: Theme.sun)
            sparkle(p(104, 40), size: 7, fill: Theme.paper)
        }

        // Arms (behind the body).
        switch pose {
        case .stretch:
            line(p(40, 70), p(24, 28))
            line(p(80, 70), p(96, 28))
        case .cheer:
            line(p(40, 64), p(28, 44))
            line(p(80, 64), p(92, 44))
        case .idle, .sleepy:
            line(p(34, 92), p(20, 104))
            line(p(86, 92), p(100, 104))
        }

        // Legs and feet.
        if cheer {
            line(p(50, 122), p(44, 132))
            line(p(70, 122), p(76, 132))
            ellipse(p(41, 135), rx: 9, ry: 5, fill: ink)
            ellipse(p(79, 135), rx: 9, ry: 5, fill: ink)
        } else {
            line(p(50, 128), p(48, 140))
            line(p(70, 128), p(72, 140))
            ellipse(p(45, 143), rx: 9, ry: 5, fill: ink)
            ellipse(p(75, 143), rx: 9, ry: 5, fill: ink)
        }

        // Body.
        let bodyRect = CGRect(x: ox + 28 * s, y: oy + (50 + dy) * s, width: 64 * s, height: 84 * s)
        let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 32 * s, style: .continuous)
        ctx.fill(bodyPath, with: .color(color))
        stroke(bodyPath, ink, 5)

        // Hands (in front, at the ends of raised arms).
        switch pose {
        case .stretch:
            ellipse(p(23, 24), rx: 8, ry: 8, fill: Theme.sun, strokeWidth: 4)
            ellipse(p(97, 24), rx: 8, ry: 8, fill: Theme.sun, strokeWidth: 4)
        case .cheer:
            ellipse(p(27, 41), rx: 8, ry: 8, fill: Theme.sun, strokeWidth: 4)
            ellipse(p(93, 41), rx: 8, ry: 8, fill: Theme.sun, strokeWidth: 4)
        case .idle, .sleepy:
            break
        }

        // Shine and cheeks.
        curve(p(40, 68 + dy), control: p(42, 60 + dy), p(50, 57 + dy), color: .white)
        ellipse(p(42, 94 + dy), rx: 4, ry: 4, fill: Theme.cheek)
        ellipse(p(78, 94 + dy), rx: 4, ry: 4, fill: Theme.cheek)

        // Face.
        switch pose {
        case .idle:
            ellipse(p(50, 82), rx: 4.5, ry: 4.5, fill: ink)
            ellipse(p(70, 82), rx: 4.5, ry: 4.5, fill: ink)
            curve(p(52, 96), control: p(60, 104), p(68, 96), color: ink)
        case .stretch:
            curve(p(45, 82), control: p(50, 78), p(55, 82), color: ink)
            curve(p(65, 82), control: p(70, 78), p(75, 82), color: ink)
            ellipse(p(60, 100), rx: 7, ry: 8, fill: ink)
        case .cheer:
            ellipse(p(50, 76), rx: 4.5, ry: 4.5, fill: ink)
            ellipse(p(70, 76), rx: 4.5, ry: 4.5, fill: ink)
            var mouth = Path()
            mouth.move(to: p(48, 88))
            mouth.addQuadCurve(to: p(72, 88), control: p(60, 104))
            mouth.closeSubpath()
            ctx.fill(mouth, with: .color(ink))
            stroke(mouth, ink, 3)
        case .sleepy:
            line(p(45, 83), p(55, 83), width: 4)
            line(p(65, 83), p(75, 83), width: 4)
            ellipse(p(60, 99), rx: 3, ry: 3, fill: ink)
        }
    }
}

/// Template images for the menu bar (they adapt to light/dark menu bars automatically).
enum PipIcon {
    static func menuBar(armsUp: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 2.5, width: 10, height: 13),
                                    xRadius: 5, yRadius: 5)
            body.append(NSBezierPath(ovalIn: NSRect(x: 6.1, y: 6.6, width: 2.2, height: 2.2)))
            body.append(NSBezierPath(ovalIn: NSRect(x: 9.7, y: 6.6, width: 2.2, height: 2.2)))
            body.windingRule = .evenOdd
            body.fill()

            if armsUp {
                let arms = NSBezierPath()
                arms.lineWidth = 1.6
                arms.lineCapStyle = .round
                arms.move(to: NSPoint(x: 5, y: 7))
                arms.line(to: NSPoint(x: 1.2, y: 1.2))
                arms.move(to: NSPoint(x: 13, y: 7))
                arms.line(to: NSPoint(x: 16.8, y: 1.2))
                arms.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }
}
