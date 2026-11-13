import Foundation
import GameController

enum RemoteAction: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case playPause
    case speedUp
    case speedDown
    case seekBack
    case seekForward
    case fontUp
    case fontDown
    case restart
    case toggleMirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause: return "Старт / пауза"
        case .speedUp: return "Быстрее"
        case .speedDown: return "Медленнее"
        case .seekBack: return "Назад на фрагмент"
        case .seekForward: return "Вперёд на фрагмент"
        case .fontUp: return "Шрифт больше"
        case .fontDown: return "Шрифт меньше"
        case .restart: return "В начало сценария"
        case .toggleMirror: return "Зеркало вкл / выкл"
        }
    }

    var symbol: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .speedUp: return "hare.fill"
        case .speedDown: return "tortoise.fill"
        case .seekBack: return "gobackward"
        case .seekForward: return "goforward"
        case .fontUp: return "textformat.size.larger"
        case .fontDown: return "textformat.size.smaller"
        case .restart: return "backward.end.fill"
        case .toggleMirror: return "arrow.left.and.right"
        }
    }

    var isToggleAction: Bool {
        switch self {
        case .playPause, .restart, .toggleMirror:
            return true
        case .speedUp, .speedDown, .seekBack, .seekForward, .fontUp, .fontDown:
            return false
        }
    }
}

enum RemoteInput: Codable, Equatable, Hashable, Sendable {
    case keyboard(Int)
    case controller(String)

    var displayName: String {
        switch self {
        case .keyboard(let code):
            return Self.keyboardNames[code] ?? String(format: "HID-клавиша (0x%02X / %d)", code, code)
        case .controller(let name):
            return Self.controllerNames[name] ?? name
        }
    }

    var storageKey: String {
        switch self {
        case .keyboard(let code): return "hid.\(code)"
        case .controller(let name): return "pad.\(name)"
        }
    }

    private static let keyboardNames: [Int: String] = [
        Int(GCKeyCode.returnOrEnter.rawValue): "Enter / Start",
        Int(GCKeyCode.keypadEnter.rawValue): "Num Enter",
        Int(GCKeyCode.spacebar.rawValue): "Пробел (Space)",
        Int(GCKeyCode.upArrow.rawValue): "Стрелка вверх (↑)",
        Int(GCKeyCode.downArrow.rawValue): "Стрелка вниз (↓)",
        Int(GCKeyCode.leftArrow.rawValue): "Стрелка влево (←)",
        Int(GCKeyCode.rightArrow.rawValue): "Стрелка вправо (→)",
        Int(GCKeyCode.pageUp.rawValue): "Page Up",
        Int(GCKeyCode.pageDown.rawValue): "Page Down",
        Int(GCKeyCode.equalSign.rawValue): "+ / =",
        Int(GCKeyCode.hyphen.rawValue): "− / -",
        Int(GCKeyCode.keypadPlus.rawValue): "Num +",
        Int(GCKeyCode.keypadHyphen.rawValue): "Num −",
        Int(GCKeyCode.openBracket.rawValue): "[",
        Int(GCKeyCode.closeBracket.rawValue): "]",
        Int(GCKeyCode.escape.rawValue): "Esc",
        Int(GCKeyCode.deleteOrBackspace.rawValue): "Backspace",
        Int(GCKeyCode.keyW.rawValue): "W",
        Int(GCKeyCode.keyS.rawValue): "S",
        Int(GCKeyCode.keyA.rawValue): "A",
        Int(GCKeyCode.keyD.rawValue): "D",
        Int(GCKeyCode.keyJ.rawValue): "J",
        Int(GCKeyCode.keyK.rawValue): "K",
        Int(GCKeyCode.keyL.rawValue): "L",
        Int(GCKeyCode.keyM.rawValue): "M",
        Int(GCKeyCode.volumeUp.rawValue): "Volume Up (HID)",
        Int(GCKeyCode.volumeDown.rawValue): "Volume Down (HID)"
    ]

