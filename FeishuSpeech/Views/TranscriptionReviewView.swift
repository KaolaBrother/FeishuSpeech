import SwiftUI

import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "TranscriptionReviewView"
)

enum TranscriptionReviewTypography {
    static let transcriptFontSize: CGFloat = 18
}

struct TranscriptionReviewView: View {
    let state: TranscriptionReviewState
    let readOnlyRecovery: Bool
    let onDraftChange: (@MainActor (String) -> Void)?
    let onConfirm: (@MainActor () -> Void)?
    let onDiscard: (@MainActor () -> Void)?

    init(
        state: TranscriptionReviewState,
        readOnlyRecovery: Bool = false,
        onDraftChange: (@MainActor (String) -> Void)? = nil,
        onConfirm: (@MainActor () -> Void)? = nil,
        onDiscard: (@MainActor () -> Void)? = nil
    ) {
        self.state = state
        self.readOnlyRecovery = readOnlyRecovery
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
                status: readOnlyRecovery ? "识别未完成；仅供查看" : "正在完成识别…",
                isPossiblyIncomplete: readOnlyRecovery
            )
        case .editable(let draft, let isPossiblyIncomplete, let feedback):
            editableContent(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: feedback,
                isEditable: true,
                canConfirm: true
            )
        case .confirming(let draft, let isPossiblyIncomplete):
            VStack(alignment: .leading, spacing: 12) {
                editableContent(
                    draft: draft,
                    isPossiblyIncomplete: isPossiblyIncomplete,
                    feedback: nil,
                    isEditable: false,
                    canConfirm: false
                )

                Text("正在发送…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .preparingSubmission(let draft, let isPossiblyIncomplete, let feedback):
            submissionStatusContent(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: feedback,
                status: "正在准备发送…"
            )
        case .submittedUnverifiedTerminal(let draft, let isPossiblyIncomplete, let feedback):
            submissionStatusContent(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: feedback,
                status: "输入状态不确定；请检查目标应用。"
            )
        }
    }

    private func submissionStatusContent(
        draft: String,
        isPossiblyIncomplete: Bool,
        feedback: ReviewDraftFeedback?,
        status: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            editableContent(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: feedback,
                isEditable: false,
                canConfirm: false
            )
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func readOnlyContent(
        preview: String,
        status: String,
        isPossiblyIncomplete: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                if preview.isEmpty {
                    Text(status)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    Text(preview)
                        .font(.system(size: TranscriptionReviewTypography.transcriptFontSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !preview.isEmpty {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if isPossiblyIncomplete {
                Text("识别结果尚未确认")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func editableContent(
        draft: String,
        isPossiblyIncomplete: Bool,
        feedback: ReviewDraftFeedback?,
        isEditable: Bool,
        canConfirm: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EditableDraftView(
                initialDraft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                isEditable: isEditable,
                canConfirm: canConfirm,
                onDraftChange: isEditable ? onDraftChange : nil,
                onConfirm: canConfirm ? onConfirm : nil,
                onDiscard: isEditable ? onDiscard : nil
            )

            if let feedbackText = feedbackText(for: feedback) {
                Text(feedbackText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feedbackText(for feedback: ReviewDraftFeedback?) -> String? {
        switch feedback {
        case .activationFailed:
            return "无法激活目标应用；请确认后再发送。"
        case .destinationChanged:
            return "目标已变化；请检查草稿后发送。"
        case .securityRejected:
            return "目标安全状态不允许输入。"
        case .unsafeText:
            return "草稿包含不安全字符，请修改后发送。"
        case .deliveryFailed:
            return "输入失败；草稿已保留，请编辑后显式发送。"
        case .deliveryUncertain:
            return "输入状态不确定；再次发送可能造成重复输入。"
        case .deliveryCancelled:
            return "输入已取消；草稿已保留。"
        case .draftTooLong:
            return "草稿过长，请缩短后发送。"
        case nil:
            return nil
        }
    }
}

private struct EditableDraftView: View {
    let isPossiblyIncomplete: Bool
    let isEditable: Bool
    let canConfirm: Bool
    let onDraftChange: (@MainActor (String) -> Void)?
    let onConfirm: (@MainActor () -> Void)?
    let onDiscard: (@MainActor () -> Void)?

    @State private var draftText: String

    init(
        initialDraft: String,
        isPossiblyIncomplete: Bool,
        isEditable: Bool,
        canConfirm: Bool,
        onDraftChange: (@MainActor (String) -> Void)?,
        onConfirm: (@MainActor () -> Void)?,
        onDiscard: (@MainActor () -> Void)?
    ) {
        self.isPossiblyIncomplete = isPossiblyIncomplete
        self.isEditable = isEditable
        self.canConfirm = canConfirm
        self.onDraftChange = onDraftChange
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        _draftText = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReviewDraftTextEditor(
                text: draftText,
                isEditable: isEditable,
                onTextChange: { newValue in
                    guard isEditable else { return }
                    draftText = newValue
                    onDraftChange?(newValue)
                }
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
                .disabled(!isEditable)

                if canConfirm {
                    Button("发送") {
                    confirmDraft()
                    }
                    .disabled(
                        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }

    private func confirmDraft() {
        guard canConfirm else { return }
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        onConfirm?()
    }
}

private struct ReviewDraftTextEditor: NSViewRepresentable {
    let text: String
    let isEditable: Bool
    let onTextChange: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ReviewDraftTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(
            ofSize: TranscriptionReviewTypography.transcriptFontSize
        )
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
        (scrollView.documentView as? ReviewDraftTextView)?.isEditable = isEditable

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

        init(onTextChange: @escaping @MainActor (String) -> Void) {
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onTextChange(textView.string)
        }
    }
}

private final class ReviewDraftTextView: NSTextView {}
