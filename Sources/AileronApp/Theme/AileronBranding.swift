import SwiftUI

public struct AileronLogo: View {
    public let size: CGFloat
    public let framed: Bool
    @Environment(\.aileronTheme) private var theme

    public init(size: CGFloat = 24, framed: Bool = false) {
        self.size = size
        self.framed = framed
    }

    public var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let sx = w / 100.0
            let sy = h / 100.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * sx, y: y * sy)
            }

            let inkBlack = Color(hex: 0x121417)
            let slateBlue = Color(hex: 0x263B63)
            let skyBlue = Color(hex: 0x72B2D4)
            let creamPaper = Color(hex: 0xF2EAD9)
            let vermilion = Color(hex: 0xCF4636)
            let warmOchre = Color(hex: 0xD9A74A)

            if framed {
                var steppedOuter = Path()
                let s1: CGFloat = 10
                let s2: CGFloat = 18
                steppedOuter.move(to: pt(s2, 2))
                steppedOuter.addLine(to: pt(100 - s2, 2))
                steppedOuter.addLine(to: pt(100 - s2, s1))
                steppedOuter.addLine(to: pt(100 - s1, s1))
                steppedOuter.addLine(to: pt(100 - s1, s2))
                steppedOuter.addLine(to: pt(98, s2))
                steppedOuter.addLine(to: pt(98, 100 - s2))
                steppedOuter.addLine(to: pt(100 - s1, 100 - s2))
                steppedOuter.addLine(to: pt(100 - s1, 100 - s1))
                steppedOuter.addLine(to: pt(100 - s2, 100 - s1))
                steppedOuter.addLine(to: pt(100 - s2, 98))
                steppedOuter.addLine(to: pt(s2, 98))
                steppedOuter.addLine(to: pt(s2, 100 - s1))
                steppedOuter.addLine(to: pt(s1, 100 - s1))
                steppedOuter.addLine(to: pt(s1, 100 - s2))
                steppedOuter.addLine(to: pt(2, 100 - s2))
                steppedOuter.addLine(to: pt(2, s2))
                steppedOuter.addLine(to: pt(s1, s2))
                steppedOuter.addLine(to: pt(s1, s1))
                steppedOuter.addLine(to: pt(s2, s1))
                steppedOuter.closeSubpath()

                ctx.drawLayer { layer in
                    layer.clip(to: steppedOuter)
                    layer.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(inkBlack))

                    var diagPlane = Path()
                    diagPlane.move(to: pt(0, 0))
                    diagPlane.addLine(to: pt(64, 0))
                    diagPlane.addLine(to: pt(34, 100))
                    diagPlane.addLine(to: pt(0, 100))
                    diagPlane.closeSubpath()
                    layer.fill(diagPlane, with: .color(slateBlue))

                    var creamBand = Path()
                    creamBand.move(to: pt(76, 0))
                    creamBand.addLine(to: pt(100, 0))
                    creamBand.addLine(to: pt(100, 100))
                    creamBand.addLine(to: pt(68, 100))
                    creamBand.closeSubpath()
                    layer.fill(creamBand, with: .color(creamPaper.opacity(0.10)))

                    for stripeX in [79.0, 83.0, 87.0] {
                        var stripe = Path()
                        stripe.move(to: pt(stripeX, 0))
                        stripe.addLine(to: pt(stripeX + 1.4, 0))
                        stripe.addLine(to: pt(stripeX - 5.6, 100))
                        stripe.addLine(to: pt(stripeX - 7.0, 100))
                        stripe.closeSubpath()
                        layer.fill(stripe, with: .color(vermilion.opacity(0.55)))
                    }
                }

                ctx.stroke(steppedOuter, with: .color(creamPaper), lineWidth: max(1.0, 2.0 * sx))
            }

            let pad: CGFloat = framed ? 0.66 : 0.92
            let offset: CGFloat = (100.0 - 100.0 * pad) / 2.0
            func ept(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                pt(offset + x * pad, offset + y * pad)
            }

            for i in 0..<3 {
                let y = 55.0 + CGFloat(i) * 8.0
                let leftOuter = 4.0 + CGFloat(i) * 5.0
                let rightOuter = 96.0 - CGFloat(i) * 5.0
                let barH: CGFloat = 4.4

                var lBar = Path()
                lBar.move(to: ept(leftOuter, y))
                lBar.addLine(to: ept(34, y))
                lBar.addLine(to: ept(32, y + barH))
                lBar.addLine(to: ept(leftOuter + 3.2, y + barH))
                lBar.closeSubpath()
                ctx.fill(lBar, with: .color(i == 0 ? skyBlue : (i == 1 ? creamPaper : warmOchre)))

                var rBar = Path()
                rBar.move(to: ept(66, y))
                rBar.addLine(to: ept(rightOuter, y))
                rBar.addLine(to: ept(rightOuter - 3.2, y + barH))
                rBar.addLine(to: ept(68, y + barH))
                rBar.closeSubpath()
                ctx.fill(rBar, with: .color(i == 0 ? vermilion : (i == 1 ? creamPaper : warmOchre)))
            }

            var crossbar = Path()
            crossbar.move(to: ept(29, 71))
            crossbar.addLine(to: ept(71, 71))
            crossbar.addLine(to: ept(71, 77.5))
            crossbar.addLine(to: ept(29, 77.5))
            crossbar.closeSubpath()
            ctx.fill(crossbar, with: .color(warmOchre))

            var leftLeg = Path()
            leftLeg.move(to: ept(50, 7))
            leftLeg.addLine(to: ept(17, 89))
            leftLeg.addLine(to: ept(33.5, 89))
            leftLeg.addLine(to: ept(50, 44))
            leftLeg.closeSubpath()
            ctx.fill(leftLeg, with: .color(creamPaper))

            var rightLeg = Path()
            rightLeg.move(to: ept(50, 7))
            rightLeg.addLine(to: ept(83, 89))
            rightLeg.addLine(to: ept(66.5, 89))
            rightLeg.addLine(to: ept(50, 44))
            rightLeg.closeSubpath()
            ctx.fill(rightLeg, with: .color(vermilion))

            var inlineCutLeft = Path()
            inlineCutLeft.move(to: ept(48.5, 21))
            inlineCutLeft.addLine(to: ept(23.5, 84))
            inlineCutLeft.addLine(to: ept(26.2, 84))
            inlineCutLeft.addLine(to: ept(48.5, 28))
            inlineCutLeft.closeSubpath()
            ctx.fill(inlineCutLeft, with: .color(inkBlack))

            var counterDiamond = Path()
            counterDiamond.move(to: ept(50, 52))
            counterDiamond.addLine(to: ept(56.5, 62))
            counterDiamond.addLine(to: ept(50, 68.5))
            counterDiamond.addLine(to: ept(43.5, 62))
            counterDiamond.closeSubpath()
            ctx.fill(counterDiamond, with: .color(skyBlue))

            var baseRule = Path()
            baseRule.addRect(CGRect(
                x: ept(17, 92.5).x,
                y: ept(17, 92.5).y,
                width: 66 * pad * sx,
                height: 3.6 * pad * sy
            ))
            ctx.fill(baseRule, with: .color(creamPaper))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Aileron")
    }
}

