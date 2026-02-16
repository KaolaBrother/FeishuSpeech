import SwiftUI

enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case error(String)
    
    var icon: String {
        switch self {
        case .idle: return "waveform.circle"
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle"
        case .error: return "exclamationmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .recording: return .red
        case .transcribing: return .orange
        case .error: return .red
        }
    }
    
    var text: String {
        switch self {
        case .idle: return "就绪"
        case .recording: return "录音中..."
        case .transcribing: return "识别中..."
        case .error(let msg): return msg
        }
    }
}
