import SwiftUI
import UIKit
import Combine
import Speech
import AVFoundation

private struct PrompterVoiceAnchor {
    let index: Int
    let normalizedWord: String
    let stem: String
    let charRange: NSRange
    let targetScrollY: CGFloat
}

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
        voicePillButton.backgroundColor = UIColor(white: 0.14, alpha: 0.88)
        voicePillButton.layer.cornerRadius = 17
        voicePillButton.layer.cornerCurve = .continuous
        voicePillButton.layer.borderWidth = 1
        voicePillButton.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
        voicePillButton.tintColor = .white
        voicePillButton.setTitleColor(.white, for: .normal)
        voicePillButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        voicePillButton.titleLabel?.lineBreakMode = .byTruncatingTail
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
            let pulseAlpha = CGFloat(0.30 + min(max(level, 0), 1) * 0.45)
            voicePillButton.backgroundColor = UIColor.systemOrange.withAlphaComponent(pulseAlpha)
            voicePillButton.layer.borderColor = UIColor.systemOrange.cgColor
        } else {
            voicePillButton.backgroundColor = UIColor(white: 0.14, alpha: 0.88)
            voicePillButton.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
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

        let labelWidth = voicePillButton.titleLabel?.intrinsicContentSize.width ?? 110
        let pillWidth = min(max(labelWidth + 28, 138), max(138, bounds.width - 32))
        let pillHeight: CGFloat = 34
        let rightMargin = max(16, safeAreaInsets.right + 12)
        let topY = safeAreaInsets.top + 64
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
            coordinator?.toggleVoiceFollow()
        }

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
        coordinator.stopVoiceFollow()
        coordinator.engine.detach(coordinator)
    }

    final class Coordinator: NSObject, UITextViewDelegate, PrompterScrollSurface {
        var engine: ScrollEngine
        weak var containerView: PrompterContainerView?
        weak var textView: UITextView?

        private var lastText: String = ""
        private var lastSettings: PrompterSettings?
        private var isProgrammaticScroll: Bool = false
        private var isInternalVoiceSeek: Bool = false

        // MARK: - Голосовой автоскролл (Voice-Follow)
        private var isVoiceFollowActive: Bool = false
        private var voiceStatusText: String = "Голос: Выкл"
        private var voiceAudioLevel: Float = 0

        private var voiceAnchors: [PrompterVoiceAnchor] = []
        private var currentAnchorIndex: Int = 0
        private var currentScrollY: CGFloat = 0
        private var voiceTargetY: CGFloat = 0
        private var maxScrollY: CGFloat = 1
        private var viewportHeight: CGFloat = 600

        private let audioEngine = AVAudioEngine()
        private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
        private var recognitionTask: SFSpeechRecognitionTask?
        private var voiceDisplayLink: CADisplayLink?
        private var lastFrameTimestamp: CFTimeInterval?

        private var lastVoiceActivityTime: CFTimeInterval = 0
        private var lastWordMatchTime: CFTimeInterval = 0
        private var sessionStartTime: CFTimeInterval = 0
        private var isRestartingSession: Bool = false

        init(engine: ScrollEngine) {
            self.engine = engine
            super.init()
        }

        deinit {
            stopVoiceFollow()
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

            self.maxScrollY = maxScroll
            self.viewportHeight = bounds.height

            engine.updateMetrics(maxPosition: maxScroll, viewportHeight: bounds.height)
            rebuildVoiceWordAnchors(in: textView, maxScroll: maxScroll)
        }

        private func rebuildVoiceWordAnchors(in textView: UITextView, maxScroll: CGFloat) {
            let nsString = (textView.text ?? "") as NSString
            guard nsString.length > 0 else {
                voiceAnchors = []
                currentAnchorIndex = 0
                return
            }

            var anchors: [PrompterVoiceAnchor] = []
            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer

            nsString.enumerateSubstrings(
                in: NSRange(location: 0, length: nsString.length),
                options: [.byWords]
            ) { substring, wordRange, _, _ in
                guard let substring else { return }
                let norm = Self.normalizeRussianWord(substring)
                guard !norm.isEmpty else { return }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: wordRange, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let targetY = min(max(0, rect.minY), maxScroll)

                let anchor = PrompterVoiceAnchor(
                    index: anchors.count,
                    normalizedWord: norm,
                    stem: Self.russianStem(for: norm),
                    charRange: wordRange,
                    targetScrollY: targetY
                )
                anchors.append(anchor)
            }

            voiceAnchors = anchors
            syncAnchorIndex(toScrollY: currentScrollY)
        }

        func displayScrollPosition(_ position: CGFloat) {
            guard let textView else { return }
            isProgrammaticScroll = true
            let clampedY = max(0, position)
            currentScrollY = clampedY
            if abs(textView.contentOffset.y - clampedY) > 0.05 {
                textView.contentOffset = CGPoint(x: 0, y: clampedY)
                textView.setNeedsDisplay()
            }
            isProgrammaticScroll = false

            // Если позицию сместили пультом или ползунком — синхронизируем голосовой прицел
            if isVoiceFollowActive && !isInternalVoiceSeek {
                voiceTargetY = clampedY
                syncAnchorIndex(toScrollY: clampedY)
            }
        }

        func setManualScrollingEnabled(_ enabled: Bool) {
            textView?.isScrollEnabled = true
            textView?.panGestureRecognizer.isEnabled = enabled || isVoiceFollowActive
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if engine.isPlaying {
                engine.pause()
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll,
                  scrollView.isDragging || scrollView.isDecelerating else { return }
            let offsetY = max(0, scrollView.contentOffset.y)
            currentScrollY = offsetY
            if isVoiceFollowActive {
                voiceTargetY = offsetY
                syncAnchorIndex(toScrollY: offsetY)
            }
            engine.updateFromManualScroll(offsetY)
        }

        // MARK: - Запуск и остановка голосового режима

        func toggleVoiceFollow() {
            if isVoiceFollowActive {
                stopVoiceFollow()
            } else {
                startVoiceFollow()
            }
        }

        private func refreshPillUI() {
            containerView?.updateVoicePillState(
                active: isVoiceFollowActive,
                statusText: voiceStatusText,
                level: voiceAudioLevel
            )
        }

        func startVoiceFollow() {
            guard !isVoiceFollowActive else { return }
            if engine.isPlaying {
                engine.pause()
            }
            voiceStatusText = "Проверка..."
            refreshPillUI()

            SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard authStatus == .authorized else {
                        self.voiceStatusText = "Нет доступа к речи"
                        self.isVoiceFollowActive = false
                        self.refreshPillUI()
                        return
                    }
                    self.requestMicrophoneAndStart()
                }
            }
        }

        private func requestMicrophoneAndStart() {
            let completion: (Bool) -> Void = { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted else {
                        self.voiceStatusText = "Микрофон запрещён"
                        self.isVoiceFollowActive = false
                        self.refreshPillUI()
                        return
                    }
                    self.launchVoiceSession()
                }
            }

            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission(completionHandler: completion)
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission(completion)
            }
        }

        private func launchVoiceSession() {
            stopAudioPipelinesOnly()

            if maxScrollY > 1 && currentScrollY >= maxScrollY - 2 {
                isInternalVoiceSeek = true
                engine.seek(to: CGFloat(0))
                isInternalVoiceSeek = false
                currentScrollY = 0
                voiceTargetY = 0
                currentAnchorIndex = 0
            } else {
                voiceTargetY = currentScrollY
                syncAnchorIndex(toScrollY: currentScrollY)
            }

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(
                    .playAndRecord,
                    mode: .measurement,
                    options: [.defaultToSpeaker, .mixWithOthers]
                )
                try session.setActive(true, options: .notifyOthersOnDeactivation)

                if speechRecognizer == nil {
                    speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
                }

                let inputNode = audioEngine.inputNode
                let format = inputNode.outputFormat(forBus: 0)
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    guard let self else { return }
                    self.recognitionRequest?.append(buffer)
                    self.analyzeMicrophoneBuffer(buffer)
                }

                audioEngine.prepare()
                try audioEngine.start()

                startRecognitionTask()
                startVoiceDisplayLink()

                isVoiceFollowActive = true
                textView?.panGestureRecognizer.isEnabled = true
                voiceStatusText = "Слушаю речь..."
                refreshPillUI()
            } catch {
                voiceStatusText = "Ошибка микрофона"
                isVoiceFollowActive = false
                refreshPillUI()
            }
        }

        private func startRecognitionTask() {
            recognitionTask?.cancel()
            recognitionTask = nil

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.recognitionRequest = request
            self.sessionStartTime = CACurrentMediaTime()

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self.handleRecognizedTranscript(transcript)
                    }
                }
                if error != nil || (result?.isFinal == true) {
                    DispatchQueue.main.async {
                        self.restartRecognitionTaskIfNeeded()
                    }
                }
            }
        }

        private func restartRecognitionTaskIfNeeded() {
            guard isVoiceFollowActive, !isRestartingSession, audioEngine.isRunning else { return }
            isRestartingSession = true
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                self.isRestartingSession = false
                if self.isVoiceFollowActive && self.audioEngine.isRunning {
                    self.startRecognitionTask()
                }
            }
        }

        func stopVoiceFollow() {
            isVoiceFollowActive = false
            voiceAudioLevel = 0
            voiceStatusText = "Голос: Выкл"
            stopVoiceDisplayLink()
            stopAudioPipelinesOnly()
            refreshPillUI()
        }

        private func stopAudioPipelinesOnly() {
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        private func startVoiceDisplayLink() {
            guard voiceDisplayLink == nil else { return }
            lastFrameTimestamp = nil
            let link = CADisplayLink(target: self, selector: #selector(handleVoiceFrame(_:)))
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            }
            link.add(to: .main, forMode: .common)
            voiceDisplayLink = link
        }

        private func stopVoiceDisplayLink() {
            voiceDisplayLink?.invalidate()
            voiceDisplayLink = nil
            lastFrameTimestamp = nil
        }

        @objc private func handleVoiceFrame(_ link: CADisplayLink) {
            guard isVoiceFollowActive else { return }
            if engine.isPlaying {
                engine.pause()
            }

            let now = link.timestamp
            let dt: CGFloat
            if let last = lastFrameTimestamp {
                dt = CGFloat(min(max(now - last, 1.0 / 240.0), 0.1))
            } else {
                dt = 1.0 / 60.0
            }
            lastFrameTimestamp = now

            let mediaNow = CACurrentMediaTime()
            let isSpeakingRecently = (mediaNow - lastVoiceActivityTime) < 0.38
            let matchedRecently = (mediaNow - lastWordMatchTime) < 0.90
            let diff = voiceTargetY - currentScrollY

            var nextY = currentScrollY
            var moved = false

            if abs(diff) > 0.6 && (isSpeakingRecently || matchedRecently) {
                let basePace = max(30.0, CGFloat(engine.speed))
                let velocity = min(max(diff * 3.6, -basePace * 1.8), basePace * 2.8)
                nextY += velocity * dt
                moved = true
            } else if isSpeakingRecently && diff >= -6 {
                let maxLead = min(maxScrollY, voiceTargetY + 62)
                if currentScrollY < maxLead {
                    nextY += CGFloat(engine.speed) * 0.44 * dt
                    moved = true
                }
            }

            if moved {
                let clamped = min(max(0, nextY), maxScrollY)
                if abs(clamped - currentScrollY) > 0.04 {
                    currentScrollY = clamped
                    isInternalVoiceSeek = true
                    engine.seek(to: clamped)
                    isInternalVoiceSeek = false
                }
            }
        }

        private func analyzeMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sum: Float = 0
            let step = max(1, frameLength / 128)
            var count = 0
            var idx = 0
            while idx < frameLength {
                let sample = channelData[idx]
                sum += sample * sample
                count += 1
                idx += step
            }
            let rms = sqrt(sum / Float(max(1, count)))
            let normalizedLevel = min(max((rms - 0.008) * 18.0, 0), 1)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVoiceFollowActive else { return }
                self.voiceAudioLevel = self.voiceAudioLevel * 0.65 + normalizedLevel * 0.35
                if normalizedLevel > 0.08 {
                    self.lastVoiceActivityTime = CACurrentMediaTime()
                }
                self.refreshPillUI()

                let now = CACurrentMediaTime()
                if now - self.sessionStartTime > 52.0 && (now - self.lastVoiceActivityTime > 0.4) {
                    self.restartRecognitionTaskIfNeeded()
                }
            }
        }

        // MARK: - Сопоставление русской речи со словами сценария

        private func handleRecognizedTranscript(_ transcript: String) {
            guard isVoiceFollowActive, !voiceAnchors.isEmpty else { return }

            let spokenTokens = Self.tokenizeRussian(transcript, maxTailWords: 6)
            guard let lastSpoken = spokenTokens.last else { return }

            let now = CACurrentMediaTime()
            lastVoiceActivityTime = now

            let prevSpoken1 = spokenTokens.count >= 2 ? spokenTokens[spokenTokens.count - 2] : nil
            let prevSpoken2 = spokenTokens.count >= 3 ? spokenTokens[spokenTokens.count - 3] : nil

            let minIdx = max(0, currentAnchorIndex - 2)
            let maxIdx = min(voiceAnchors.count - 1, currentAnchorIndex + 26)
            guard minIdx <= maxIdx else { return }

            var bestIndex: Int?
            var bestScore: Double = 0

            for idx in minIdx...maxIdx {
                let anchor = voiceAnchors[idx]
                let primarySim = Self.wordSimilarity(spoken: lastSpoken, anchor: anchor)
                guard primarySim >= 0.72 else { continue }

                let jump = idx - currentAnchorIndex

                var prevMatchSim: Double = 0
                if let prevSpoken1, idx >= 1 {
                    prevMatchSim = max(
                        Self.wordSimilarity(spoken: prevSpoken1, anchor: voiceAnchors[idx - 1]),
                        idx >= 2 ? Self.wordSimilarity(spoken: prevSpoken1, anchor: voiceAnchors[idx - 2]) * 0.9 : 0
                    )
                }

                if lastSpoken.norm.count <= 2 && jump > 2 && prevMatchSim < 0.75 {
                    continue
                }
                if jump > 9 && prevMatchSim < 0.72 && lastSpoken.norm.count < 7 {
                    continue
                }

                var prev2MatchSim: Double = 0
                if let prevSpoken2, idx >= 2 {
                    prev2MatchSim = Self.wordSimilarity(spoken: prevSpoken2, anchor: voiceAnchors[idx - 2])
                }

                let distancePenalty = abs(Double(jump - 1)) * 0.018
                let score = primarySim
                    + (prevMatchSim >= 0.72 ? prevMatchSim * 0.85 : 0)
                    + (prev2MatchSim >= 0.72 ? prev2MatchSim * 0.45 : 0)
                    - distancePenalty

                if score > bestScore {
                    bestScore = score
                    bestIndex = idx
                }
            }

            if let matchedIdx = bestIndex {
                currentAnchorIndex = matchedIdx
                lastWordMatchTime = now

                let matchedAnchor = voiceAnchors[matchedIdx]
                let leadOffset = min(max(18, viewportHeight * 0.04), 36)
                voiceTargetY = min(max(0, matchedAnchor.targetScrollY + leadOffset), maxScrollY)

                let previewWords = spokenTokens.suffix(2).map(\.norm).joined(separator: " ")
                voiceStatusText = "«\(previewWords)»"
                refreshPillUI()
            }
        }

        private func syncAnchorIndex(toScrollY scrollY: CGFloat) {
            guard !voiceAnchors.isEmpty else {
                currentAnchorIndex = 0
                return
            }
            var closestIdx = 0
            var smallestDiff = CGFloat.greatestFiniteMagnitude
            for anchor in voiceAnchors {
                let diff = abs(anchor.targetScrollY - scrollY)
                if diff < smallestDiff {
                    smallestDiff = diff
                    closestIdx = anchor.index
                }
            }
            currentAnchorIndex = closestIdx
        }

        private static func normalizeRussianWord(_ raw: String) -> String {
            let lowered = raw.lowercased().replacingOccurrences(of: "ё", with: "е")
            let scalars = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            return String(String.UnicodeScalarView(scalars))
        }

        private static func russianStem(for normalized: String) -> String {
            let count = normalized.count
            if count >= 7 {
                return String(normalized.prefix(count - 2))
            } else if count >= 5 {
                return String(normalized.prefix(count - 1))
            }
            return normalized
        }

        private static func tokenizeRussian(_ text: String, maxTailWords: Int) -> [(norm: String, stem: String)] {
            let parts = text.components(separatedBy: .whitespacesAndNewlines)
            var result: [(norm: String, stem: String)] = []
            for part in parts.suffix(maxTailWords * 2) {
                let norm = normalizeRussianWord(part)
                if !norm.isEmpty {
                    result.append((norm: norm, stem: russianStem(for: norm)))
                }
            }
            if result.count > maxTailWords {
                return Array(result.suffix(maxTailWords))
            }
            return result
        }

        private static func wordSimilarity(spoken: (norm: String, stem: String), anchor: PrompterVoiceAnchor) -> Double {
            if spoken.norm == anchor.normalizedWord {
                return 1.0
            }
            if spoken.norm.count >= 4 && anchor.normalizedWord.count >= 4 {
                if spoken.stem == anchor.stem {
                    return 0.90
                }
                if anchor.normalizedWord.hasPrefix(spoken.stem) || spoken.norm.hasPrefix(anchor.stem) {
                    return 0.84
                }
            }
            if spoken.norm.count >= 5 && anchor.normalizedWord.count >= 5 {
                let dist = levenshteinDistance(spoken.norm, anchor.normalizedWord)
                if dist == 1 {
                    return 0.82
                } else if dist == 2 && spoken.norm.count >= 8 {
                    return 0.75
                }
            }
            return 0.0
        }

        private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
            let aChars = Array(a)
            let bChars = Array(b)
            let m = aChars.count
            let n = bChars.count
            if abs(m - n) > 2 { return 3 }
            if m == 0 { return n }
            if n == 0 { return m }

            var prev = Array(0...n)
            var curr = [Int](repeating: 0, count: n + 1)

            for i in 1...m {
                curr[0] = i
                for j in 1...n {
                    let cost = (aChars[i - 1] == bChars[j - 1]) ? 0 : 1
                    curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
                }
                prev = curr
            }
            return prev[n]
        }
    }
}
