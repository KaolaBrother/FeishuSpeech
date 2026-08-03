import SwiftUI

enum RecordingState: Equatable {
    case idle
    case streaming
    case finalOnly
    case sealing
    case manualRecoveryCopied
    case emptyFinalPreservedPartial
    case provisionalOutputPreserved
    // Compatibility-only states for the retired whole-file flow.
    case recording
    case transcribing
    case error(String)

    var isCompletionFeedback: Bool {
        switch self {
        case .manualRecoveryCopied, .emptyFinalPreservedPartial, .provisionalOutputPreserved:
            return true
        default:
            return false
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "waveform.circle"
        case .streaming: return "mic.circle.fill"
        case .finalOnly: return "mic.badge.ellipsis"
        case .sealing: return "ellipsis.circle.fill"
        case .manualRecoveryCopied: return "doc.on.clipboard.fill"
        case .emptyFinalPreservedPartial: return "text.badge.checkmark"
        case .provisionalOutputPreserved: return "text.badge.checkmark"
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle"
        case .error: return "exclamationmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .streaming: return .red
        case .finalOnly: return .orange
        case .sealing: return .orange
        case .manualRecoveryCopied: return .orange
        case .emptyFinalPreservedPartial: return .secondary
        case .provisionalOutputPreserved: return .secondary
        case .recording: return .red
        case .transcribing: return .orange
        case .error: return .red
        }
    }
    
    var text: String {
        switch self {
        case .idle: return "就绪"
        case .streaming: return "正在聆听…"
        case .finalOnly: return "正在聆听，松开后输入…"
        case .sealing: return "正在完成识别…"
        case .manualRecoveryCopied: return "识别结果已复制，请手动粘贴"
        case .emptyFinalPreservedPartial: return "未返回最终文本，已保留已显示内容"
        case .provisionalOutputPreserved: return "已保留已输入内容"
        case .recording: return "录音中..."
        case .transcribing: return "识别中..."
        case .error(let msg): return msg
        }
    }
}
