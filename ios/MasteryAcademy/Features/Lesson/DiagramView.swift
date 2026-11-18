import SwiftUI

/// Draws a diagram at its design size inside a horizontal scroller, so labels stay readable on a phone.
/// Diagrams with steps get a step player; nodes with a detail text can be tapped.
struct DiagramView: View {
    let diagram: Diagram
    let tint: Color

    @State private var step: Int?
    @State private var selected: String?

    private var nodesById: [String: Diagram.Node] {
        Dictionary(diagram.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var activeStep: Diagram.Step? {
        guard let step, diagram.steps.indices.contains(step) else { return nil }
        return diagram.steps[step]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(diagram.title).font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in drawBackground(&context) }
                    ForEach(diagram.nodes) { node in
                        nodeView(node)
                            .frame(width: node.w, height: node.h)
                            .position(x: node.x + node.w / 2, y: node.y + node.h / 2)
                    }
                }
                .frame(width: diagram.width, height: diagram.height)
                .padding(.bottom, 6)
            }
            if let selected, let node = nodesById[selected], !node.detail.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.label).font(.caption.weight(.semibold))
                    MarkupText(node.detail).font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            if !diagram.steps.isEmpty { stepPlayer }
            if !diagram.caption.isEmpty {
                MarkupText(diagram.caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diagram: \(diagram.title)")
    }

    // MARK: Nodes

    private func isActive(_ node: Diagram.Node) -> Bool {
        if let activeStep { return activeStep.from == node.id || activeStep.to == node.id }
        return node.hot
    }

    @ViewBuilder
    private func nodeView(_ node: Diagram.Node) -> some View {
        let active = isActive(node)
        let color = active ? tint : kindColor(node.kind)
        let label = VStack(spacing: 1) {
            Text(node.label).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
            if !node.sub.isEmpty {
                Text(node.sub).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Group {
            if node.kind == "decision" {
                label.background(Diamond().fill(color.opacity(active ? 0.22 : 0.10)))
                    .overlay(Diamond().stroke(color, lineWidth: active ? 2 : 1.2))
            } else {
                label.background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(active ? 0.22 : 0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: active || selected == node.id ? 2 : 1.2))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !node.detail.isEmpty else { return }
            selected = selected == node.id ? nil : node.id
        }
        .accessibilityLabel(node.sub.isEmpty ? node.label : "\(node.label), \(node.sub)")
        .accessibilityHint(node.detail)
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "client": return .blue
        case "edge", "gateway": return .purple
        case "service", "worker": return .teal
        case "db": return .orange
        case "cache": return .pink
        case "queue": return .indigo
        case "external": return .gray
        default: return .secondary
        }
    }

    // MARK: Lanes and edges

    private func drawBackground(_ context: inout GraphicsContext) {
        for lane in diagram.lanes {
            let rect = CGRect(x: 0, y: lane.y, width: diagram.width, height: lane.h)
            context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(.secondary.opacity(0.07)))
            context.draw(Text(lane.label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary),
                         at: CGPoint(x: 8, y: lane.y + 10), anchor: .leading)
        }
        let nodes = nodesById
        for edge in diagram.edges {
            let points = DiagramGeometry.points(for: edge, nodes: nodes)
            guard points.count >= 2 else { continue }
            let active = isActive(edge)
            let color: Color = active ? tint : .secondary
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            let style = StrokeStyle(lineWidth: active ? 2.2 : 1.2, lineCap: .round, lineJoin: .round, dash: edge.dashed ? [5, 4] : [])
            context.stroke(path, with: .color(color), style: style)

            let tip = points[points.count - 1]
            let (left, right) = DiagramGeometry.arrowHead(tip: tip, previous: points[points.count - 2])
            var head = Path()
            head.move(to: tip); head.addLine(to: left); head.addLine(to: right); head.closeSubpath()
            context.fill(head, with: .color(color))

            if !edge.label.isEmpty, let middle = DiagramGeometry.labelPoint(points) {
                let text = context.resolve(Text(edge.label).font(.system(size: 10)).foregroundStyle(active ? tint : Color.secondary))
                let size = text.measure(in: CGSize(width: 160, height: 40))
                let box = CGRect(x: middle.x - size.width / 2 - 3, y: middle.y - size.height / 2 - 1, width: size.width + 6, height: size.height + 2)
                context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Color(uiColor: .secondarySystemGroupedBackground)))
                context.draw(text, at: middle, anchor: .center)
            }
        }
    }

    private func isActive(_ edge: Diagram.Edge) -> Bool {
        if let activeStep, let from = edge.from, let to = edge.to {
            return (from == activeStep.from && to == activeStep.to) || (from == activeStep.to && to == activeStep.from)
        }
        return activeStep == nil && edge.hot
    }

    // MARK: Steps

    private var stepPlayer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    step = max((step ?? 0) - 1, 0)
                } label: { Image(systemName: "chevron.left") }
                    .disabled(step == nil || step == 0)
                    .accessibilityLabel("Previous step")
                Text(step.map { "Step \($0 + 1) of \(diagram.steps.count)" } ?? "\(diagram.steps.count) steps")
                    .font(.caption.weight(.medium)).monospacedDigit()
                Button {
                    step = min((step ?? -1) + 1, diagram.steps.count - 1)
                } label: { Image(systemName: "chevron.right") }
                    .disabled(step == diagram.steps.count - 1)
                    .accessibilityLabel("Next step")
                Spacer()
                if step != nil {
                    Button("Reset") { step = nil }.font(.caption)
                }
            }
            .buttonStyle(.bordered)
            if let activeStep {
                let from = nodesById[activeStep.from]?.label ?? activeStep.from
                let to = nodesById[activeStep.to]?.label ?? activeStep.to
                Text("\(from) → \(to)").font(.caption.weight(.semibold)).foregroundStyle(tint)
                MarkupText(activeStep.text).font(.subheadline)
            } else {
                Text("Step through the request to see which parts talk to each other.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
