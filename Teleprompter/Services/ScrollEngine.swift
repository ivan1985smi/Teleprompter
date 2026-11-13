import Foundation
import QuartzCore
import UIKit

@MainActor
protocol PrompterScrollSurface: AnyObject {
    func displayScrollPosition(_ position: CGFloat)
    func setManualScrollingEnabled(_ enabled: Bool)
}

@MainActor
final class ScrollEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var reachedEnd = false
    @Published private(set) var remainingSeconds: Int = 0

    var speed: Double = 70 {
        didSet {
            let clamped = speed.isFinite
                ? min(max(speed, PrompterSettings.speedRange.lowerBound), PrompterSettings.speedRange.upperBound)
                : 70
            if speed != clamped {
                speed = clamped
            }
            updateRemainingTime(force: true)
        }
    }

    weak var surface: PrompterScrollSurface? {
        didSet {
            surface?.setManualScrollingEnabled(!isPlaying)
            surface?.displayScrollPosition(CGFloat(position))
        }
    }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var lastProgressPublish: CFTimeInterval = 0

    private var position: Double = 0
    private var maxPosition: Double = 0
    private var viewportHeight: CGFloat = 0

    func attach(_ surface: PrompterScrollSurface) {
        self.surface = surface
    }

    func detach(_ surface: PrompterScrollSurface) {
        guard self.surface === surface else { return }
        pause()
        self.surface = nil
    }

    func play() {
        guard !isPlaying, maxPosition > 0 else { return }
        if position >= maxPosition - 0.5 {
            position = 0
            reachedEnd = false
            surface?.displayScrollPosition(0)
        }
        isPlaying = true
        surface?.setManualScrollingEnabled(false)
        lastTimestamp = nil
        startDisplayLink()
        publishProgress(force: true)
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        stopDisplayLink()
        surface?.setManualScrollingEnabled(true)
        publishProgress(force: true)
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func restart() {
        pause()
        reachedEnd = false
        seek(to: 0)
    }

    func seek(by delta: CGFloat) {
        seek(to: position + Double(delta))
    }

    func seekPage(forward: Bool) {
        let step = max(Double(viewportHeight) * 0.75, 120)
        seek(by: forward ? step : -step)
    }

    func seek(to newPosition: Double) {
        guard newPosition.isFinite else { return }
        position = min(max(newPosition, 0), maxPosition)
        reachedEnd = position >= maxPosition && maxPosition > 0
        if reachedEnd { pause() }
        surface?.displayScrollPosition(CGFloat(position))
        publishProgress(force: true)
    }

    func seek(toProgress newProgress: Double) {
        guard newProgress.isFinite else { return }
        seek(to: min(max(newProgress, 0), 1) * maxPosition)
    }

    func updateFromManualScroll(_ newPosition: CGFloat) {
        guard !isPlaying, newPosition.isFinite else { return }
        position = min(max(Double(newPosition), 0), maxPosition)
        reachedEnd = position >= maxPosition && maxPosition > 0
        publishProgress(force: false)
    }

    func updateMetrics(maxPosition: CGFloat, viewportHeight: CGFloat) {
        let previousRatio = self.maxPosition > 0 ? min(max(position / self.maxPosition, 0), 1) : 0
        let newMax = max(0, Double(maxPosition))

        self.viewportHeight = viewportHeight
        self.maxPosition = newMax

        if previousRatio > 0 && newMax > 0 {
            position = min(previousRatio * newMax, newMax)
        } else {
            position = min(position, newMax)
        }

        reachedEnd = newMax > 0 && position >= newMax - 0.5
        surface?.displayScrollPosition(CGFloat(position))
        publishProgress(force: true)
    }

    private func startDisplayLink() {
        stopDisplayLink()
        let proxy = DisplayLinkProxy(engine: self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    fileprivate func handleFrame(_ link: CADisplayLink) {
        guard isPlaying else { return }
        guard let previous = lastTimestamp else {
            lastTimestamp = link.timestamp
            return
        }
        let delta = min(max(link.timestamp - previous, 0), 0.1)
        lastTimestamp = link.timestamp
        position += speed * delta

        if position >= maxPosition {
            position = maxPosition
            reachedEnd = true
            surface?.displayScrollPosition(CGFloat(position))
            pause()
            return
        }

        surface?.displayScrollPosition(CGFloat(position))
        publishProgress(force: false)
    }

    private func publishProgress(force: Bool) {
        let now = CACurrentMediaTime()
        guard force || now - lastProgressPublish >= 0.1 else { return }
        lastProgressPublish = now
        let value = maxPosition > 0 ? position / maxPosition : 0
        if abs(progress - value) > 0.0001 || force {
            progress = min(max(value, 0), 1)
        }
        updateRemainingTime(force: force)
    }

    private func updateRemainingTime(force: Bool) {
        guard speed > 0, maxPosition > position else {
            if remainingSeconds != 0 { remainingSeconds = 0 }
            return
        }
        let seconds = Int(ceil((maxPosition - position) / speed))
        if remainingSeconds != seconds || force {
            remainingSeconds = max(0, seconds)
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}

private final class DisplayLinkProxy: NSObject {
    weak var engine: ScrollEngine?

    init(engine: ScrollEngine) {
        self.engine = engine
    }

    @objc func step(_ link: CADisplayLink) {
        Task { @MainActor [weak engine] in
            engine?.handleFrame(link)
        }
    }
}