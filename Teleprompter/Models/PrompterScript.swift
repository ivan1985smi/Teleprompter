import Foundation

struct PrompterScript: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var title: String
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        text: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Пустой сценарий" }
        return String(trimmed.prefix(220))
    }

    var wordCount: Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    var estimatedReadingTimeFormatted: String {
        let words = wordCount
        guard words > 0 else { return "0:00" }
        let totalSeconds = max(1, Int((Double(words) / 130.0) * 60.0))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static let sample = PrompterScript(
        title: "Добро пожаловать",
        text: """
        Это ваш профессиональный телесуфлёр.

        Нажмите кнопку воспроизведения внизу экрана или кнопку START/STOP на Bluetooth-пульте. Текст начнёт плавно двигаться снизу вверх, а читаемая строка останется напротив боковых меток.

        Скорость и размер шрифта можно менять прямо во время записи — текущая строка останется на месте и не собьётся.

        Кнопка «Зеркало» мгновенно отражает текст по горизонтали для работы со светоделительным стеклом телесуфлёра. Состояние зеркала сохраняется автоматически.

        Подключите Bluetooth-пульт в «Настройках iPhone → Bluetooth», затем откройте «Настройки → Bluetooth-пульт» в приложении для проверки и назначения кнопок.

        Удачных дублей!
        """
    )
}