import SwiftUI
import UIKit

/// Renders one content block.
struct BlockView: View {
    let block: Block
    let tint: Color

    var body: some View {
        switch block {
        case .heading(let text):
            MarkupText(text).font(.title3.weight(.semibold)).padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        case .text(let text):
            MarkupText(text)
        case .code(let code):
            CodeBlockView(block: code)
        case .list(let ordered, let items):
            ListBlockView(ordered: ordered, items: items)
        case .callout(let callout):
            CalloutView(callout: callout, tint: tint)
        case .table(let table):
            TableBlockView(table: table)
        case .links(let links):
            VStack(alignment: .leading, spacing: 8) {
                Text("References").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    LinkRow(link: link).buttonStyle(.plain)
                    if link != links.last { Divider() }
                }
            }
            .card()
        case .diagram(let diagram):
            DiagramView(diagram: diagram, tint: tint)
        case .task(let task):
            TaskBlockView(task: task, tint: tint)
        case .unknown:
            EmptyView()
        }
    }
}

struct ListBlockView: View {
    let ordered: Bool
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .foregroundStyle(.secondary).monospacedDigit()
                        .frame(minWidth: ordered ? 22 : 10, alignment: .trailing)
                    MarkupText(item)
                }
            }
        }
    }
}

struct CodeBlockView: View {
    let block: CodeBlock
    @State private var copied = false
    @State private var fullScreen = false
    @AppStorage(ReadingKeys.codeWrap) private var wrap = false
    @Environment(\.explainAction) private var explainAction
    @Environment(\.blockIndex) private var blockIndex

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(block.caption ?? block.language).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button {
                    UIPasteboard.general.string = block.code
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                }
                .buttonStyle(.borderless)
                if let explainAction, let blockIndex {
                    Button {
                        explainAction.run(blockIndex)
                    } label: {
                        Label("Explain", systemImage: "sparkles").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 8)
                }
                Button {
                    fullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
                .accessibilityLabel("Open code full screen")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if wrap {
                Text(SwiftHighlighter.attributed(block.code))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(SwiftHighlighter.attributed(block.code))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
            }
        }
        .fullScreenCover(isPresented: $fullScreen) {
            CodeFullScreen(block: block)
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Code sample")
    }
}

struct CalloutView: View {
    let callout: Callout
    let tint: Color
    @State private var revealed = false

    private var symbol: String {
        switch callout.style {
        case "tip": return "lightbulb"
        case "warn": return "exclamationmark.triangle"
        case "question": return "questionmark.bubble"
        default: return "info.circle"
        }
    }

    private var color: Color {
        switch callout.style {
        case "tip": return .yellow
        case "warn": return .orange
        case "question": return tint
        default: return .secondary
        }
    }

    /// A question hides its answer until asked, so the learner can try first.
    private var hidesAnswer: Bool { callout.style == "question" && !callout.text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                MarkupText(callout.title).font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            if hidesAnswer {
                if revealed {
                    MarkupText(callout.text).font(.subheadline)
                }
                Button(revealed ? "Hide answer" : "Show answer") {
                    withAnimation(.easeInOut(duration: 0.2)) { revealed.toggle() }
                }
                .font(.subheadline)
            } else if !callout.text.isEmpty {
                MarkupText(callout.text).font(.subheadline)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 8)
        }
    }
}

/// Two columns render as a key/value grid. Wider tables become one card per row on a phone,
/// because four columns of prose do not fit in 360 points.
struct TableBlockView: View {
    let table: TableBlock
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var hasHeaders: Bool { table.headers.contains { !$0.isEmpty } }

    var body: some View {
        if table.headers.count <= 2 || (sizeClass == .regular && table.headers.count <= 4) {
            grid
        } else {
            stacked
        }
    }

    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 8) {
            if hasHeaders {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        Text(header).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        MarkupText(cell).font(.subheadline)
                            .fontWeight(column == 0 && !hasHeaders ? .semibold : .regular)
                            .frame(maxWidth: column == 0 && table.headers.count == 2 ? 130 : .infinity, alignment: .leading)
                    }
                }
                if index < table.rows.count - 1 { Divider() }
            }
        }
        .card()
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        if column == 0 {
                            MarkupText(cell).font(.subheadline.weight(.semibold))
                        } else if !cell.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(column < table.headers.count ? table.headers[column] : "").font(.caption).foregroundStyle(.secondary)
                                MarkupText(cell).font(.subheadline)
                            }
                        }
                    }
                }
                .card()
            }
        }
    }
}
