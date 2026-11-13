import SwiftUI
import UIKit

struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = Self.clamp(red, min: 0, max: 1, fallback: 1)
        self.green = Self.clamp(green, min: 0, max: 1, fallback: 1)
        self.blue = Self.clamp(blue, min: 0, max: 1, fallback: 1)
        self.opacity = Self.clamp(opacity, min: 0, max: 1, fallback: 1)
    }

    init(_ color: Color) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        let uiColor = UIColor(color)
        if !uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            if let converted = uiColor.cgColor.converted(
                to: CGColorSpaceCreateDeviceRGB(),
                intent: .defaultIntent,
                options: nil
            ), let components = converted.components, components.count >= 3 {
                r = components[0]
                g = components[1]
                b = components[2]
                a = components.count >= 4 ? components[3] : 1.0
            }
        }
        self.init(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(opacity))
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lower), upper)
    }

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let yellow = RGBAColor(red: 1, green: 0.84, blue: 0.25)
}

enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum PrompterTextAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
    case left
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "По левому краю"
        case .center: return "По центру"
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        }
    }
}

enum ScreenOrientationLock: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case portrait
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Автоповорот"
        case .portrait: return "Только портрет"
        case .landscape: return "Только ландшафт"
        }
    }

    var interfaceOrientationMask: UIInterfaceOrientationMask {
        switch self {
        case .auto: return .allButUpsideDown
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }
}

struct PrompterSettings: Codable, Equatable, Sendable {
    var fontSize: Double = 46
    var speed: Double = 70
    var lineSpacing: Double = 12
    var textColor: RGBAColor = .white
    var backgroundColor: RGBAColor = .black
    var mirrored: Bool = false
    var countdownSeconds: Int = 3
    var theme: AppTheme = .dark
    var textAlignment: PrompterTextAlignment = .center
    var showReadingGuide: Bool = true
    var readingPosition: Double = 0.38
    var orientationLock: ScreenOrientationLock = .auto
    var hapticFeedback: Bool = true
    var keepControlsHiddenOnRemote: Bool = true

    static let fontRange: ClosedRange<Double> = 20...110
    static let speedRange: ClosedRange<Double> = 10...240
    static let lineSpacingRange: ClosedRange<Double> = 0...40
    static let readingPositionRange: ClosedRange<Double> = 0.2...0.65

    mutating func normalize() {
        let defaults = PrompterSettings()
        fontSize = Self.sanitize(fontSize, in: Self.fontRange, fallback: defaults.fontSize)
        speed = Self.sanitize(speed, in: Self.speedRange, fallback: defaults.speed)
        lineSpacing = Self.sanitize(lineSpacing, in: Self.lineSpacingRange, fallback: defaults.lineSpacing)
        countdownSeconds = min(max(countdownSeconds, 0), 10)
        readingPosition = Self.sanitize(readingPosition, in: Self.readingPositionRange, fallback: defaults.readingPosition)
    }

    private static func sanitize(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case fontSize, speed, lineSpacing, textColor, backgroundColor
        case mirrored, countdownSeconds, theme, textAlignment
        case showReadingGuide, readingPosition
        case orientationLock, hapticFeedback, keepControlsHiddenOnRemote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PrompterSettings()
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? defaults.speed
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? defaults.lineSpacing
        textColor = try container.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? defaults.textColor
        backgroundColor = try container.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? defaults.backgroundColor
        mirrored = try container.decodeIfPresent(Bool.self, forKey: .mirrored) ?? defaults.mirrored
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? defaults.countdownSeconds
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        textAlignment = try container.decodeIfPresent(PrompterTextAlignment.self, forKey: .textAlignment) ?? defaults.textAlignment
        showReadingGuide = try container.decodeIfPresent(Bool.self, forKey: .showReadingGuide) ?? defaults.showReadingGuide
        readingPosition = try container.decodeIfPresent(Double.self, forKey: .readingPosition) ?? defaults.readingPosition
        orientationLock = try container.decodeIfPresent(ScreenOrientationLock.self, forKey: .orientationLock) ?? defaults.orientationLock
        hapticFeedback = try container.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? defaults.hapticFeedback
        keepControlsHiddenOnRemote = try container.decodeIfPresent(Bool.self, forKey: .keepControlsHiddenOnRemote) ?? defaults.keepControlsHiddenOnRemote
        normalize()
    }
}