public struct AileronWordmark: View {
    public let height: CGFloat
    public let color: Color?
    @Environment(\.aileronTheme) private var theme

    public init(height: CGFloat = 15, color: Color? = nil) {
        self.height = height
        self.color = color
    }

    public var body: some View {
        let ink = color ?? theme.textPrimary
        let width = height * 6.8
        Canvas { ctx, size in
            let s = size.height / 24.0
            let sw = max(1.3, 2.3 * s)
            let style = StrokeStyle(lineWidth: sw, lineCap: .square, lineJoin: .miter)

            func strokePath(_ build: (inout Path) -> Void) {
                var p = Path()
                build(&p)
                ctx.stroke(p, with: .color(ink), style: style)
            }

            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * s, y: y * s)
            }

            strokePath { p in
                p.move(to: pt(2, 22))
                p.addLine(to: pt(10, 2))
                p.addLine(to: pt(18, 22))
                p.move(to: pt(4.5, 16.5))
                p.addLine(to: pt(15.5, 16.5))
            }

            strokePath { p in
                p.move(to: pt(27, 2))
                p.addLine(to: pt(27, 22))
            }

            strokePath { p in
                p.move(to: pt(36, 2))
                p.addLine(to: pt(36, 22))
                p.addLine(to: pt(49, 22))
            }

            strokePath { p in
                p.move(to: pt(70, 2))
                p.addLine(to: pt(57, 2))
                p.addLine(to: pt(57, 22))
                p.addLine(to: pt(70, 22))
                p.move(to: pt(57, 10))
                p.addLine(to: pt(67, 10))
            }

            strokePath { p in
                p.move(to: pt(79, 22))
                p.addLine(to: pt(79, 2))
                p.addLine(to: pt(88, 2))
                p.addArc(
                    center: pt(88, 7.5),
                    radius: 5.5 * s,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(90),
                    clockwise: false
                )
                p.addLine(to: pt(79, 13))
                p.move(to: pt(87, 13))
                p.addLine(to: pt(94, 22))
            }

            strokePath { p in
                p.addEllipse(in: CGRect(x: 103 * s, y: 2 * s, width: 20 * s, height: 20 * s))
            }

            strokePath { p in
                p.move(to: pt(132, 22))
                p.addLine(to: pt(132, 2))
                p.addLine(to: pt(148, 22))
                p.addLine(to: pt(148, 2))
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("Aileron")
    }
}
