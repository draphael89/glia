import SwiftUI
import Observation

/// Growth replay: scrub or play through the brain's history and watch
/// pages bloom into the settled map in creation order. Pure presentation —
/// positions stay fixed (the map you know), only existence animates.
@MainActor
@Observable
final class ReplayController {
    private(set) var isPlaying = false
    /// nil == live (no replay filter)
    private(set) var cursor: Date?
    private(set) var range: ClosedRange<Date>?

    /// node index -> birth moment expressed as media time, for bloom-in
    private(set) var birthTimes: [Int: CFTimeInterval] = [:]

    private var timer: Timer?
    private weak var model: AppModel?
    /// One full replay lasts this long regardless of history span.
    private let playDuration: TimeInterval = 14

    func attach(model: AppModel) { self.model = model }

    var isActive: Bool { cursor != nil }

    var progress: Double {
        guard let cursor, let range else { return 1 }
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        guard total > 0 else { return 1 }
        return cursor.timeIntervalSince(range.lowerBound) / total
    }

    func recomputeRange() {
        guard let model else { return }
        let dates = model.graph.nodes.compactMap(\.createdDate)
        guard let lo = dates.min(), let hi = dates.max(), lo < hi else { range = nil; return }
        range = lo...hi
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard let model else { return }
        if range == nil { recomputeRange() }
        guard let range else { return }
        // restart from the beginning if at the end or live
        if cursor == nil || cursor! >= range.upperBound {
            cursor = range.lowerBound
            birthTimes.removeAll()
        }
        isPlaying = true
        model.setReplayRendering(true)
        let step = range.upperBound.timeIntervalSince(range.lowerBound) / (playDuration * 30)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(step: step) }
        }
    }

    private func tick(step: TimeInterval) {
        guard let model, let range, let current = cursor else { return }
        let next = min(current.addingTimeInterval(step), range.upperBound)
        markBirths(from: current, to: next)
        cursor = next
        model.replayChanged()
        if next >= range.upperBound {
            pause()
            // hold the completed picture; keep blooms fading naturally
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if !self.isPlaying { self.exitReplay() }
            }
        }
    }

    /// Live mode: bloom pages that just arrived from the backend poll.
    func noteLiveBirths(indices: [Int]) {
        guard !indices.isEmpty else { return }
        let now = CACurrentMediaTime()
        for i in indices { birthTimes[i] = now }
        model?.setReplayRendering(true)
        model?.replayChanged()
        // wind the render loop back down once the blooms settle
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if !self.isPlaying && !self.isActive { self.model?.setReplayRendering(false) }
        }
    }

    private func markBirths(from: Date, to: Date) {
        guard let model else { return }
        let now = CACurrentMediaTime()
        for (i, node) in model.graph.nodes.enumerated() {
            guard let d = node.createdDate else { continue }
            if d > from && d <= to { birthTimes[i] = now }
        }
        // keep the dictionary from growing unbounded during long scrubs
        if birthTimes.count > 800 {
            let cutoff = now - 3
            birthTimes = birthTimes.filter { $0.value > cutoff }
        }
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func scrub(to fraction: Double) {
        guard let model else { return }
        if range == nil { recomputeRange() }
        guard let range else { return }
        pause()
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        cursor = range.lowerBound.addingTimeInterval(total * fraction.clamped(to: 0...1))
        model.setReplayRendering(true)
        model.replayChanged()
    }

    func exitReplay() {
        pause()
        cursor = nil
        birthTimes.removeAll()
        model?.replayChanged()
        model?.setReplayRendering(false)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
