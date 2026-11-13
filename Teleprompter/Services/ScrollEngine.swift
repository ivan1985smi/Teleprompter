import Foundation
import QuartzCore
import CoreGraphics
import Combine

protocol PrompterScrollSurface: AnyObject {
    func displayScrollPosition(_ position: CGFloat)
    func setManualScrollingEnabled(_ enabled: Bool)
}

final class ScrollEngine: ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var reachedEnd: Bool = false

    var speed: Double = 75
    weak var surface: PrompterScrollSurface?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    private var position: CGFloat = 0
    private var maxPosition: CGFloat = 1
    private var viewportHeight: CGFloat = 600

    private var pendingSeekOffset: CGFloat = 0
    private var lastPublishedProgress: Double = -1

    init() {}

    deinit {
        stopDisplayLink()
    }

    func attach(_ surface: PrompterScrollSurface) {
        self.surface = surface
        surface.setManualScrollingEnabled(!isPlaying)
        surface.displayScrollPosition(position)
    }

    func detach(_ surface: PrompterScrollSurface) {
        if self.surface === surface {
            self.surface = nil
        }
        stopDisplayLink()
    }

    func play() {
        guard !isPlaying else { return }
        if reachedEnd || (maxPosition > 1 && position >= maxPosition - 1) {
            position = 0
            pendingSeekOffset = 0
            reachedEnd = false
            publishProgress(force: true)
            surface?.displayScrollPosition(position)
        }
        isPlaying = true
        surface?.setManualScrollingEnabled(false)
        ensureDisplayLinkRunning()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        surface?.setManualScrollingEnabled(true)
        publishProgress(force: true)
        if abs(pendingSeekOffset) < 0.5 {
            stopDisplayLink()
        }
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func restart() {
        pause()
        pendingSeekOffset = 0
        position = 0
        reachedEnd = false
        surface?.displayScrollPosition(0)
        publishProgress(force: true)
    }

    func seek(by delta: CGFloat) {
        let adjustedDelta: CGFloat = abs(delta) > 100 ? (delta * 0.42) : delta
        let target = clampPosition(position + pendingSeekOffset + adjustedDelta)
        pendingSeekOffset = target - position
        reachedEnd = (maxPosition > 0 && target >= maxPosition - 0.5)
        ensureDisplayLinkRunning()
    }

    func seekPage(forward: Bool) {
        let step = min(max(80, viewportHeight * 0.20), 145)
        let signedStep = forward ? step : -step
        let target = clampPosition(position + pendingSeekOffset + signedStep)
        pendingSeekOffset = target - position
        reachedEnd = (maxPosition > 0 && target >= maxPosition - 0.5)
        ensureDisplayLinkRunning()
    }

    func seek(to newPosition: Double) {
        seek(to: CGFloat(newPosition))
    }

    func seek(to newPosition: CGFloat) {
        pendingSeekOffset = 0
        position = clampPosition(newPosition)
        reachedEnd = (maxPosition > 0 && position >= maxPosition - 0.5)
        surface?.displayScrollPosition(position)
        publishProgress(force: true)
    }

    func seek(toProgress newProgress: Double) {
        let clamped = min(max(newProgress, 0), 1)
        seek(to: CGFloat(clamped) * maxPosition)
    }

    func updateFromManualScroll(_ newPosition: CGFloat) {
        guard !isPlaying else { return }
        pendingSeekOffset = 0
        position = clampPosition(newPosition)
        reachedEnd = (maxPosition > 0 && position >= maxPosition - 0.5)
        publishProgress(force: false)
    }

    func updateMetrics(maxPosition: CGFloat, viewportHeight: CGFloat) {
        self.maxPosition = max(1, maxPosition)
        self.viewportHeight = max(100, viewportHeight)
        self.position = clampPosition(self.position)
        surface?.displayScrollPosition(self.position)
        publishProgress(force: true)
    }

    private func clampPosition(_ value: CGFloat) -> CGFloat {
        min(max(0, value), maxPosition)
    }

    private func publishProgress(force: Bool) {
        let newProgress = maxPosition > 0 ? min(max(Double(position / maxPosition), 0), 1) : 0
        if force || abs(newProgress - lastPublishedProgress) >= 0.002 {
            lastPublishedProgress = newProgress
            progress = newProgress
        }
    }

    private func ensureDisplayLinkRunning() {
        guard displayLink == nil else { return }
        lastTimestamp = nil
        let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    @objc private func handleFrame(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt: CGFloat
        if let last = lastTimestamp {
            dt = CGFloat(min(max(now - last, 1.0 / 240.0), 0.1))
        } else {
            dt = 1.0 / 60.0
        }
        lastTimestamp = now

        var changed = false

        if isPlaying {
            position += CGFloat(speed) * dt
            changed = true
        }

        if abs(pendingSeekOffset) > 0.3 {
            let smoothing = min(1.0, dt * 14.0)
            let step = pendingSeekOffset * smoothing
            position += step
            pendingSeekOffset -= step
            changed = true
        } else if pendingSeekOffset != 0 {
            position += pendingSeekOffset
            pendingSeekOffset = 0
            changed = true
        }

        if changed {
            position = clampPosition(position)
            surface?.displayScrollPosition(position)
            publishProgress(force: false)

            if isPlaying && maxPosition > 1 && position >= maxPosition - 0.5 {
                position = maxPosition
                pendingSeekOffset = 0
                reachedEnd = true
                isPlaying = false
                surface?.setManualScrollingEnabled(true)
                publishProgress(force: true)
                stopDisplayLink()
                return
            }
        }

        if !isPlaying && abs(pendingSeekOffset) <= 0.3 {
            pendingSeekOffset = 0
            publishProgress(force: true)
            stopDisplayLink()
        }
    }
}