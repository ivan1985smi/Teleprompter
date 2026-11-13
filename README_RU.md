# Суфлёр — нативный iOS-телесуфлёр

SwiftUI + UIKit, минимум **iOS 16**, только Swift, архитектура **MVVM**.

## Важно про «просто установочный файл»

Универсального IPA, который ставится на любой iPhone «нажал и установил», не существует: iOS требует действительную подпись Apple и provisioning-профиль. Поэтому в этом репозитории есть:

1. **Полный Xcode-проект** — открывается и собирается без CocoaPods/SPM-зависимостей.
2. **Скрипт и GitHub Actions** — собирают IPA на macOS.
3. **Инструкции установки** — TestFlight, Xcode, AltStore/Sideloadly.

Артефакт `Teleprompter-unsigned.ipa` из CI **неподписан**. iPhone не установит его напрямую. Это нормальный промежуточный артефакт сборки, а не готовый установщик.

Самые близкие к «одной кнопке» варианты:

- **TestFlight**: пользователь открывает ссылку и нажимает «Установить». Нужен платный Apple Developer Program и загрузка сборки в App Store Connect.
- **Xcode на Mac**: подключить iPhone, выбрать команду подписи, нажать Run.
- **AltStore/Sideloadly**: бесплатно с обычным Apple ID, но нужен компьютер и переподпись примерно каждые 7 дней.

---

## Структура проекта

```text
Teleprompter/
├── Teleprompter.xcodeproj
├── Teleprompter/
│   ├── App/
│   │   └── TeleprompterApp.swift          # @main, DI сервисов, TabView
│   ├── Models/
│   │   ├── PrompterScript.swift           # сценарий
│   │   ├── PrompterSettings.swift         # настройки, цвета, зеркало, тема
│   │   └── RemoteMapping.swift            # действия пульта и назначения кнопок
│   ├── Services/
│   │   ├── ScriptStore.swift              # JSON-библиотека, TXT/буфер
│   │   ├── SettingsStore.swift            # UserDefaults, автосохранение
│   │   ├── ScrollEngine.swift             # CADisplayLink, скорость, позиция
│   │   └── RemoteInputManager.swift       # GCKeyboard + GCController, калибровка
│   ├── ViewModels/
│   │   ├── PrompterViewModel.swift        # плеер, отсчёт, пульт, контролы
│   │   └── ScriptEditorViewModel.swift    # черновик редактора
│   ├── Views/
│   │   ├── LibraryView.swift              # библиотека сценариев
│   │   ├── ScriptEditorView.swift         # редактор
│   │   ├── PrompterView.swift             # полноэкранный суфлёр
│   │   ├── PrompterScrollView.swift       # UIKit UITextView-прокрутка
│   │   ├── SettingsView.swift             # настройки
│   │   ├── RemoteSettingsView.swift       # пульт и калибровка
│   │   └── PrompterComponents.swift       # кнопки, метка, отсчёт, toast
│   ├── Resources/
│   │   └── Assets.xcassets                # иконка и accent color
│   └── Info.plist
├── Tools/
│   ├── generate_project.py                # генератор .xcodeproj
│   └── build_unsigned_ipa.sh              # сборка неподписанного IPA
└── .github/workflows/
    └── build-unsigned-ipa.yml             # CI на macOS
```

## Основные типы

| Тип | Ответственность |
|---|---|
| `PrompterScript` | `id`, заголовок, текст, даты создания/обновления. |
| `PrompterSettings` | шрифт, скорость, интервал, цвета, зеркало, отсчёт, тема, выравнивание, метка чтения. |
| `ScriptStore` | единственная библиотека сценариев; атомарная запись JSON; импорт TXT и буфера. |
| `SettingsStore` | автосохранение настроек; `mirrored` сохраняется сразу. |
| `ScrollEngine` | независимая прокрутка: `CADisplayLink`, points/sec, seek, progress, конец текста. |
| `RemoteInputManager` | HID-клавиатура через `GCKeyboard.coalesced`, геймпад через `GCController`, переподключение, калибровка. |
| `PrompterViewModel` | связывает плеер, настройки, движок и пульт; обратный отсчёт; скрытие контролов. |
| `PrompterScrollView` | UIKit-поверхность: длинный текст, атрибуты, горизонтальное зеркало через transform. |

