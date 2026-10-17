import AppKit
import SwiftUI
import NMapMacCore

/// Live, highlighted Nmap output for the selected scan (ScanNmapOutputPage.py).
struct OutputTab: View {
    @Bindable var session: ScanSession

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("Scan", selection: Binding(
                    get: { session.selectedJob?.id },
                    set: { session.selectedJobID = $0 })
                ) {
                    ForEach(session.jobs) { job in
                        Text(label(for: job)).tag(Optional(job.id))
                    }
                }
                .frame(maxWidth: 520)
                .disabled(session.jobs.isEmpty)
                Spacer()
                if let job = session.selectedJob, job.isRunning {
                    ProgressView().controlSize(.small)
                    Text(job.progress.map { "\(Int($0 * 100))%" } ?? "Scanning…")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Cancel") { job.cancel() }
                }
                Button {
                    session.runSavePanel()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(session.selectedJob?.result == nil || session.selectedJob?.isRunning == true)
            }
            .padding(.top, 8)

            if let job = session.selectedJob {
                NmapOutputView(text: job.output)
            } else {
                EmptyState(title: "No scans", systemImage: "network",
                           message: "Enter a target and choose Scan, or open saved scan results with ⌘O.")
            }
        }
    }

    private func label(for job: ScanJob) -> String {
        let status = job.status == .finished || job.status == .loaded ? "" : " — \(job.status.label)"
        return job.command + status
    }
}

/// A read-only NSTextView that appends output incrementally and applies
/// Zenmap's highlighting rules (UmitConf.NmapOutputHighlight).
struct NmapOutputView: NSViewRepresentable {
    var text: String
    @AppStorage("highlightOutput") private var highlight = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = OutputHighlighter.baseFont
        scroll.borderType = .bezelBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        let coordinator = context.coordinator
        let atBottom = scroll.contentView.bounds.maxY >= textView.bounds.maxY - 20

        if coordinator.highlight != highlight || !text.hasPrefix(coordinator.rendered) {
            storage.setAttributedString(NSAttributedString(string: text, attributes: OutputHighlighter.plain))
            if highlight { OutputHighlighter.apply(to: storage, in: NSRange(location: 0, length: storage.length)) }
        } else if text.count > coordinator.rendered.count {
            let delta = String(text.dropFirst(coordinator.rendered.count))
            let previousLength = storage.length
            storage.append(NSAttributedString(string: delta, attributes: OutputHighlighter.plain))
            if highlight {
                // Re-highlight from the start of the line the old text ended on.
                let ns = storage.string as NSString
                let lineStart = ns.lineRange(for: NSRange(location: max(previousLength - 1, 0), length: 0)).location
                OutputHighlighter.apply(to: storage, in: NSRange(location: lineStart, length: storage.length - lineStart))
            }
        } else {
            return
        }
        coordinator.rendered = text
        coordinator.highlight = highlight
        if atBottom { textView.scrollToEndOfDocument(nil) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var rendered = ""
        var highlight = true
    }
}

enum OutputHighlighter {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    static var plain: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor]
    }

    struct Rule {
        var regex: NSRegularExpression
        var bold = false
        var italic = false
        var underline = false
        var color: NSColor = .textColor
    }

    // Applied in order; later rules override earlier ones, as in Zenmap.
    static let rules: [Rule] = {
        func re(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
        return [
            Rule(regex: re(#"\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}\s.{1,4}"#), bold: true),
            Rule(regex: re(#"(\w{2,}://)*[\w-]{2,}\.[\w-]{2,}(\.[\w-]{2,})*"#),
                 bold: true, italic: true, underline: true, color: .systemBlue),
            Rule(regex: re(#"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#), bold: true),
            Rule(regex: re(#"PORT\s+STATE\s+SERVICE(\s+VERSION)?[^\n]*"#), bold: true, color: .systemIndigo),
            Rule(regex: re(#"\d{1,5}/.{1,5}\s+open\s+.*"#), bold: true, color: .systemGreen),
            Rule(regex: re(#"\d{1,5}/.{1,5}\s+closed\s+.*"#), color: .systemRed),
            Rule(regex: re(#"\d{1,5}/.{1,5}\s+filtered\s+.*"#), color: .systemOrange),
            Rule(regex: re(#"^(\w{2,}[\s]{0,3}){0,4}:"#), bold: true, underline: true),
        ]
    }()

    static func font(bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    static func apply(to storage: NSTextStorage, in range: NSRange) {
        storage.beginEditing()
        storage.setAttributes(plain, range: range)
        for rule in rules {
            let font = font(bold: rule.bold, italic: rule.italic)
            rule.regex.enumerateMatches(in: storage.string, range: range) { match, _, _ in
                guard let r = match?.range, r.length > 0 else { return }
                storage.setAttributes([
                    .font: font,
                    .foregroundColor: rule.color,
                    .underlineStyle: rule.underline ? NSUnderlineStyle.single.rawValue : 0,
                ], range: r)
            }
        }
        storage.endEditing()
    }
}
