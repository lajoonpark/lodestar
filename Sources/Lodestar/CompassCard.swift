import AppKit
import Foundation
import RadialCore

/// What is printed on the card, and the things that sit proud of it.
///
/// Split out from the case because it is a different material with different rules: paper is
/// flat and its ink follows the depth scale, while a slice's wash has to stay behind the ink
/// it is lighting up.
extension CompassRenderer {

    // MARK: - Printing

    func drawCardPrinting(in context: CGContext, state: State, metrics: CompassMetrics) {
        let z = metrics.cardDepth
        let alpha = CGFloat(state.contentAlpha)
        let layout = layout(for: state)

        drawGuilloche(in: context, state: state, metrics: metrics, alpha: alpha)
        drawScale(in: context, state: state, metrics: metrics, alpha: alpha)
        drawSectorRules(in: context, state: state, metrics: metrics, alpha: alpha)
        if state.showsNumbers {
            drawNumerals(in: context, state: state, metrics: metrics, layout: layout)
        }

        // Quadrant pips, in the gaps between the numerals.
        for degrees in [45.0, 135.0, 225.0, 315.0] {
            let angle = CGFloat(degrees) * .pi / 180
            let anchor = state.camera.project(
                x: metrics.numeralRadius * sin(angle),
                y: -metrics.numeralRadius * cos(angle),
                z: z
            )
            drawText(
                "·",
                at: anchor,
                scale: inkScale(at: Point3D(radius: metrics.numeralRadius, angle: angle), state),
                font: CompassTheme.serif(max(7, metrics.cardRadius * 0.050)),
                colour: CompassTheme.inkRule.withAlphaComponent(0.50 * alpha),
                in: context
            )
        }
    }

    /// Fine concentric circles in the margin between the sectors and the scale — the engraved
    /// band that stops the card reading as a blank disc with wedges printed on it.
    private func drawGuilloche(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        for index in 0..<8 {
            let radius = metrics.sectorOutset + metrics.cardRadius * (0.005 + CGFloat(index) * 0.0075)
            let ring = (0...120).map { step -> CGPoint in
                let angle = CGFloat(step) / 120 * 2 * .pi
                return state.camera.project(x: radius * sin(angle), y: -radius * cos(angle), z: metrics.cardDepth)
            }
            stroke(ring, context,
                   CompassTheme.inkRule.withAlphaComponent((0.16 - CGFloat(index) * 0.012) * alpha),
                   width: 0.7)
        }
    }

    /// The printed degree scale, interrupted at each slot's bearing.
    ///
    /// The interruptions are not decoration: they are the gate each slot numeral sits in, and
    /// they are what let the numerals live on cream paper (9.3:1) instead of on brass (4.3:1).
    /// These digits are the keyboard shortcut, so they are the least affordable thing on the
    /// dial to misread.
    private func drawScale(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        let z = metrics.cardDepth
        let sliceCount = max(1, state.slices.count)
        let stepDegrees = 360.0 / Double(sliceCount)

        for degrees in stride(from: 0, to: 360, by: CompassTheme.scaleStepDegrees) {
            let bearing = Double(degrees)
            var inGate = false
            for index in 0..<sliceCount {
                let centre = Double(index) * stepDegrees
                var delta = abs(bearing - centre).truncatingRemainder(dividingBy: 360)
                delta = min(delta, 360 - delta)
                if delta < stepDegrees * Double(CompassTheme.numeralGateHalf) {
                    inGate = true
                    break
                }
            }
            if inGate { continue }

            let angle = CGFloat(degrees) * .pi / 180
            let major = degrees % 15 == 0
            let inner = metrics.scaleInset + metrics.cardRadius * (major ? 0.008 : 0.032)
            let outer = metrics.scaleOutset
            let from = state.camera.project(x: inner * sin(angle), y: -inner * cos(angle), z: z)
            let to = state.camera.project(x: outer * sin(angle), y: -outer * cos(angle), z: z)
            line(from, to, context,
                 CompassTheme.inkRule.withAlphaComponent((major ? 0.55 : 0.26) * alpha),
                 width: major ? 1.05 : 0.7)
        }
    }

