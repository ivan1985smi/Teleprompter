import SwiftUI
import UIKit
import Combine

final class PrompterContainerView: UIView {
    let textView: UITextView
    let voicePillButton: UIButton = UIButton(type: .system)
    var onLayoutMetricsChanged: (() -> Void)?
    var onToggleVoiceFollow: (() -> Void)?

    private var lastBoundsSize: CGSize = .zero
    private var lastSafeArea: UIEdgeInsets = .zero

    override init(frame: CGRect) {
        if #available(iOS 16.0, *) {
            self.textView = UITextView(usingTextLayoutManager: false)
        } else {
            self.textView = UITextView(frame: .zero)
        }
        super.init(frame: frame)

        backgroundColor = .clear
        isOpaque = false

        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = false
        textView.clipsToBounds = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainer.lineFragmentPadding = 0
        textView.layoutManager.allowsNonContiguousLayout = false

        addSubview(textView)
        setupVoicePillButton()
    }

    private func setupVoicePillButton() {
        voicePillButton.backgroundColor = UIColor(white: 0.14, alpha: 0.86)
        voicePillButton.layer.cornerRadius = 17
        voicePillButton.layer.cornerCurve = .continuous
        voicePillButton.layer.borderWidth = 1
        voicePillButton.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        voicePillButton.tintColor = .white
        voicePillButton.setTitleColor(.white, for: .normal)
        voicePillButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        voicePillButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 13, bottom: 7, right: 13)
        voicePillButton.setTitle("🎙 Голос: Выкл", for: .normal)
        voicePillButton.addTarget(self, action: #selector(handleVoiceButtonTap), for: .touchUpInside)
        addSubview(voicePillButton)
    }

    @objc private func handleVoiceButtonTap() {
        onToggleVoiceFollow?()
    }

    func updateVoicePillState(active: Bool, statusText: String, level: Float) {
        let title = active ? "🟢 🎙 \(statusText)" : "🎙 \(statusText)"
        voicePillButton.setTitle(title, for: .normal)

        if active {
            let pulseAlpha = CGFloat(0.28 + min(max(level, 0), 1) * 0.42)
            voicePillButton.backgroundColor = UIColor.systemOrange.withAlphaComponent(pulseAlpha)
            voicePillButton.layer.borderColor = UIColor.systemOrange.cgColor
        } else {
            voicePillButton.backgroundColor = UIColor(white: 0.14, alpha: 0.86)
            voicePillButton.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        }
        setNeedsLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if textView.frame != bounds {
            textView.frame = bounds
        }

        voicePillButton.sizeToFit()
        let pillWidth = min(max(voicePillButton.bounds.width, 136), bounds.width - 32)
        let pillHeight: CGFloat = 34
        let rightMargin = max(16, safeAreaInsets.right + 12)
        let topY = safeAreaInsets.top + 64
        // Если контейнер отзеркален, размещаем кнопку у противоположного края, чтобы на экране она всегда была справа
        let isMirrored = transform.a < 0
        let pillX = isMirrored ? rightMargin : (bounds.width - pillWidth - rightMargin)
        voicePillButton.frame = CGRect(x: pillX, y: topY, width: pillWidth, height: pillHeight)

        if bounds.size != lastBoundsSize || safeAreaInsets != lastSafeArea {
            lastBoundsSize = bounds.size
            lastSafeArea = safeAreaInsets
            onLayoutMetricsChanged?()
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        if safeAreaInsets != lastSafeArea {
            lastSafeArea = safeAreaInsets
            onLayoutMetricsChanged?()
        }
    }
}

struct PrompterScrollView: UIViewRepresentable {
    let text: String
    let settings: PrompterSettings
    @ObservedObject var engine: ScrollEngine

