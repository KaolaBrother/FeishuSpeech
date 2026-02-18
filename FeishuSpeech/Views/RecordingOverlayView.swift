import SwiftUI

struct RecordingOverlayView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
            
            Text("🎤 可以开始说话...")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview {
    RecordingOverlayView()
        .frame(width: 300, height: 120)
        .background(Color.gray.opacity(0.3))
}
