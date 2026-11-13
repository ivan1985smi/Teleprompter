import Foundation
import GameController
import QuartzCore
import UIKit

@MainActor
final class RemoteInputManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var deviceName = "Пульт не подключён"
    @Published private(set) var lastInputDescription = "Нажмите кнопку на пульте"
    @Published private(set) var lastInputDate: Date?
    @Published private(set) var mapping: RemoteMapping
    @Published private(set) var capturingAction: RemoteAction?
    @Published var calibrationMessage: String?
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: enabledKey)
        }
    }

    private var actionHandler: ((RemoteAction) -> Void)?
    private var actionHandlerID: UUID?

    func setActionHandler(_ handler: @escaping (RemoteAction) -> Void) -> UUID {
        let id = UUID()
        actionHandlerID = id
        actionHandler = handler
        return id
    }

    func clearActionHandler(id: UUID) {
        guard actionHandlerID == id else { return }
        actionHandler = nil
        actionHandlerID = nil
    }

    private let defaults: UserDefaults
    private let mappingKey: String
    private let enabledKey: String
    private var observers: [NSObjectProtocol] = []
    private var captureTimeoutTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var isStarted = false

    private var lastRawEvent: (key: String, timestamp: CFTimeInterval)?
    private var lastActionTimes: [RemoteAction: CFTimeInterval] = [:]

    init(
        defaults: UserDefaults = .standard,
        mappingKey: String = "remote.mapping.v1",
        enabledKey: String = "remote.enabled.v1"
    ) {
        self.defaults = defaults
        self.mappingKey = mappingKey
        self.enabledKey = enabledKey

        if defaults.object(forKey: enabledKey) != nil {
            self.isEnabled = defaults.bool(forKey: enabledKey)
        } else {
            self.isEnabled = true
        }

        if let data = defaults.data(forKey: mappingKey),
           let saved = try? JSONDecoder().decode(RemoteMapping.self, from: data),
           !saved.bindings.isEmpty {
            self.mapping = saved
        } else {
            self.mapping = .default
        }
    }

    func start() {
        guard !isStarted else {
            refresh()
            return
        }
        isStarted = true

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .GCKeyboardDidConnect,
            .GCKeyboardDidDisconnect,
            .GCControllerDidConnect,
            .GCControllerDidDisconnect,
            UIApplication.didBecomeActiveNotification
        ]

        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRefreshWithRetry()
                }
            }
            observers.append(observer)
        }
        refresh()
    }

    func stop() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
        captureTimeoutTask?.cancel()
        refreshTask?.cancel()
        clearHandlers()
        isStarted = false
        isConnected = false
    }

    func refresh() {
        clearHandlers()

        let keyboard = GCKeyboard.coalesced
        let controllers = GCController.controllers()

        if let input = keyboard?.keyboardInput {
            input.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
                guard pressed else { return }
                let code = Int(keyCode.rawValue)
                Task { @MainActor [weak self] in
                    self?.receive(.keyboard(code))
                }
            }
        }

        for controller in controllers {
            attach(controller)
        }

        isConnected = keyboard != nil || !controllers.isEmpty
        switch (keyboard, controllers.isEmpty) {
        case (.some(let keyboard), true):
            deviceName = keyboard.vendorName ?? "Bluetooth-клавиатура / HID-пульт"
        case (.none, false):
            deviceName = controllers.first?.vendorName ?? "Bluetooth-контроллер"
        case (.some, false):
            deviceName = "HID-клавиатура + контроллер"
        case (.none, true):
            deviceName = "Пульт не подключён"
        }
    }

    func handleExternalHIDKey(code: Int) {
        if !isConnected {
            refresh()
        }
        receive(.keyboard(code))
    }

    func beginCapture(for action: RemoteAction) {
        capturingAction = action
        calibrationMessage = "Нажмите кнопку на пульте для действия «\(action.title)»."
        captureTimeoutTask?.cancel()
        captureTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self, self.capturingAction == action else { return }
            self.capturingAction = nil
            self.calibrationMessage = "Время ожидания истекло. Если кнопка не определилась, iOS перехватывает её как системную."
        }
    }

    func cancelCapture() {
        captureTimeoutTask?.cancel()
        capturingAction = nil
        calibrationMessage = nil
    }

    func resetMapping() {
        mapping = .default
        persistMapping()
        cancelCapture()
        calibrationMessage = "Заводские назначения восстановлены."
    }

    func assign(_ input: RemoteInput, to action: RemoteAction) {
        mapping.assign(input, to: action)
        persistMapping()
    }

    private func scheduleRefreshWithRetry() {
        refresh()
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func receive(_ input: RemoteInput) {
        let now = CACurrentMediaTime()

        if let last = lastRawEvent, last.key == input.storageKey, (now - last.timestamp) < 0.045 {
            return
        }
        lastRawEvent = (input.storageKey, now)

        lastInputDescription = input.displayName
        lastInputDate = .now

        if let action = capturingAction {
            assign(input, to: action)
            capturingAction = nil
            captureTimeoutTask?.cancel()
            calibrationMessage = "«\(input.displayName)» назначена на «\(action.title)»."
            return
        }

        guard isEnabled, let action = mapping.action(for: input) else { return }

        let minInterval: CFTimeInterval = action.isToggleAction ? 0.22 : 0.075
        if let lastActionTime = lastActionTimes[action], (now - lastActionTime) < minInterval {
            return
        }
        lastActionTimes[action] = now

        actionHandler?(action)
    }

    private func attach(_ controller: GCController) {
        let profile = controller.physicalInputProfile

        let buttonAliases: [String: String] = [
            GCInputButtonA: "buttonA",
            GCInputButtonB: "buttonB",
            GCInputButtonX: "buttonX",
            GCInputButtonY: "buttonY",
            GCInputButtonMenu: "buttonMenu",
            GCInputButtonOptions: "buttonOptions",
            GCInputLeftShoulder: "leftShoulder",
            GCInputRightShoulder: "rightShoulder"
        ]

        for (appleName, button) in profile.buttons {
            guard let normalized = buttonAliases[appleName] else { continue }
            bind(button, to: .controller(normalized))
        }

        for (_, pad) in profile.dpads {
            bind(pad.up, to: .controller("dpad.up"))
            bind(pad.down, to: .controller("dpad.down"))
            bind(pad.left, to: .controller("dpad.left"))
            bind(pad.right, to: .controller("dpad.right"))
        }
    }

    private func bind(_ button: GCControllerButtonInput, to input: RemoteInput) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor [weak self] in
                self?.receive(input)
            }
        }
    }

    private func clearHandlers() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        for controller in GCController.controllers() {
            let profile = controller.physicalInputProfile
            for (_, button) in profile.buttons {
                button.pressedChangedHandler = nil
            }
            for (_, pad) in profile.dpads {
                pad.up.pressedChangedHandler = nil
                pad.down.pressedChangedHandler = nil
                pad.left.pressedChangedHandler = nil
                pad.right.pressedChangedHandler = nil
            }
        }
    }

    private func persistMapping() {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        defaults.set(data, forKey: mappingKey)
    }
}