    /// The walls between slices: a dark hairline with a lit companion, so they read as cut
    /// into the paper rather than drawn over it.
    private func drawSectorRules(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        let z = metrics.cardDepth
        let count = max(1, state.slices.count)
        let step = 2 * CGFloat.pi / CGFloat(count)
        for index in 0..<count {
            let angle = CGFloat(index) * step - step / 2
            let innerY = -(metrics.hubRadius + metrics.cardRadius * 0.02) * cos(angle)
            for (offset, colour, width) in [
                (CGFloat(1.7), NSColor.white.withAlphaComponent(0.40 * alpha), CGFloat(1.25)),
                (CGFloat(0), CompassTheme.inkRule.withAlphaComponent(0.42 * alpha), CGFloat(1.1)),
            ] {
                let from = state.camera.project(
                    x: (metrics.hubRadius + metrics.cardRadius * 0.02) * sin(angle),
                    y: innerY + offset,
                    z: z
                )
                let to = state.camera.project(
                    x: metrics.sectorOutset * sin(angle),
                    y: -metrics.sectorOutset * cos(angle) + offset,
                    z: z
                )
                line(from, to, context, colour, width: width)
            }
        }
    }

    /// The slot numerals, in their gates. The loudest ink on the card, because they are what
    /// the keyboard drives.
    private func drawNumerals(
        in context: CGContext,
        state: State,
        metrics: CompassMetrics,
        layout: RadialLayout
    ) {
        for index in 0..<max(1, state.slices.count) {
            let angle = layout.centerAngle(of: index)
            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0
            let point = Point3D(radius: metrics.numeralRadius, angle: angle)
            let anchor = state.camera.project(x: point.x, y: point.y, z: metrics.cardDepth)
            drawText(
                RadialLayout.keyLabel(forSlice: index),
                at: anchor,
                scale: inkScale(at: point, state),
                font: CompassTheme.serif(metrics.numeralFontSize, .semibold),
                colour: hover > 0.3
                    ? CompassTheme.vermilion.withAlphaComponent(0.55 + 0.45 * Double(hover))
                    : CompassTheme.ink.withAlphaComponent(0.94),
                in: context
            )
        }
    }

    // MARK: - Slices

