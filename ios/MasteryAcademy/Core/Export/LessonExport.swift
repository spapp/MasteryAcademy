import UIKit

/// Turns a lesson into HTML and then into a PDF file that can be shared or printed.
enum LessonExport {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func tag(_ name: String, _ inner: String) -> String {
        "<\(name)>\(inner)</\(name)>"
    }

    static func inline(_ source: String) -> String {
        var out = ""
        for span in InlineMarkup.parse(source) {
            switch span {
            case .plain(let text): out += escape(text)
            case .bold(let text): out += tag("b", escape(text))
            case .italic(let text): out += tag("i", escape(text))
            case .code(let text): out += tag("code", escape(text))
            }
        }
        return out
    }

    private static func tableHTML(_ table: TableBlock) -> String {
        var rows = ""
        if table.headers.contains(where: { !$0.isEmpty }) {
            var cells = ""
            for header in table.headers { cells += tag("th", inline(header)) }
            rows += tag("tr", cells)
        }
        for row in table.rows {
            var cells = ""
            for cell in row { cells += tag("td", inline(cell)) }
            rows += tag("tr", cells)
        }
        return tag("table", rows)
    }

    private static func listHTML(ordered: Bool, items: [String]) -> String {
        var inner = ""
        for item in items { inner += tag("li", inline(item)) }
        return tag(ordered ? "ol" : "ul", inner)
    }

    private static func blockHTML(_ block: Block) -> String {
        switch block {
        case .heading(let text):
            return tag("h2", inline(text))
        case .text(let text):
            return tag("p", inline(text))
        case .code(let code):
            return tag("pre", escape(code.code))
        case .list(let ordered, let items):
            return listHTML(ordered: ordered, items: items)
        case .callout(let callout):
            let title: String = tag("b", inline(callout.title))
            let text: String = inline(callout.text)
            return "<div class=\"callout\">\(title)<br>\(text)</div>"
        case .table(let table):
            return tableHTML(table)
        case .links(let links):
            var inner = ""
            for link in links {
                let line: String = escape(link.title) + ": " + escape(link.url)
                inner += tag("li", line)
            }
            return tag("ul", inner)
        case .diagram(let diagram):
            let line: String = "Diagram: " + escape(diagram.title) + ". " + escape(diagram.caption)
            return tag("p", tag("i", line))
        case .task(let task):
            return tag("h2", "Your task") + tag("p", inline(task.prompt)) + listHTML(ordered: false, items: task.rubric)
        case .unknown:
            return ""
        }
    }

    static func html(courseTitle: String, lesson: Lesson) -> String {
        var body: [String] = []
        let course: String = escape(courseTitle)
        body.append("<p class=\"course\">\(course)</p>")
        body.append(tag("h1", inline(lesson.title)))
        for block in lesson.blocks {
            body.append(blockHTML(block))
        }
        let style = """
        body { font: 11pt -apple-system, Helvetica, sans-serif; color: #111; line-height: 1.45; }
        h1 { font-size: 20pt; margin: 0 0 12pt; } h2 { font-size: 14pt; margin: 16pt 0 6pt; }
        .course { color: #666; font-size: 9pt; text-transform: uppercase; margin: 0 0 4pt; }
        pre { font: 8.5pt Menlo, monospace; background: #f3f3f3; padding: 8pt; white-space: pre-wrap; word-wrap: break-word; }
        code { font: 10pt Menlo, monospace; color: #1d4ed8; }
        table { border-collapse: collapse; width: 100%; } th, td { border: 0.5pt solid #bbb; padding: 4pt 6pt; text-align: left; vertical-align: top; font-size: 10pt; }
        th { background: #eee; } .callout { border-left: 3pt solid #999; background: #f6f6f6; padding: 6pt 8pt; margin: 8pt 0; }
        """
        let content: String = body.joined(separator: "\n")
        return "<html><head><meta charset=\"utf-8\"><style>\(style)</style></head><body>\(content)</body></html>"
    }

    /// A4 PDF of the lesson. Must run on the main thread because it uses UIKit's print renderer.
    @MainActor
    static func pdfData(courseTitle: String, lesson: Lesson) -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: html(courseTitle: courseTitle, lesson: lesson))
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 40, dy: 44)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// Writes `data` to a temporary file with a readable name and returns its URL.
    static func temporaryFile(named name: String, extension ext: String, data: Data) throws -> URL {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "-" }
        let trimmed = String(String(safe).prefix(60)).trimmingCharacters(in: .whitespaces)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent((trimmed.isEmpty ? "export" : trimmed) + "." + ext)
        try data.write(to: url, options: .atomic)
        return url
    }
}
