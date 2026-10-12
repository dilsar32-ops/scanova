import UIKit

// A room's wall segments (feet-space) plus its own name, if known - the
// minimal shape FloorPlanPanelView needs to draw a live, cumulative
// sketch of the plan-so-far. Deliberately NOT the same shape as
// FloorPlanEncoder's JSON output - this is a disposable, in-scan
// preview, not the source of truth (finishSession() remains that).
struct RoomSketch {
    let name: String?
    let walls: [(CGPoint, CGPoint)]
}

// A rough, honest live sketch of every room finished SO FAR during a
// multi-room scan - lines only, no hatching/dimension lines/door symbols
// (that fidelity belongs to the polished web SVG renderer, which can't
// run live during a scan - a second WKWebView alongside an active
// ARKit/LiDAR session was already rejected earlier as a real, unverified
// resource-contention risk). Redraws from scratch on every update() via
// draw(rect:) rather than diffing CAShapeLayers: updates arrive at most
// once per finished room (tens of seconds apart), so GPU-compositing
// wins from a diffing approach are irrelevant at this cadence, and a
// full stateless redraw sidesteps needing a stable per-room identifier
// (RoomPlan only guarantees stable identifiers at wall/door/window/
// object granularity, not room granularity).
class FloorPlanPanelView: UIView {
    private var rooms: [RoomSketch] = []
    private var merged = true
    // El "segundo asistente" a la vista: las esquinas del ÚLTIMO cuarto que
    // no cerraron, marcadas en naranja sobre el croquis. Solo se ven; el
    // plano es el que propone cerrarlas.
    private var esquinas: [CGPoint] = []
    func marcarEsquinas(_ puntos: [CGPoint]) {
        esquinas = puntos
        setNeedsDisplay()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rooms: [RoomSketch], merged: Bool) {
        self.rooms = rooms
        self.merged = merged
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !rooms.isEmpty else { return }
        let allPoints = rooms.flatMap { room in room.walls.flatMap { [$0.0, $0.1] } }
        guard !allPoints.isEmpty else { return }
        let minX = allPoints.map(\.x).min()!, maxX = allPoints.map(\.x).max()!
        let minY = allPoints.map(\.y).min()!, maxY = allPoints.map(\.y).max()!
        let spanX = max(maxX - minX, 1), spanY = max(maxY - minY, 1)
        // Auto-fit from scratch on every draw - no persisted zoom/pan
        // state - which is what lets "visible at all times" hold with no
        // gesture the tech has to discover or manage one-handed.
        let scale = min(rect.width / spanX, rect.height / spanY) * 0.92
        let drawnW = spanX * scale, drawnH = spanY * scale
        let offsetX = (rect.width - drawnW) / 2, offsetY = (rect.height - drawnH) / 2
        func project(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - minX) * scale + offsetX, y: (p.y - minY) * scale + offsetY)
        }

        // Lines thin out as the plan grows so a whole-house scan doesn't
        // visually collapse into a solid mass - walls always draw at
        // full geometric fidelity regardless of scale, only line weight
        // (and, below, text) adapt.
        let totalWallCount = rooms.reduce(0) { $0 + $1.walls.count }
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
        ctx.setLineWidth(totalWallCount > 60 ? 1.0 : 2.0)
        ctx.setLineCap(.round)
        let path = CGMutablePath()
        for room in rooms {
            for (a, b) in room.walls {
                path.move(to: project(a))
                path.addLine(to: project(b))
            }
        }
        ctx.addPath(path)
        ctx.strokePath()

        // Las esquinas abiertas: un arco naranja donde las dos paredes se
        // encontrarían. Se dibuja aunque el punto caiga un poco fuera del
        // encuadre (una esquina que falta está, por definición, más allá
        // de las puntas dibujadas).
        if !esquinas.isEmpty {
            ctx.setStrokeColor(UIColor.systemOrange.cgColor)
            ctx.setLineWidth(2.0)
            for e in esquinas {
                let p = project(e)
                ctx.addArc(center: p, radius: 6, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
                ctx.strokePath()
            }
        }

        // A room's name is drawn at its own polygon centroid - the SAME
        // area-weighted (shoelace) formula the finished plan's web SVG
        // renderer uses - so a label lands in approximately the same
        // spot here as it will in the reviewed plan. Past a legibility
        // floor (the panel is small - 160pt tall, shared by every room
        // scanned so far), a name is replaced by a small numbered dot
        // rather than rendered too small to read.
        let labelFontSize: CGFloat = totalWallCount > 40 ? 8 : 11
        let minLegibleFontSize: CGFloat = 7
        for (idx, room) in rooms.enumerated() {
            guard !room.walls.isEmpty else { continue }
            let centroid = Self.polygonCentroid(room.walls)
            let p = project(centroid)
            if labelFontSize >= minLegibleFontSize, let name = room.name, !name.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: labelFontSize, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                let text = name as NSString
                let size = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2), withAttributes: attrs)
            } else {
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
                ctx.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
                let dotAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85)
                ]
                ("\(idx + 1)" as NSString).draw(at: CGPoint(x: p.x + 4, y: p.y - 5), withAttributes: dotAttrs)
            }
        }

        if !merged {
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor.systemOrange
            ]
            ("sin combinar" as NSString).draw(at: CGPoint(x: 8, y: rect.height - 16), withAttributes: badgeAttrs)
        }
    }

    // Same area-weighted (shoelace) polygon centroid the web SVG renderer
    // already uses for room-name placement (each wall's own start point,
    // in scan order).
    private static func polygonCentroid(_ walls: [(CGPoint, CGPoint)]) -> CGPoint {
        let pts = walls.map { $0.0 }
        func bboxCenter() -> CGPoint {
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        }
        guard pts.count >= 3 else { return bboxCenter() }
        var area: CGFloat = 0, cx: CGFloat = 0, cy: CGFloat = 0
        for i in 0..<pts.count {
            let j = (i + pts.count - 1) % pts.count
            let cross = pts[j].x * pts[i].y - pts[i].x * pts[j].y
            area += cross
            cx += (pts[j].x + pts[i].x) * cross
            cy += (pts[j].y + pts[i].y) * cross
        }
        area *= 0.5
        guard abs(area) > 0.0001 else { return bboxCenter() }
        return CGPoint(x: cx / (6 * area), y: cy / (6 * area))
    }
}
