import AVFoundation
import SwiftUI
import UIKit

/// Text size, spacing, width, theme and code wrapping. Changes apply to the lesson behind the sheet at once.
struct ReadingSettingsSheet: View {
    @AppStorage(ReadingKeys.textStep) private var textStep = 0
    @AppStorage(ReadingKeys.lineSpacing) private var lineSpacing = ReadingLineSpacing.normal
    @AppStorage(ReadingKeys.width) private var width = ReadingWidth.normal
    @AppStorage(ReadingKeys.theme) private var theme = ReadingTheme.system
    @AppStorage(ReadingKeys.codeWrap) private var codeWrap = false
    @Environment(\.dismiss) private var dismiss

    private var sizeText: String {
        if textStep == 0 { return "Default" }
        return textStep > 0 ? "+\(textStep)" : "\(textStep)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    Stepper(value: $textStep, in: ReadingStyle.stepRange) {
                        LabeledContent("Text size", value: sizeText)
                    }
                    Picker("Line spacing", selection: $lineSpacing) {
                        ForEach(ReadingLineSpacing.allCases) { choice in Text(choice.title).tag(choice) }
                    }
                    Picker("Margins", selection: $width) {
                        ForEach(ReadingWidth.allCases) { choice in Text(choice.title).tag(choice) }
                    }
                }
                Section("Theme") {
                    Picker("Theme", selection: $theme) {
                        ForEach(ReadingTheme.allCases) { choice in Text(choice.title).tag(choice) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Code") {
                    Toggle("Wrap long lines", isOn: $codeWrap)
                }
                Section {
                    Button("Reset to defaults") {
                        textStep = 0
                        lineSpacing = .normal
                        width = .normal
                        theme = .system
                        codeWrap = false
                    }
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Code on its own screen, scrollable both ways, in a larger font.
struct CodeFullScreen: View {
    let block: CodeBlock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(SwiftHighlighter.attributed(block.code))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding()
            }
            .navigationTitle(block.caption ?? block.language)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = block.code
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy code")
                }
            }
        }
    }
}

/// Reads a lesson aloud with the system voice.
final class LessonSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(text: String) {
        if synthesizer.isSpeaking {
            stop()
        } else {
            synthesizer.speak(AVSpeechUtterance(string: text))
            isSpeaking = true
        }
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}

struct ShareFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
