import Foundation

enum HotKeyState: Equatable {
    case idle
    case pending(startTime: Date)
    case recording
    case transcribing
    case cancelled(reason: CancelReason)
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .pending, .recording:
            return true
        default:
            return false
        }
    }
    
    var shouldShowOverlay: Bool {
        switch self {
        case .recording:
            return true
        default:
            return false
        }
    }
}

enum CancelReason: Equatable {
    case otherKeyPressed(keyCode: UInt32)
    case releasedTooSoon(duration: TimeInterval)
    case modifierCombo(modifiers: String)
    case eventTapDisabled
    
    var description: String {
        switch self {
        case .otherKeyPressed:
            return "检测到组合键"
        case .releasedTooSoon(let duration):
            return "按键时间太短 (\(String(format: "%.1f", duration))s)"
        case .modifierCombo:
            return "检测到修饰键组合"
        case .eventTapDisabled:
            return "系统事件被禁用"
        }
    }
}
