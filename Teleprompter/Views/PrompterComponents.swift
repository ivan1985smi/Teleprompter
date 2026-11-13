import SwiftUI
import UIKit

struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 22
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isActive ? Color.orange : Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ReadingGuideView: View {
    let position: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            HStack {
                Capsule()
                    .fill(color.opacity(0.55))
                    .frame(width: 24, height: 4)
                Spacer()
                Capsule()
                    .fill(color.opacity(0.55))
                    .frame(width: 24, height: 4)
            }
            .padding(.horizontal, 8)
            .position(x: proxy.size.width / 2, y: proxy.size.height * CGFloat(position))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CountdownOverlay: View {
    let number: Int
    let color: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("\(number)")
                    .font(.system(size: 128, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: number)

                Text("Нажмите на экран, чтобы отменить")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .transition(.opacity)
        .allowsHitTesting(false)
        .accessibilityLabel("Обратный отсчёт: \(number)")
    }
}

struct FeedbackToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

struct KeyPressCaptureView: UIViewRepresentable {
    let remote: RemoteInputManager

    func makeUIView(context: Context) -> ResponderCaptureUIView {
        let view = ResponderCaptureUIView()
        view.onKeyCode = { code in
            Task { @MainActor in
                remote.handleExternalHIDKey(code: code)
            }
        }
        return view
    }

    func updateUIView(_ uiView: ResponderCaptureUIView, context: Context) {
        uiView.onKeyCode = { code in
            Task { @MainActor in
                remote.handleExternalHIDKey(code: code)
            }
        }
        if uiView.window != nil && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    final class ResponderCaptureUIView: UIView {
        var onKeyCode: ((Int) -> Void)?

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                DispatchQueue.main.async { [weak self] in
                    self?.becomeFirstResponder()
                }
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                if let key = press.key {
                    onKeyCode?(Int(key.keyCode.rawValue))
                    handled = true
                }
            }
            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }
    }
}