    init(text: String, settings: PrompterSettings, engine: ScrollEngine) {
        self.text = text
        self.settings = settings
        self.engine = engine
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    func makeUIView(context: Context) -> PrompterContainerView {
        let container = PrompterContainerView(frame: .zero)
        let coordinator = context.coordinator

        container.textView.delegate = coordinator
        coordinator.containerView = container
        coordinator.textView = container.textView

        container.onLayoutMetricsChanged = { [weak coordinator] in
            coordinator?.recalculateLayoutMetrics()
        }
        container.onToggleVoiceFollow = { [weak coordinator] in
            coordinator?.engine.toggleVoiceFollow()
        }

        coordinator.bindVoiceUpdates()
        coordinator.apply(text: text, settings: settings, force: true)
        engine.attach(coordinator)
        return container
    }

    func updateUIView(_ container: PrompterContainerView, context: Context) {
        context.coordinator.engine = engine
        context.coordinator.containerView = container
        context.coordinator.textView = container.textView
        context.coordinator.apply(text: text, settings: settings, force: false)
        engine.attach(context.coordinator)
    }

    static func dismantleUIView(_ container: PrompterContainerView, coordinator: Coordinator) {
        container.onLayoutMetricsChanged = nil
        container.onToggleVoiceFollow = nil
        container.textView.delegate = nil
        coordinator.cancellables.removeAll()
        coordinator.engine.detach(coordinator)
    }

    final class Coordinator: NSObject, UITextViewDelegate, PrompterScrollSurface {
        var engine: ScrollEngine
        weak var containerView: PrompterContainerView?
        weak var textView: UITextView?

        private var lastText: String = ""
        private var lastSettings: PrompterSettings?
        private var isProgrammaticScroll: Bool = false
        var cancellables = Set<AnyCancellable>()

        init(engine: ScrollEngine) {
            self.engine = engine
        }

        func bindVoiceUpdates() {
            cancellables.removeAll()
            Publishers.CombineLatest3(
                engine.$isVoiceFollowActive,
                engine.$voiceStatusText,
                engine.$voiceAudioLevel
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active, status, level in
                self?.containerView?.updateVoicePillState(active: active, statusText: status, level: level)
            }
            .store(in: &cancellables)
        }

        func apply(text: String, settings: PrompterSettings, force: Bool) {
            guard let textView, let containerView else { return }

            var normalized = settings
            normalized.normalize()

            let textChanged = force || (text != lastText)
            let settingsChanged = force || (normalized != lastSettings)

            if textChanged || settingsChanged {
                let savedOffsetY = textView.contentOffset.y

                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = CGFloat(normalized.lineSpacing)
                paragraph.alignment = normalized.textAlignment.nsTextAlignment
                paragraph.lineBreakMode = .byWordWrapping

                let font = UIFont.systemFont(ofSize: CGFloat(normalized.fontSize), weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: normalized.textColor.uiColor,
                    .paragraphStyle: paragraph
                ]

                let displayString = text.isEmpty ? " " : text
                isProgrammaticScroll = true
                textView.attributedText = NSAttributedString(string: displayString, attributes: attributes)
                textView.layoutManager.allowsNonContiguousLayout = false
                textView.layoutManager.ensureLayout(for: textView.textContainer)
                isProgrammaticScroll = false

                lastText = text
                lastSettings = normalized

                applyMirrorTransform(mirrored: normalized.mirrored, to: containerView)
                recalculateLayoutMetrics()
                displayScrollPosition(savedOffsetY)
            } else {
                applyMirrorTransform(mirrored: normalized.mirrored, to: containerView)
            }
        }

        private func applyMirrorTransform(mirrored: Bool, to containerView: PrompterContainerView) {
            let mirrorTransform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
            if containerView.transform != mirrorTransform {
                containerView.transform = mirrorTransform
                containerView.voicePillButton.transform = mirrorTransform
                containerView.setNeedsLayout()
            }
        }

        func recalculateLayoutMetrics() {
            guard let textView, let containerView else { return }
            let bounds = containerView.bounds
            guard bounds.width > 10, bounds.height > 10 else { return }

            let settings = lastSettings ?? PrompterSettings()
            let safeInsets = containerView.safeAreaInsets
            let horizontalInset = max(20, safeInsets.left, safeInsets.right) + 16

            let readingRatio = CGFloat(min(max(settings.readingPosition, 0.15), 0.85))
            let topAnchor = max(bounds.height * readingRatio, safeInsets.top + 72)
            let bottomPadding = max(bounds.height * (1.0 - readingRatio) + 80, safeInsets.bottom + 140)

            let targetContainerInset = UIEdgeInsets(
                top: topAnchor,
                left: horizontalInset,
                bottom: bottomPadding,
                right: horizontalInset
            )

            if textView.textContainerInset != targetContainerInset {
                isProgrammaticScroll = true
                textView.textContainerInset = targetContainerInset
                isProgrammaticScroll = false
            }

            let targetWidth = max(10, bounds.width - targetContainerInset.left - targetContainerInset.right)
            if abs(textView.textContainer.size.width - targetWidth) > 0.5 {
                textView.textContainer.size = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
            }

            textView.layoutManager.ensureLayout(for: textView.textContainer)
            textView.layoutIfNeeded()

            let usedRect = textView.layoutManager.usedRect(for: textView.textContainer)
            let totalContentHeight = ceil(usedRect.height + targetContainerInset.top + targetContainerInset.bottom)
            let maxScroll = max(1, totalContentHeight - bounds.height)

            engine.updateMetrics(maxPosition: maxScroll, viewportHeight: bounds.height)
            rebuildVoiceWordAnchors(in: textView, maxScroll: maxScroll)
        }

        private func rebuildVoiceWordAnchors(in textView: UITextView, maxScroll: CGFloat) {
            let nsString = (textView.text ?? "") as NSString
            guard nsString.length > 0 else {
                engine.updateVoiceAnchors([])
                return
            }

            var anchors: [VoiceWordAnchor] = []
            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer

            nsString.enumerateSubstrings(
                in: NSRange(location: 0, length: nsString.length),
                options: [.byWords]
            ) { substring, wordRange, _, _ in
                guard let substring else { return }
                let norm = ScrollEngine.normalizeRussianWord(substring)
                guard !norm.isEmpty else { return }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: wordRange, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let targetY = min(max(0, rect.minY), maxScroll)

                let anchor = VoiceWordAnchor(
                    index: anchors.count,
                    normalizedWord: norm,
                    stem: ScrollEngine.russianStem(for: norm),
                    charRange: wordRange,
                    targetScrollY: targetY
                )
                anchors.append(anchor)
            }

            engine.updateVoiceAnchors(anchors)
        }

        func displayScrollPosition(_ position: CGFloat) {
            guard let textView else { return }
            isProgrammaticScroll = true
            let clampedY = max(0, position)
            if abs(textView.contentOffset.y - clampedY) > 0.05 {
                textView.contentOffset = CGPoint(x: 0, y: clampedY)
                textView.setNeedsDisplay()
            }
            isProgrammaticScroll = false
        }

        func setManualScrollingEnabled(_ enabled: Bool) {
            textView?.isScrollEnabled = true
            textView?.panGestureRecognizer.isEnabled = enabled || engine.isVoiceFollowActive
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if engine.isPlaying && !engine.isVoiceFollowActive {
                engine.pause()
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll,
                  scrollView.isDragging || scrollView.isDecelerating else { return }
            engine.updateFromManualScroll(scrollView.contentOffset.y)
        }
    }
}
