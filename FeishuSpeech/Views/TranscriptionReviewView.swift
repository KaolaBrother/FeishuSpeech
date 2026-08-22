import SwiftUI

import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "TranscriptionReviewView"
)

struct TranscriptionReviewView: View {
    let state: TranscriptionReviewState
    let onDraftChange: (@MainActor (String) -> Void)?
    let onConfirm: (@MainActor () -> Void)?
    let onDiscard: (@MainActor () -> Void)?

    init(
        state: TranscriptionReviewState,
        onDraftChange: (@MainActor (String) -> Void)? = nil,
        onConfirm: (@MainActor () -> Void)? = nil,
        onDiscard: (@MainActor () -> Void)? = nil
    ) {
        self.state = state
        self.onDraftChange = onDraftChange
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            EmptyView()
        case .streaming(let preview):
            readOnlyContent(
                preview: preview,
                status: "正在聆听…"
            )
        case .sealing(let preview):
            readOnlyContent(
                preview: preview,
                status: "正在完成识别…"
            )
        case .editable(let draft, let isPossiblyIncomplete):
            editableContent(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete
            )
        case .confirming:
            EmptyView()
        }
    }

    private func readOnlyContent(preview: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(preview.isEmpty ? status : preview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !preview.isEmpty {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func editableContent(
        draft: String,
        isPossiblyIncomplete: Bool
    ) -> some View {
        EditableDraftView(
            initialDraft: draft,
            isPossiblyIncomplete: isPossiblyIncomplete,
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onDiscard: onDiscard
        )
    }
}

private struct EditableDraftView: View {
    let isPossiblyIncomplete: Bool
    let onDraftChange: (@MainActor (String) -> Void)?
    let onConfirm: (@MainActor () -> Void)?
    let onDiscard: (@MainActor () -> Void)?

    @State private var draftText: String

    init(
        initialDraft: String,
        isPossiblyIncomplete: Bool,
        onDraftChange: (@MainActor (String) -> Void)?,
        onConfirm: (@MainActor () -> Void)?,
        onDiscard: (@MainActor () -> Void)?
    ) {
        self.isPossiblyIncomplete = isPossiblyIncomplete
        self.onDraftChange = onDraftChange
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        _draftText = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReviewDraftTextEditor(
                text: draftText,
                onTextChange: { newValue in
                    draftText = newValue
                    onDraftChange?(newValue)
                },
                onConfirm: confirmDraft
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isPossiblyIncomplete {
                Text("可能不完整")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()

                Button("取消", role: .cancel) {
                    onDiscard?()
                }
                .keyboardShortcut(.cancelAction)

                Button("输入") {
                    confirmDraft()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func confirmDraft() {
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        onConfirm?()
    }
}

private struct ReviewDraftTextEditor: NSViewRepresentable {
    let text: String
    let onTextChange: @MainActor (String) -> Void
    let onConfirm: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTextChange: onTextChange,
            onConfirm: onConfirm
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ReviewDraftTextView()
        textView.delegate = context.coordinator
        textView.onConfirm = { [weak coordinator = context.coordinator] in
            coordinator?.confirm()
        }
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onConfirm = onConfirm

        guard let textView = scrollView.documentView as? ReviewDraftTextView,
              !textView.hasMarkedText(),
              textView.string != text else {
            return
        }

        let selectedRange = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(
            NSRange(
                location: min(selectedRange.location, textView.string.utf16.count),
                length: 0
            )
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: @MainActor (String) -> Void
        var onConfirm: @MainActor () -> Void

        init(
            onTextChange: @escaping @MainActor (String) -> Void,
            onConfirm: @escaping @MainActor () -> Void
        ) {
            self.onTextChange = onTextChange
            self.onConfirm = onConfirm
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onTextChange(textView.string)
        }

        func confirm() {
            onConfirm()
        }
    }
}

private final class ReviewDraftTextView: NSTextView {
    var onConfirm: (@MainActor () -> Void)?

    override func keyDown(with event: NSEvent) {
        guard isReturnEvent(event), !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasUnsupportedModifier = modifiers.contains(.option) || modifiers.contains(.control)
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)

        guard !hasUnsupportedModifier, hasCommand || !hasShift else {
            super.keyDown(with: event)
            return
        }

        onConfirm?()
    }

    private func isReturnEvent(_ event: NSEvent) -> Bool {
        event.keyCode == 36 || event.keyCode == 76
    }
}