Полный код находится в файлах проекта. Ключевые файлы для ревью: `ScrollEngine.swift`, `RemoteInputManager.swift`, `PrompterScrollView.swift`, `PrompterView.swift`, `PrompterViewModel.swift`.

---

## Возможности

- Большой читаемый текст, плавная прокрутка снизу вверх.
- Размер шрифта, скорость, цвет текста/фона, межстрочный интервал.
- Ввод вручную, вставка из буфера, импорт `.txt`.
- Полноэкранный режим: скрытие статус-бара, home indicator и контролов.
- **Зеркало** по горизонтали, работает на паузе и во время прокрутки, состояние сохраняется.
- Bluetooth HID-пульт: play/pause, скорость, перемотка, размер шрифта.
- Экран калибровки: последняя нажатая кнопка + переназначение действий.
- Обратный отсчёт перед первым стартом.
- Библиотека сценариев, поиск, дублирование, удаление.
- Светлая/тёмная/системная тема интерфейса.
- Портретная и ландшафтная ориентации.
- Экран не гаснет во время работы; при уходе в фон прокрутка ставится на паузу.

## Почему прокрутка сделана через UIKit

SwiftUI удобен для экранов и настроек, но покадровое обновление длинного текста не должно пересобирать SwiftUI-дерево. Поэтому:

- текст живёт в одном `UITextView`;
- атрибуты пересобираются только при изменении текста/шрифта/цвета/интервала;
- каждый кадр меняется только `contentOffset`;
- скорость считается через delta time, а не через «шаг на кадр»;
- `progress` публикуется не чаще 10 раз в секунду;
- зеркало — это `CGAffineTransform(scaleX: -1, y: 1)`, оно не ломает вертикальную прокрутку.

---

## Bluetooth-пульт: как это работает на iOS

Приложение **не спаривает** Bluetooth-устройство самостоятельно. Для обычных HID-пультов это делает iOS:

1. Откройте **Настройки iPhone → Bluetooth**.
2. Переведите пульт в режим сопряжения.
3. Подключите пульт как клавиатуру/контроллер.
4. Откройте приложение → **Настройки → Bluetooth-пульт**.
5. Нажмите кнопку на пульте: она должна появиться в «Последняя кнопка».
6. Если действие не совпадает — нажмите «Настроить» и назначьте кнопку.

После первого сопряжения iOS сама восстанавливает соединение. Приложение заново подписывается на события после `GCKeyboardDidConnect` / `GCControllerDidConnect` и после возвращения из фона.

### Заводские назначения

| Действие | Клавиатура / HID | Геймпад |
|---|---|---|
| Старт / пауза | Enter, Num Enter, Пробел | A |
| Быстрее | ↑, Page Up | D-pad ↑ |
| Медленнее | ↓, Page Down | D-pad ↓ |
| Назад | ← | D-pad ← |
| Вперёд | → | D-pad → |
| Шрифт больше | `+` / `=`, Num `+` | Right shoulder |
| Шрифт меньше | `-`, Num `-` | Left shoulder |

### Ограничение дешёвых пультов

Некоторые пульты отправляют не обычные клавиши, а системные media/volume-события. iOS может перехватить их до приложения. Публичный API не даёт гарантированно перехватить такие кнопки. В этом случае:

- переключите режим пульта, если у него есть несколько режимов;
- назначьте действия на кнопки, которые видны в калибровке;
- используйте экранные кнопки как запасной вариант.

Это не ошибка калибровки, а ограничение iOS для системных HID-событий.

---

## Сборка на Mac

Требуется macOS с Xcode 15 или новее. Минимальная версия приложения — iOS 16.

### Открыть в Xcode

