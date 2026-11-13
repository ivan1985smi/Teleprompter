import SwiftUI
import UIKit

final class PrompterContainerView: UIView {
    let textView = UITextView()
    var onLayoutMetricsChanged: (() -> Void)?

    private var lastBoundsSize: CGSize = .zero
    private var lastSafeArea: UIEdgeInsets = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true

        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.bounces = false
        textView.alwaysBounceVertical = false
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainer.lineFragmentPadding = 0
        textView.clipsToBounds = true

        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds

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
    let engine: ScrollEngine

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    func makeUIView(context: Context) -> PrompterContainerView {
        let container = PrompterContainerView()
        container.textView.delegate = context.coordinator

        context.coordinator.container = container
        container.onLayoutMetricsChanged = { [weak coordinator = context.coordinator] in
            coordinator?.recalculateLayoutMetrics()
        }

        engine.attach(context.coordinator)
        context.coordinator.apply(text: text, settings: settings, force: true)
        return container
    }

    func updateUIView(_ container: PrompterContainerView, context: Context) {
        context.coordinator.engine = engine
        context.coordinator.container = container
        engine.attach(context.coordinator)
        context.coordinator.apply(text: text, settings: settings, force: false)
    }

    static func dismantleUIView(_ container: PrompterContainerView, coordinator: Coordinator) {
        coordinator.engine.detach(coordinator)
        container.onLayoutMetricsChanged = nil
        container.textView.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, PrompterScrollSurface {
        var engine: ScrollEngine
        weak var container: PrompterContainerView?

        private var lastText: String?
        private var lastFontSize: Double?
        private var lastLineSpacing: Double?
        private var lastAlignment: PrompterTextAlignment?
        private var lastTextColor: RGBAColor?
        private var lastReadingPosition: Double?

        init(engine: ScrollEngine) {
            self.engine = engine
        }

        func apply(text: String, settings: PrompterSettings, force: Bool) {
            guard let container else { return }
            let textView = container.textView

            let typographyChanged = force
                || text != lastText
                || settings.fontSize != lastFontSize
                || settings.lineSpacing != lastLineSpacing
                || settings.textAlignment != lastAlignment
                || settings.textColor != lastTextColor

            let guideChanged = force || settings.readingPosition != lastReadingPosition

            if typographyChanged {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = CGFloat(settings.lineSpacing)
                paragraph.alignment = settings.textAlignment.nsTextAlignment
                paragraph.lineBreakMode = .byWordWrapping

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: CGFloat(settings.fontSize), weight: .semibold),
                    .foregroundColor: settings.textColor.uiColor,
                    .paragraphStyle: paragraph
                ]
                textView.attributedText = NSAttributedString(string: text, attributes: attributes)

                lastText = text
                lastFontSize = settings.fontSize
                lastLineSpacing = settings.lineSpacing
                lastAlignment = settings.textAlignment
                lastTextColor = settings.textColor
            }

            if guideChanged {
                lastReadingPosition = settings.readingPosition
            }

            if typographyChanged || guideChanged {
                recalculateLayoutMetrics()
            }

            let targetTransform = settings.mirrored
                ? CGAffineTransform(scaleX: -1, y: 1)
                : .identity
            if container.transform.a != targetTransform.a || container.transform.d != targetTransform.d {
                container.transform = targetTransform
            }

            textView.isScrollEnabled = !engine.isPlaying
        }

        func recalculateLayoutMetrics() {
            guard let container else { return }
            let textView = container.textView
            let height = container.bounds.height
            let width = container.bounds.width
            guard height > 0, width > 0 else { return }

            let readingPos = lastReadingPosition ?? 0.38
            let safeHorizontal = max(container.safeAreaInsets.left, container.safeAreaInsets.right)
            let horizontalInset = safeHorizontal + 24

            textView.textContainerInset = UIEdgeInsets(
                top: 0,
                left: horizontalInset,
                bottom: 0,
                right: horizontalInset
            )

            let topInset = height * CGFloat(readingPos)
            let bottomInset = height * (1 - CGFloat(readingPos))
            textView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
            textView.layoutIfNeeded()

            let maxPosition = max(
                0,
                textView.contentSize.height
                    + textView.contentInset.top
                    + textView.contentInset.bottom
                    - height
            )
            engine.updateMetrics(maxPosition: maxPosition, viewportHeight: height)
        }

        func displayScrollPosition(_ position: CGFloat) {
            guard let textView = container?.textView else { return }
            let targetY = position - textView.contentInset.top
            if abs(textView.contentOffset.y - targetY) > 0.01 {
                textView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
            }
        }

        func setManualScrollingEnabled(_ enabled: Bool) {
            container?.textView.isScrollEnabled = enabled
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            engine.pause()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            let position = scrollView.contentOffset.y + scrollView.contentInset.top
            engine.updateFromManualScroll(position)
        }
    }
}