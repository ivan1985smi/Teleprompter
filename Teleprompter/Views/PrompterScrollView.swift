import SwiftUI
import UIKit

final class PrompterContainerView: UIView {
    let textView: UITextView
    var onLayoutMetricsChanged: (() -> Void)?

    private var lastBoundsSize: CGSize = .zero
    private var lastSafeArea: UIEdgeInsets = .zero

    override init(frame: CGRect) {
        if #available(iOS 16.0, *) {
            // Классический движок TextKit 1 гарантирует, что текст не пропадёт через 10 секунд
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
        container.textView.delegate = nil
        coordinator.engine.detach(coordinator)
    }

    final class Coordinator: NSObject, UITextViewDelegate, PrompterScrollSurface {
        var engine: ScrollEngine
        weak var containerView: PrompterContainerView?
        weak var textView: UITextView?

        private var lastText: String = ""
        private var lastSettings: PrompterSettings?
        private var isProgrammaticScroll: Bool = false

        init(engine: ScrollEngine) {
            self.engine = engine
        }

        func apply(text: String, settings: PrompterSettings, force: Bool) {
            guard let textView, let containerView else { return }

            let normalized = settings.normalized()
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

                let mirrorTransform = normalized.mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
                if containerView.transform != mirrorTransform {
                    containerView.transform = mirrorTransform
                }

                recalculateLayoutMetrics()
                displayScrollPosition(savedOffsetY)
            } else {
                let mirrorTransform = normalized.mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
                if containerView.transform != mirrorTransform {
                    containerView.transform = mirrorTransform
                }
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
            // Держим isScrollEnabled = true всегда, чтобы iOS не гасила текст во время движения
            textView?.isScrollEnabled = true
            textView?.panGestureRecognizer.isEnabled = enabled
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if engine.isPlaying {
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
