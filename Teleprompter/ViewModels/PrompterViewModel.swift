import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class PrompterViewModel: ObservableObject {
    let script: PrompterScript
    let engine: ScrollEngine

    @Published private(set) var settings: PrompterSettings
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var countdown: Int?
    @Published private(set) var feedback: String?
    @Published var controlsVisible = true
    @Published private(set) var remoteConnected = false

    private let settingsStore: SettingsStore
    private let remote: RemoteInputManager
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private var cancellables = Set<AnyCancellable>()
    private var countdownTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var controlsTask: Task<Void, Never>?
    private var remoteHandlerID: UUID?
    private var hasStarted = false

    init(script: PrompterScript, settingsStore: SettingsStore, remote: RemoteInputManager) {
        self.script = script
        self.settingsStore = settingsStore
        self.remote = remote
        self.settings = settingsStore.settings

        let engine = ScrollEngine()
        engine.speed = settingsStore.settings.speed
        self.engine = engine

        settingsStore.$settings
            .sink { [weak self] newValue in
                self?.settings = newValue
                self?.engine.speed = newValue.speed
            }
            .store(in: &cancellables)

        engine.$isPlaying
            .sink { [weak self] playing in
                guard let self else { return }
                self.isPlaying = playing
                if playing {
                    self.hasStarted = true
                    self.scheduleControlsHide()
                } else {
                    self.controlsTask?.cancel()
                    self.controlsVisible = true
                }
            }
            .store(in: &cancellables)

        engine.$progress
            .sink { [weak self] value in self?.progress = value }
            .store(in: &cancellables)

        engine.$remainingSeconds
            .sink { [weak self] seconds in self?.remainingSeconds = seconds }
            .store(in: &cancellables)

        engine.$reachedEnd
            .sink { [weak self] reached in
                if reached { self?.showFeedback("Конец сценария") }
            }
            .store(in: &cancellables)

        remote.$isConnected
            .sink { [weak self] connected in self?.remoteConnected = connected }
            .store(in: &cancellables)

        remoteHandlerID = remote.setActionHandler { [weak self] action in
            self?.handleRemoteAction(action)
        }
    }

    var formattedRemainingTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func activate() {
        UIApplication.shared.isIdleTimerDisabled = true
        controlsVisible = true
        impactGenerator.prepare()
        OrientationController.apply(settings.orientationLock)
    }

    func deactivate() {
        cancelCountdown()
        engine.pause()
        controlsTask?.cancel()
        feedbackTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        if let remoteHandlerID {
            remote.clearActionHandler(id: remoteHandlerID)
            self.remoteHandlerID = nil
        }
    }

    func togglePlayback() {
        triggerHaptic()
        if countdown != nil {
            cancelCountdown()
            controlsVisible = true
            showFeedback("Отсчёт отменён")
            return
        }
        if engine.isPlaying {
            engine.pause()
            return
        }

        if !hasStarted && settings.countdownSeconds > 0 {
            startCountdown()
        } else {
            engine.play()
        }
    }

    func pauseForInterruption() {
        cancelCountdown()
        engine.pause()
    }

    func restart() {
        triggerHaptic()
        cancelCountdown()
        engine.restart()
        hasStarted = false
        controlsVisible = true
        showFeedback("В начало")
    }

    func toggleMirror() {
        triggerHaptic()
        settingsStore.settings.mirrored.toggle()
        showFeedback(settingsStore.settings.mirrored ? "Зеркало включено" : "Зеркало выключено")
    }

    func changeSpeed(by delta: Double) {
        settingsStore.settings.speed += delta
        showFeedback("Скорость: \(Int(settingsStore.settings.speed)) пт/с")
    }

    func changeFontSize(by delta: Double) {
        settingsStore.settings.fontSize += delta
        showFeedback("Шрифт: \(Int(settingsStore.settings.fontSize)) пт")
    }

    func setSpeed(_ value: Double) {
        settingsStore.settings.speed = value
    }

    func setFontSize(_ value: Double) {
        settingsStore.settings.fontSize = value
    }

    func seek(toProgress value: Double) {
        engine.seek(toProgress: value)
    }

    func beginScrubbing() {
        engine.pause()
    }

    func handleScreenTap() {
        if countdown != nil {
            cancelCountdown()
            controlsVisible = true
            showFeedback("Отсчёт отменён")
            return
        }
        toggleControls()
    }

    func toggleControls() {
        if controlsVisible && isPlaying {
            controlsTask?.cancel()
            controlsVisible = false
        } else {
            controlsVisible = true
            scheduleControlsHide()
        }
    }

    func registerInteraction() {
        controlsVisible = true
        scheduleControlsHide()
    }

    func handleRemoteAction(_ action: RemoteAction) {
        switch action {
        case .playPause:
            togglePlayback()
        case .speedUp:
            changeSpeed(by: 10)
        case .speedDown:
            changeSpeed(by: -10)
        case .seekBack:
            engine.seekPage(forward: false)
            showFeedback("Назад")
        case .seekForward:
            engine.seekPage(forward: true)
            showFeedback("Вперёд")
        case .fontUp:
            changeFontSize(by: 4)
        case .fontDown:
            changeFontSize(by: -4)
        case .restart:
            restart()
        case .toggleMirror:
            toggleMirror()
        }

        if !settings.keepControlsHiddenOnRemote && isPlaying {
            registerInteraction()
        }
    }

    private func triggerHaptic() {
        guard settings.hapticFeedback else { return }
        impactGenerator.impactOccurred()
    }

    private func startCountdown() {
        countdownTask?.cancel()
        controlsVisible = false
        let seconds = settings.countdownSeconds
        countdown = seconds

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for value in stride(from: seconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                self.countdown = value
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            self.countdown = nil
            self.engine.play()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    private func scheduleControlsHide() {
        controlsTask?.cancel()
        guard isPlaying, countdown == nil else { return }
        controlsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, !Task.isCancelled, self.isPlaying, self.countdown == nil else { return }
            self.controlsVisible = false
        }
    }

    private func showFeedback(_ text: String) {
        feedback = text
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !Task.isCancelled else { return }
            self.feedback = nil
        }
    }
}