```bash
open Teleprompter.xcodeproj
```

В Xcode:

1. Выберите target **Teleprompter**.
2. В **Signing & Capabilities** выберите свою Team.
3. Измените Bundle Identifier с `com.example.teleprompter` на свой, например `com.yourname.teleprompter`.
4. Подключите iPhone и нажмите **Run**.

### Собрать неподписанный IPA одной командой

```bash
bash Tools/build_unsigned_ipa.sh
```

Результат: `Teleprompter-unsigned.ipa`.

Ещё раз: это **неподписанный** артефакт. Он нужен для CI/подписи, а не для прямой установки на iPhone.

### Пересоздать Xcode-проект

Если меняли список файлов:

```bash
python3 Tools/generate_project.py
```

Генератор не требует сторонних Python-пакетов.

## GitHub Actions

Workflow `.github/workflows/build-unsigned-ipa.yml` запускается вручную или при push в `main`. Он собирает проект на `macos-14` и загружает артефакт `Teleprompter-unsigned-ipa`.

Чтобы получить устанавливаемую сборку, добавьте один из путей подписи:

- Xcode Archive → Distribute App → TestFlight;
- подпись через AltStore/Sideloadly;
- CI-шаг с сертификатами и provisioning-профилем вашей команды Apple Developer.

---

## Установка

### Вариант A — TestFlight, ближе всего к «нажал и установил»

1. Нужен платный Apple Developer Program.
2. В Xcode: **Product → Archive**.
3. **Distribute App → App Store Connect → Upload**.
4. В App Store Connect добавьте сборку в TestFlight.
5. Отправьте пользователю ссылку TestFlight.

Пользователь ставит TestFlight из App Store, открывает ссылку и нажимает «Установить».

### Вариант B — Xcode и бесплатный Apple ID

1. Откройте проект на Mac.
2. Выберите Team своего Apple ID.
3. Подключите iPhone.
4. Нажмите Run.

Бесплатная подпись обычно действует ограниченное время, после чего приложение нужно переподписать/переустановить через Xcode.

### Вариант C — AltStore / Sideloadly

1. Соберите IPA или возьмите CI-артефакт.
2. Подпишите и установите через AltStore или Sideloadly своим Apple ID.
3. Учитывайте срок действия бесплатной подписи и необходимость обновления.

Это бесплатно, но не является «вечной установкой без компьютера».

---

## Проверка перед съёмкой

- [ ] Длинный TXT импортируется и открывается.
- [ ] Старт/пауза работает с экрана и с пульта.
- [ ] ↑/↓ меняют скорость, ←/→ перематывают, +/− меняют шрифт.
- [ ] «Зеркало» включается/выключается во время прокрутки и сохраняется после перезапуска.
- [ ] Статус-бар и контролы скрываются в полноэкранном режиме.
- [ ] Поворот в ландшафт не сбрасывает текст и не ломает зеркало.
- [ ] После выключения/включения пульта приложение снова видит кнопки.
- [ ] При уходе приложения в фон прокрутка останавливается.
- [ ] Сценарии сохраняются после перезапуска.

## Технические заметки

- Разрешение Bluetooth для HID-клавиатуры через GameController не требуется: сопряжение выполняется в системных настройках iOS.
- Данные хранятся локально: сценарии в `Application Support/Teleprompter/scripts.json`, настройки и маппинг пульта в `UserDefaults`.
- Сетевых запросов и сторонних SDK нет.
- `ITSAppUsesNonExemptEncryption` установлен в `false`, так как приложение не использует собственную криптографию.

## Полезные ссылки Apple

- GCKeyboard: https://developer.apple.com/documentation/gamecontroller/gckeyboard
- GCKeyCode: https://developer.apple.com/documentation/gamecontroller/gckeycode
- GCPhysicalInputProfile: https://developer.apple.com/documentation/gamecontroller/gcphysicalinputprofile
- WWDC: Bring keyboard and mouse gaming to iPad: https://developer.apple.com/videos/play/wwdc2020/10617/
