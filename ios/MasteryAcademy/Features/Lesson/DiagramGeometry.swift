import CoreGraphics

/// Pure geometry for diagrams, kept apart from the view so it can be unit tested.
enum DiagramGeometry {
    /// Where the segment from the centre of `rect` towards `target` leaves the rectangle.
    static func exitPoint(of rect: CGRect, towards target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x, dy = target.y - center.y
        if dx == 0 && dy == 0 { return center }
        let scaleX = dx == 0 ? CGFloat.greatestFiniteMagnitude : (rect.width / 2) / abs(dx)
        let scaleY = dy == 0 ? CGFloat.greatestFiniteMagnitude : (rect.height / 2) / abs(dy)
        let scale = min(scaleX, scaleY)
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    /// The polyline for an edge: explicit points when given, otherwise a straight line between the two node borders.
    static func points(for edge: Diagram.Edge, nodes: [String: Diagram.Node]) -> [CGPoint] {
        if let raw = edge.points, raw.count >= 2 {
            return raw.compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        }
        guard let fromId = edge.from, let toId = edge.to, let a = nodes[fromId], let b = nodes[toId] else { return [] }
        let start = exitPoint(of: a.rect, towards: CGPoint(x: b.rect.midX, y: b.rect.midY))
        let end = exitPoint(of: b.rect, towards: CGPoint(x: a.rect.midX, y: a.rect.midY))
        return [start, end]
    }

    /// Two points that, with `tip`, form an arrowhead for a segment arriving from `previous`.
    static func arrowHead(tip: CGPoint, previous: CGPoint, size: CGFloat = 8) -> (CGPoint, CGPoint) {
        let angle = atan2(tip.y - previous.y, tip.x - previous.x)
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: tip.x - size * cos(angle - spread), y: tip.y - size * sin(angle - spread))
        let right = CGPoint(x: tip.x - size * cos(angle + spread), y: tip.y - size * sin(angle + spread))
        return (left, right)
    }

    /// Middle of the longest segment, where the label is drawn.
    static func labelPoint(_ points: [CGPoint]) -> CGPoint? {
        guard points.count >= 2 else { return nil }
        var best = (length: CGFloat(-1), point: points[0])
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let length = hypot(b.x - a.x, b.y - a.y)
            if length > best.length { best = (length, CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)) }
        }
        return best.point
    }
}
