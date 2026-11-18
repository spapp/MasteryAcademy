import SwiftUI

struct LessonView: View {
    let courseId: String
    let lessonId: String

    var body: some View {
        CourseLoader(courseId: courseId) { course in
            if let lesson = course.lesson(id: lessonId) {
                LessonContentView(course: course, lesson: lesson)
            } else {
                ContentUnavailableView("Lesson not found", systemImage: "questionmark.folder",
                                       description: Text("This lesson is not part of the installed version of the course."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OutlineItem: Identifiable {
    let index: Int
    let title: String
    var id: Int { index }
}

private struct NoteTarget: Identifiable {
    let index: Int
    let excerpt: String
    var id: Int { index }
}

private struct TutorTarget: Identifiable {
    let blockIndex: Int?
    let excerpt: String?
    var id: Int { blockIndex ?? -1 }
}

private struct ExplainTarget: Identifiable {
    let blockIndex: Int
    let code: CodeBlock
    var id: Int { blockIndex }
}

private struct LessonContentView: View {
    let course: Course
    let lesson: Lesson

    @Environment(ProgressStore.self) private var progress
    @Environment(ContentRepository.self) private var repository
    @Environment(AnnotationStore.self) private var reading
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage(ReadingKeys.textStep) private var textStep = 0
    @AppStorage(ReadingKeys.lineSpacing) private var lineSpacing = ReadingLineSpacing.normal
    @AppStorage(ReadingKeys.width) private var width = ReadingWidth.normal
    @AppStorage(ReadingKeys.theme) private var theme = ReadingTheme.system

    /// Index of the block at the top of the screen; -1 is the lesson header.
    @State private var topBlock: Int?
    @State private var showSettings = false
    @State private var showNotes = false
    @State private var noteTarget: NoteTarget?
    @State private var shareFile: ShareFile?
    @State private var exportFailed = false
    @State private var tutorTarget: TutorTarget?
    @State private var explainTarget: ExplainTarget?
    @State private var showQuizMe = false
    @StateObject private var speaker = LessonSpeaker()

    private var tint: Color { repository.summary(course.id)?.tintColor ?? .accentColor }

    private var outline: [OutlineItem] {
        lesson.blocks.enumerated().compactMap { (index, block) -> OutlineItem? in
            if case .heading(let text) = block { return OutlineItem(index: index, title: InlineMarkup.plain(text)) }
            return nil
        }
    }

    /// How far down the lesson the reader is, by blocks.
    private var fraction: Double {
        guard let top = topBlock, top >= 0, !lesson.blocks.isEmpty else { return 0 }
        return Double(top + 1) / Double(lesson.blocks.count)
    }

    private var minutesLeft: Int { ReadingStyle.minutesLeft(total: lesson.minutes, fraction: fraction) }

    private var moduleMinutesLeft: Int {
        guard let module = course.module(containing: lesson.id) else { return minutesLeft }
        let others = module.lessons.filter { $0.id != lesson.id && !progress.isLessonDone(course.id, $0.id) }
        return minutesLeft + others.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        withAI
            .onAppear { progress.setLastOpened(courseId: course.id, lessonId: lesson.id) }
            .task { restorePosition() }
            .onChange(of: topBlock) { _, value in savePosition(value) }
            .onDisappear {
                reading.flush()
                speaker.stop()
            }
    }

    private func restorePosition() {
        // Reopen where the reader stopped.
        guard topBlock == nil, let saved = reading.position(course.id, lesson.id) else { return }
        if saved > 0 && saved < lesson.blocks.count { topBlock = saved }
    }

    private func savePosition(_ value: Int?) {
        guard let value, value >= 0 else { return }
        reading.setPosition(course.id, lesson.id, value)
    }

    private var sideMargin: CGFloat { sizeClass == .compact ? width.margin : 20 }

    private var textSize: DynamicTypeSize { ReadingStyle.dynamicTypeSize(base: systemTypeSize, step: textStep) }

    private var blocks: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            header.id(-1)
            ForEach(Array(lesson.blocks.enumerated()), id: \.offset) { index, block in
                AnnotatedBlock(courseId: course.id, lessonId: lesson.id, index: index, block: block, tint: tint,
                               onNote: { noteTarget = NoteTarget(index: index, excerpt: block.excerpt) },
                               onAsk: { tutorTarget = TutorTarget(blockIndex: index, excerpt: block.excerpt) })
            }
            quiz
            quizMeButton
            footer
        }
        .scrollTargetLayout()
        .environment(\.lessonRef, LessonRef(courseId: course.id, lessonId: lesson.id))
        .environment(\.explainAction, ExplainAction(run: explain))
    }

    private func explain(_ index: Int) {
        guard index >= 0, index < lesson.blocks.count, case .code(let code) = lesson.blocks[index] else { return }
        explainTarget = ExplainTarget(blockIndex: index, code: code)
    }

    private var quizMeButton: some View {
        Button {
            showQuizMe = true
        } label: {
            Label("Quiz me on this lesson", systemImage: "sparkles").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .padding(.top, 8)
    }

    private var askButton: some View {
        Button {
            tutorTarget = TutorTarget(blockIndex: nil, excerpt: nil)
        } label: {
            Image(systemName: "sparkles")
        }
        .accessibilityLabel("Ask the tutor about this lesson")
    }

    private func tutorSheet(for target: TutorTarget) -> some View {
        TutorSheet(courseId: course.id, lessonId: lesson.id, lessonTitle: InlineMarkup.plain(lesson.title),
                   blockIndex: target.blockIndex, excerpt: target.excerpt, tint: tint) { index in
            withAnimation { topBlock = index }
        }
    }

    private func explainSheet(for target: ExplainTarget) -> some View {
        ExplainSheet(courseId: course.id, lessonId: lesson.id, blockIndex: target.blockIndex, code: target.code, tint: tint)
    }

    private var quizMeSheet: some View {
        QuizMeSheet(courseId: course.id, lessonId: lesson.id, lessonTitle: InlineMarkup.plain(lesson.title), tint: tint)
    }

    private var withAI: some View {
        withSheets
            .sheet(item: $tutorTarget) { target in tutorSheet(for: target) }
            .sheet(item: $explainTarget) { target in explainSheet(for: target) }
            .sheet(isPresented: $showQuizMe) { quizMeSheet }
    }

    @ViewBuilder
    private var quiz: some View {
        if !lesson.quiz.isEmpty {
            Divider().padding(.vertical, 6)
            Text("Check yourself").font(.title3.weight(.semibold))
            QuizView(questions: lesson.quiz, tint: tint, previous: progress.quizResult(course.id, lesson.id)) { score, total in
                progress.setQuizResult(course.id, lesson.id, score: score, total: total)
            }
        }
    }

    private var reader: some View {
        ScrollView {
            blocks
                .lineSpacing(lineSpacing.points)
                .padding(.horizontal, sideMargin)
                .padding(.vertical)
                .frame(maxWidth: width.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .dynamicTypeSize(textSize)
        }
        .scrollPosition(id: $topBlock, anchor: .top)
        .background(theme.background)
        .readingColorScheme(theme.colorScheme)
        .safeAreaInset(edge: .top, spacing: 0) { progressBar }
    }

    private var progressBar: some View {
        ProgressView(value: fraction)
            .progressViewStyle(.linear)
            .tint(tint)
            .accessibilityLabel("Reading progress")
    }

    private var withToolbar: some View {
        reader
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    askButton
                    settingsButton
                    bookmarkButton
                    moreMenu
                }
            }
            .navigationDestination(isPresented: $showNotes) {
                NotesView(courseId: course.id)
            }
    }

    private var withSheets: some View {
        withToolbar
            .sheet(isPresented: $showSettings) {
                ReadingSettingsSheet().presentationDetents([.medium, .large])
            }
            .sheet(item: $noteTarget) { target in
                noteEditor(for: target)
            }
            .sheet(item: $shareFile) { file in
                ActivityView(items: [file.url])
            }
            .alert("Could not make the PDF", isPresented: $exportFailed) {
                Button("OK", role: .cancel) {}
            }
    }

    private func noteEditor(for target: NoteTarget) -> some View {
        let existing = reading.annotation(course.id, lesson.id, target.index)?.note ?? ""
        return NoteEditor(excerpt: target.excerpt, note: existing) { text in
            reading.setNote(course.id, lesson.id, target.index, excerpt: target.excerpt, note: text)
        }
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "textformat.size")
        }
        .accessibilityLabel("Reading settings")
    }

    private var bookmarkButton: some View {
        let marked = progress.isBookmarked(course.id, lesson.id)
        return Button {
            progress.toggleBookmark(course.id, lesson.id)
        } label: {
            Image(systemName: marked ? "bookmark.fill" : "bookmark")
        }
        .accessibilityLabel(Text(marked ? "Remove bookmark" : "Bookmark this lesson"))
    }

    private var moreMenu: some View {
        Menu {
            if outline.count > 1 { outlineMenu }
            Button {
                speaker.toggle(text: spokenText)
            } label: {
                Label(speaker.isSpeaking ? "Stop reading aloud" : "Read aloud", systemImage: speaker.isSpeaking ? "stop.circle" : "speaker.wave.2")
            }
            Button {
                exportPDF()
            } label: {
                Label("Share as PDF", systemImage: "square.and.arrow.up")
            }
            Button {
                showNotes = true
            } label: {
                Label("Notes and highlights", systemImage: "note.text")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    private var outlineMenu: some View {
        Menu {
            ForEach(outline) { item in
                Button(item.title) {
                    withAnimation { topBlock = item.index }
                }
            }
        } label: {
            Label("Outline", systemImage: "list.bullet.indent")
        }
    }

    private var timeText: String {
        let total = formatMinutes(lesson.minutes)
        let left = formatMinutes(minutesLeft)
        let moduleLeft = formatMinutes(moduleMinutesLeft)
        return total + " · " + left + " left · " + moduleLeft + " left in this module"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let module = course.module(containing: lesson.id) {
                Text(module.title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(tint)
            }
            MarkupText(lesson.title).font(.title2.weight(.bold))
            Text(timeText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var spokenText: String {
        var parts: [String] = [InlineMarkup.plain(lesson.title)]
        for block in lesson.blocks {
            if case .code = block { continue }
            let text = InlineMarkup.plain(block.searchText)
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: ". ")
    }

    private func exportPDF() {
        let data = LessonExport.pdfData(courseTitle: course.title, lesson: lesson)
        if let url = try? LessonExport.temporaryFile(named: InlineMarkup.plain(lesson.title), extension: "pdf", data: data) {
            shareFile = ShareFile(url: url)
        } else {
            exportFailed = true
        }
    }

    @ViewBuilder
    private var footer: some View {
        let done = progress.isLessonDone(course.id, lesson.id)
        VStack(spacing: 10) {
            Button {
                progress.setLessonDone(course.id, lesson.id, !done)
            } label: {
                Label(done ? "Completed" : "Mark as complete", systemImage: done ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(done ? .green : tint)
            .sensoryFeedback(.success, trigger: done)

            if let next = course.lesson(after: lesson.id) {
                NavigationLink(value: Route.lesson(courseId: course.id, lessonId: next.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next").font(.caption).foregroundStyle(.secondary)
                            MarkupText(next.title).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            } else if !course.questions.isEmpty {
                NavigationLink(value: Route.flashcards(courseId: course.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Course finished").font(.caption).foregroundStyle(.secondary)
                            Text("Practise with flashcards").font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }
}

/// One block with its highlight, its note, and the menu that edits them.
private struct AnnotatedBlock: View {
    let courseId: String
    let lessonId: String
    let index: Int
    let block: Block
    let tint: Color
    let onNote: () -> Void
    let onAsk: () -> Void

    @Environment(AnnotationStore.self) private var reading

    private func highlightColor(_ on: Bool) -> Color {
        on ? Color.yellow.opacity(0.3) : Color.clear
    }

    var body: some View {
        let item = reading.annotation(courseId, lessonId, index)
        let highlighted = item?.highlighted ?? false
        let note = item?.note ?? ""
        VStack(alignment: .leading, spacing: 6) {
            BlockView(block: block, tint: tint)
                .environment(\.blockIndex, index)
                .padding(highlighted ? 6 : 0)
                .background(highlightColor(highlighted), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if !note.isEmpty {
                Button(action: onNote) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "note.text")
                        Text(note).italic().multilineTextAlignment(.leading)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your note: \(note)")
            }
        }
        .contextMenu {
            if block.isAnnotatable {
                Button {
                    reading.toggleHighlight(courseId, lessonId, index, excerpt: block.excerpt)
                } label: {
                    Label(highlighted ? "Remove highlight" : "Highlight", systemImage: "highlighter")
                }
                Button(action: onNote) {
                    Label(note.isEmpty ? "Add note" : "Edit note", systemImage: "note.text")
                }
                Button(action: onAsk) {
                    Label("Ask about this", systemImage: "sparkles")
                }
                Button {
                    UIPasteboard.general.string = InlineMarkup.plain(block.searchText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

private struct NoteEditor: View {
    let excerpt: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    private let hadNote: Bool

    init(excerpt: String, note: String, onSave: @escaping (String) -> Void) {
        self.excerpt = excerpt
        self.onSave = onSave
        self.hadNote = !note.isEmpty
        _text = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Passage") {
                    Text(excerpt).font(.footnote).foregroundStyle(.secondary).lineLimit(5)
                }
                Section("Your note") {
                    TextEditor(text: $text).frame(minHeight: 140)
                }
                if hadNote {
                    Section {
                        Button("Delete note", role: .destructive) {
                            onSave("")
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
    }
}