    /// The aimed wedge's wash. Warm light on paper rather than a lit surface: the card is the
    /// material, so hovering has to read as a highlight washing over print.
    func drawSliceWash(in context: CGContext, state: State, metrics: CompassMetrics) {
        let layout = layout(for: state)
        let alpha = CGFloat(state.contentAlpha)
        for index in 0..<max(1, state.slices.count) {
            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0
            guard hover > 0.008 else { continue }
            let path = wedge(
                index: index,
                inset: layout.step * 0.045,
                inner: metrics.sectorInset,
                outer: metrics.sectorOutset,
                layout: layout,
                state
            )
            context.saveGState()
            context.addPath(path)
            context.clip()
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor(calibratedRed: 0.808, green: 0.647, blue: 0.365, alpha: 1)
                        .withAlphaComponent(0.30 * hover * alpha).cgColor,
                    NSColor(calibratedRed: 0.847, green: 0.706, blue: 0.424, alpha: 1)
                        .withAlphaComponent(0.24 * hover * alpha).cgColor,
                    NSColor(calibratedRed: 0.902, green: 0.784, blue: 0.549, alpha: 1)
                        .withAlphaComponent(0.10 * hover * alpha).cgColor,
                ] as CFArray,
                locations: [0, 0.62, 1]
            ) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: .zero,
                    startRadius: metrics.sectorInset,
                    endCenter: .zero,
                    endRadius: metrics.sectorOutset,
                    options: []
                )
            }
            context.restoreGState()

            // A vermilion rule along the aimed wedge's rim, so the aim has a crisp edge as well
            // as a wash — the wash alone is ambiguous on a bright wallpaper.
            if hover > 0.25 {
                let drawn = layout.drawableRange(of: index, inset: layout.step * 0.045)
                let arc = (0...24).map { step -> CGPoint in
                    let angle = drawn.start + drawn.sweep * CGFloat(step) / 24
                    return state.camera.project(
                        x: metrics.sectorOutset * sin(angle),
                        y: -metrics.sectorOutset * cos(angle),
                        z: metrics.cardDepth
                    )
                }
                stroke(arc, context,
                       CompassTheme.vermilion.withAlphaComponent(0.70 * Double(hover) * alpha),
                       width: 1.6)
            }
        }
    }

    // MARK: - The needle

    func drawNeedle(in context: CGContext, state: State, metrics: CompassMetrics) {
        let angle = state.needleAngle
        let z = metrics.cardDepth + metrics.cardRadius * 0.004
        let tip = metrics.cardRadius * 0.78
        let tail = metrics.cardRadius * 0.62
        let halfWidth = metrics.cardRadius * 0.026

        func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            state.camera.project(
                x: along * sin(angle) - across * cos(angle),
                y: -along * cos(angle) - across * sin(angle),
                z: z
            )
        }

        let tipPoint = at(tip, 0)
        let leftPoint = at(0, -halfWidth)
        let backPoint = at(-tail, 0)
        let rightPoint = at(0, halfWidth)

        // A shadow a hair off, so the needle sits above the printing rather than in it.
        context.saveGState()
        context.translateBy(x: 1.1, y: 1.5)
        fill([tipPoint, leftPoint, backPoint, rightPoint], context,
             NSColor.black.withAlphaComponent(0.30))
        context.restoreGState()

        let path = CGMutablePath()
        path.addLines(between: [tipPoint, leftPoint, backPoint, rightPoint])
        path.closeSubpath()
        context.saveGState()
        context.addPath(path)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.vermilion.withAlphaComponent(0.8).cgColor,
                CompassTheme.vermilionLit.cgColor,
                CompassTheme.vermilion.cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: leftPoint,
                end: rightPoint,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        drawNeedleWear(in: context, at: { at($0, $1) }, tip: tip, halfWidth: halfWidth)
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.50).cgColor)
        context.setLineWidth(0.8)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Labels

    func drawSliceLabels(in context: CGContext, state: State, metrics: CompassMetrics) {
        let layout = layout(for: state)
        let alpha = CGFloat(state.contentAlpha)
        let pageShift = CGFloat((1 - Easing.outCubic(min(1, max(0, state.pageAlpha)))) * 9)
        // Where the sweep's leading edge is, as a fraction of a turn clockwise from 12 o'clock. It is
        // the same easing `drawSweep` uses, so each label lights as the edge reaches its bearing.
        let edge = Easing.outQuint(min(1, max(0, state.sweep)))
        let size = metrics.labelFontSize(sliceCount: state.slices.count)
        let radius = metrics.labelRadius

        for index in 0..<max(1, state.slices.count) {
            guard let bookmark = state.slices[safe: index] else { continue }
            let angle = layout.centerAngle(of: index)
            let anchor = state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: metrics.cardDepth
            )
            let scale = inkScale(at: Point3D(radius: radius, angle: angle), state)

            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0

            // The labels come in clockwise with the sweep. The reveal is measured against the edge scaled
            // by 1.22, so the last slot (a bearing under one turn) is fully inked before the sweep settles,
            // and slot 1 (bearing 0) starts dark. A hovered label is never dimmed by that.
            let bearing = Double(RadialLayout.normalize(angle)) / (2 * .pi)
            let revealed = Easing.smoothstep(min(1, max(0, (1.22 * edge - bearing) / 0.22)))
            let labelAlpha = alpha * CGFloat(max(Double(hover), revealed))

            let label = fittedLabel(
                bookmark.displayTitle,
                size: size,
                index: index,
                radius: radius,
                layout: layout,
                metrics: metrics
            )

            context.saveGState()
            // Clip to the wedge: glyph metrics vary with the font actually installed, and the
            // wedge is the authority on where a slice ends.
            context.addPath(wedge(
                index: index,
                inset: 0.05,
                inner: metrics.sectorInset,
                outer: metrics.sectorOutset,
                layout: layout,
                state
            ))
            context.clip()

            let box = CGRect(
                x: anchor.x - label.width / 2,
                y: anchor.y - label.height / 2 + pageShift,
                width: label.width,
                height: label.height
            )
            // Halo first, ink on top. The needle passes under the aimed name, and dark ink on
            // vermilion is unreadable without a pale rim to lift the letters off it.
            draw(squashed: label.halo(alpha: labelAlpha), in: box, scale: scale, context: context)
            draw(squashed: label.ink(alpha: labelAlpha), in: box, scale: scale, context: context)
            context.restoreGState()
        }
    }

    /// One wedge name, laid out at the page's shared size.
    private struct WedgeLabel {
        let text: String
        let size: CGFloat
        let wraps: Bool
        let width: CGFloat
        let height: CGFloat

        private func attributed(_ attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
            var all = attributes
            all[.font] = CompassTheme.label(size)
            all[.paragraphStyle] = paragraph
            return NSAttributedString(string: text, attributes: all)
        }

        func ink(alpha: CGFloat) -> NSAttributedString {
            attributed([.foregroundColor: CompassTheme.ink.withAlphaComponent(alpha)])
        }

        /// Stroke-only copy in paper colour. A positive `strokeWidth` draws the outline alone.
        func halo(alpha: CGFloat) -> NSAttributedString {
            attributed([
                .foregroundColor: NSColor.clear,
                .strokeColor: CompassTheme.paperLit.withAlphaComponent(0.78 * alpha),
                .strokeWidth: 18,
            ])
        }
    }

    /// Lays a name out at `size`: one line if the wedge has the room, otherwise two lines at
    /// the *same* size, with truncation only as the backstop.
    ///
    /// The old approach shrank the type until it fitted, which is what made labels differ in
    /// size. Here the size is fixed and the wedge's room is spent in height instead.
    private func fittedLabel(
        _ text: String,
        size: CGFloat,
        index: Int,
        radius: CGFloat,
        layout: RadialLayout,
        metrics: CompassMetrics
    ) -> WedgeLabel {
        let font = CompassTheme.label(size)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let cap = metrics.cardRadius * 0.60

        func room(lines: CGFloat) -> CGFloat {
            let limit = layout.labelWidthLimit(for: index, radius: radius, height: lineHeight * lines, pad: metrics.labelPad)
            return max(34, min(limit, cap))
        }
        func width(_ string: String) -> CGFloat {
            ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
        }

        let oneLine = room(lines: 1)
        let whole = width(text)
        if whole <= oneLine {
            return WedgeLabel(text: text, size: size, wraps: false, width: oneLine, height: lineHeight)
        }

        // Two lines only help if every word fits on one; a single long word has to truncate
        // on its own line rather than break mid-word.
        let twoLines = room(lines: 2)
        let longest = text.split(separator: " ").map { width(String($0)) }.max() ?? whole
        if longest <= twoLines, text.contains(" ") {
            return WedgeLabel(text: text, size: size, wraps: true, width: twoLines, height: lineHeight * 2)
        }
        return WedgeLabel(text: text, size: size, wraps: false, width: oneLine, height: lineHeight)
    }

    // MARK: - Hub

    func drawHub(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.hubRadius
        let hover = min(1, max(0, state.hubHover))
        let base = metrics.cardDepth
        let top = base + metrics.hubHeight
        let shoulder = base + metrics.hubHeight * 0.18
        let well = base + metrics.hubHeight * 0.42
        let opening = metrics.hubWindowRadius + radius * 0.075
        let crown = opening + radius * 0.04
        let camera = state.camera

        drawHubShadow(in: context, state: state, metrics: metrics)

        let aperture = CGMutablePath()
        aperture.addLines(between: circle(opening, state, z: top))
        aperture.closeSubpath()
        let window = CGMutablePath()
        window.addLines(between: circle(metrics.hubWindowRadius, state, z: well))
        window.closeSubpath()
        context.saveGState()
        context.addPath(aperture)
        context.clip()
        context.addPath(window)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.hubWindow.cgColor,
                CompassTheme.hubWindow.cgColor,
                NSColor.black.cgColor,
            ] as CFArray,
            locations: [0, 0.55, 1]
        ) {
            context.drawRadialGradient(
                gradient,
                startCenter: camera.project(x: radius * 0.10, y: radius * 0.15, z: well),
                startRadius: 0,
                endCenter: camera.project(x: 0, y: 0, z: well),
                endRadius: metrics.hubWindowRadius * 1.05,
                options: [.drawsAfterEndLocation]
            )
        }

        // The readout stays on the recessed floor, not on the screen or the brass lip.
        let origin = camera.project(x: 0, y: 0, z: well)
        let unitX = camera.project(x: 1, y: 0, z: well)
        let unitY = camera.project(x: 0, y: 1, z: well)
        context.concatenate(CGAffineTransform(
            a: unitX.x - origin.x, b: unitX.y - origin.y,
            c: unitY.x - origin.x, d: unitY.y - origin.y,
            tx: origin.x, ty: origin.y
        ))
        let readout = state.hoveredSlice.map { String(format: "%02d", $0 + 1) } ?? "–"
        drawText(
            readout,
            at: .zero,
            scale: 1,
            font: CompassTheme.serif(radius * 0.62, .semibold),
            colour: CompassTheme.hubWindowInk.withAlphaComponent(1 - hover),
            in: context
        )
        if hover > 0.02 {
            let arm = radius * 0.30
            context.rotate(by: hover * .pi / 4)
            context.setStrokeColor(CompassTheme.hubWindowInk.withAlphaComponent(0.92 * Double(hover)).cgColor)
            context.setLineWidth(max(1.5, radius * 0.055))
            context.setLineCap(.round)
            context.move(to: CGPoint(x: -arm, y: -arm))
            context.addLine(to: CGPoint(x: arm, y: arm))
            context.move(to: CGPoint(x: arm, y: -arm))
            context.addLine(to: CGPoint(x: -arm, y: arm))
            context.strokePath()
        }
        context.restoreGState()

        var profile: [(radius: CGFloat, z: CGFloat)] = [(radius, base)]
        for step in 0...10 {
            let angle = CGFloat(step) / 10 * .pi / 2
            profile.append((crown + (radius - crown) * cos(angle), shoulder + (top - shoulder) * sin(angle)))
        }
        profile.append((opening, top))
        profile.append((metrics.hubWindowRadius, well))

        var faces: [(points: [CGPoint], normal: Point3D, depth: CGFloat, band: Int)] = []
        let segments = 96
        faces.reserveCapacity((profile.count - 1) * segments)
        for band in 0..<(profile.count - 1) {
            let from = profile[band]
            let to = profile[band + 1]
            let dr = to.radius - from.radius
            let dz = to.z - from.z
            let length = hypot(dr, dz)
            for step in 0..<segments {
                let a0 = CGFloat(step) / CGFloat(segments) * 2 * .pi
                let a1 = CGFloat(step + 1) / CGFloat(segments) * 2 * .pi
                let mid = (a0 + a1) / 2
                let normal = camera.rotate(Point3D(x: dz * sin(mid) / length, y: -dz * cos(mid) / length, z: -dr / length))
                let centre = camera.rotate(Point3D(radius: (from.radius + to.radius) / 2, angle: mid, z: (from.z + to.z) / 2))
                guard -normal.x * centre.x - normal.y * centre.y + normal.z * (camera.eyeDistance - centre.z) > 0 else { continue }
                let points = [
                    Point3D(radius: from.radius, angle: a0, z: from.z),
                    Point3D(radius: from.radius, angle: a1, z: from.z),
                    Point3D(radius: to.radius, angle: a1, z: to.z),
                    Point3D(radius: to.radius, angle: a0, z: to.z),
                ].map { camera.project($0).point }
                faces.append((points, normal, centre.z, band))
            }
        }

        let shell = CGMutablePath()
        for face in faces.sorted(by: { $0.depth < $1.depth }) {
            let isInner = face.band == profile.count - 2
            let intensity = brassIntensity(face.normal, shine: isInner ? 0.12 : 0.26)
            let colour = brassColour(intensity * (isInner ? 0.60 : 0.96))
            fill(face.points, context, colour)
            // Overlap the mesh edges so antialiasing cannot expose the card between faces.
            stroke(face.points + [face.points[0]], context, colour, width: 0.45)
            shell.addLines(between: face.points)
            shell.closeSubpath()
        }
        drawHubWear(in: context, state: state, metrics: metrics, boss: shell) { distance in
            let t = min(1, max(0, (distance - crown) / (radius - crown)))
            return shoulder + (top - shoulder) * sqrt(1 - t * t)
        }

        for step in 0..<segments {
            let a0 = CGFloat(step) / CGFloat(segments) * 2 * .pi
            let a1 = CGFloat(step + 1) / CGFloat(segments) * 2 * .pi
            let mid = (a0 + a1) / 2
            let normal = camera.rotate(Point3D(x: -sin(mid) * 0.707, y: cos(mid) * 0.707, z: 0.707))
            let light = min(1, max(0, brassIntensity(normal, shine: 0.18) - 0.25))
            line(
                camera.project(Point3D(radius: opening, angle: a0, z: top)).point,
                camera.project(Point3D(radius: opening, angle: a1, z: top)).point,
                context,
                CompassTheme.brassHi.withAlphaComponent(0.12 + light * (0.52 + hover * 0.18)),
                width: max(0.65, radius * 0.023)
            )
        }
    }

    private func drawHubShadow(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.hubRadius
        let lift = metrics.hubHeight
        let base = metrics.cardDepth
        for step in (1...8).reversed() {
            let reach = CGFloat(step) / 8
            let points = circle(radius * (1 + 0.08 * reach), state, z: base).map {
                CGPoint(x: $0.x + lift * 0.60 * reach, y: $0.y + lift * 0.85 * reach)
            }
            fill(points, context, NSColor.black.withAlphaComponent(0.045))
        }
        fill(circle(radius * 1.025, state, z: base), context, NSColor.black.withAlphaComponent(0.24))
    }

    // MARK: - Opening sweep

    /// One orchestrated gesture as the compass appears: a needle of light runs once around the
    /// card and expires, explaining the clockwise order in a single beat.
    func drawSweep(in context: CGContext, state: State, metrics: CompassMetrics) {
        let progress = state.sweep
        guard progress > 0.002, progress < 0.998 else { return }
        let eased = Easing.outQuint(min(1, progress))
        // Slot 1 sits at 12 o'clock (`RadialLayout.centerAngle(of: 0)` is 0), so the sweep starts there
        // and runs clockwise, the same way the slots are numbered.
        let start: CGFloat = 0
        let end = start + 2 * .pi * CGFloat(eased)
        let radius = metrics.numeralRadius
        let fade = CGFloat(1 - Easing.outCubic(min(1, progress)))

        let arc = (0...48).map { step -> CGPoint in
            let angle = start + (end - start) * CGFloat(step) / 48
            return state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: metrics.cardDepth
            )
        }
        stroke(arc, context,
               CompassTheme.vermilion.withAlphaComponent(0.85 * fade * CGFloat(state.contentAlpha)),
               width: 2)
    }

    // MARK: - Helpers

    /// The layout the dial has always used, so labels, hit testing and keyboard firing cannot
    /// disagree about where a slice is.
    private func layout(for state: State) -> RadialLayout {
        RadialLayout(
            sliceCount: max(1, state.slices.count),
            centerRadius: state.metrics.hubRadius,
            outerRadius: state.metrics.sectorOutset
        )
    }

    /// Draws type at the depth scale of its anchor and squeezes it vertically, so it lies on
    /// the leaning card instead of floating above it.
    private func draw(squashed string: NSAttributedString, in box: CGRect, scale: CGFloat, context: CGContext) {
        context.saveGState()
        context.translateBy(x: box.midX, y: box.midY)
        context.scaleBy(x: 1, y: max(0.5, scale))
        string.draw(with: CGRect(
            x: -box.width / 2,
            y: -box.height / 2,
            width: box.width,
            height: box.height
        ), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        context.restoreGState()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
