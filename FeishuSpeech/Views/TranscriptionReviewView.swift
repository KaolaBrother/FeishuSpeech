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
            TextEditor(text: Binding(
                get: { draftText },
                set: { newValue in
                    draftText = newValue
                    onDraftChange?(newValue)
                }
            ))
            .font(.body)
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
                    guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return
                    }
                    onConfirm?()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