    private static let controllerNames: [String: String] = [
        "buttonA": "Кнопка A / ОК",
        "buttonB": "Кнопка B / Назад",
        "buttonX": "Кнопка X",
        "buttonY": "Кнопка Y",
        "buttonMenu": "Кнопка Menu / Start",
        "buttonOptions": "Кнопка Options / Select",
        "dpad.up": "D-pad вверх",
        "dpad.down": "D-pad вниз",
        "dpad.left": "D-pad влево",
        "dpad.right": "D-pad вправо",
        "leftShoulder": "Левый бампер (L1)",
        "rightShoulder": "Правый бампер (R1)"
    ]
}

struct RemoteBinding: Codable, Equatable, Identifiable, Sendable {
    var action: RemoteAction
    var input: RemoteInput

    var id: String { "\(action.rawValue)|\(input.storageKey)" }
}

struct RemoteMapping: Codable, Equatable, Sendable {
    var bindings: [RemoteBinding]

    func action(for input: RemoteInput) -> RemoteAction? {
        bindings.first(where: { $0.input == input })?.action
    }

    func inputs(for action: RemoteAction) -> [RemoteInput] {
        bindings.filter { $0.action == action }.map(\.input)
    }

    mutating func assign(_ input: RemoteInput, to action: RemoteAction) {
        bindings.removeAll { $0.input == input || $0.action == action }
        bindings.append(RemoteBinding(action: action, input: input))
    }

    static let `default`: RemoteMapping = {
        var bindings: [RemoteBinding] = []

        func add(_ action: RemoteAction, _ inputs: [RemoteInput]) {
            bindings.append(contentsOf: inputs.map { RemoteBinding(action: action, input: $0) })
        }

        add(.playPause, [
            .keyboard(Int(GCKeyCode.returnOrEnter.rawValue)),
            .keyboard(Int(GCKeyCode.keypadEnter.rawValue)),
            .keyboard(Int(GCKeyCode.spacebar.rawValue)),
            .keyboard(Int(GCKeyCode.keyK.rawValue)),
            .controller("buttonA"),
            .controller("buttonMenu")
        ])
        add(.speedUp, [
            .keyboard(Int(GCKeyCode.upArrow.rawValue)),
            .keyboard(Int(GCKeyCode.pageUp.rawValue)),
            .keyboard(Int(GCKeyCode.keyW.rawValue)),
            .keyboard(Int(GCKeyCode.keyL.rawValue)),
            .controller("dpad.up")
        ])
        add(.speedDown, [
            .keyboard(Int(GCKeyCode.downArrow.rawValue)),
            .keyboard(Int(GCKeyCode.pageDown.rawValue)),
            .keyboard(Int(GCKeyCode.keyS.rawValue)),
            .keyboard(Int(GCKeyCode.keyJ.rawValue)),
            .controller("dpad.down")
        ])
        add(.seekBack, [
            .keyboard(Int(GCKeyCode.leftArrow.rawValue)),
            .keyboard(Int(GCKeyCode.keyA.rawValue)),
            .controller("dpad.left")
        ])
        add(.seekForward, [
            .keyboard(Int(GCKeyCode.rightArrow.rawValue)),
            .keyboard(Int(GCKeyCode.keyD.rawValue)),
            .controller("dpad.right")
        ])
        add(.fontUp, [
            .keyboard(Int(GCKeyCode.equalSign.rawValue)),
            .keyboard(Int(GCKeyCode.keypadPlus.rawValue)),
            .keyboard(Int(GCKeyCode.closeBracket.rawValue)),
            .controller("rightShoulder")
        ])
        add(.fontDown, [
            .keyboard(Int(GCKeyCode.hyphen.rawValue)),
            .keyboard(Int(GCKeyCode.keypadHyphen.rawValue)),
            .keyboard(Int(GCKeyCode.openBracket.rawValue)),
            .controller("leftShoulder")
        ])
        add(.restart, [
            .keyboard(Int(GCKeyCode.escape.rawValue)),
            .keyboard(Int(GCKeyCode.deleteOrBackspace.rawValue)),
            .controller("buttonB")
        ])
        add(.toggleMirror, [
            .keyboard(Int(GCKeyCode.keyM.rawValue)),
            .controller("buttonY")
        ])

        return RemoteMapping(bindings: bindings)
    }()
}