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

    /// node.ID -> birth moment (media time), for bloom-in. Keyed by STABLE node id,
    /// NOT array index: apply() replaces `graph` (JSON order) on every live poll, so
    /// an index key would light the wrong pages after any insert/remove/reorder.
    private(set) var birthTimes: [Int: CFTimeInterval] = [:]

    /// Bumped by user actions (play/scrub) so a post-completion auto-exit scheduled
    /// earlier can tell it's stale and not wipe a scrub made during the hold window.
    private var generation = 0

    private var timer: Timer?
    private weak var model: AppModel?
    /// One full replay lasts this long regardless of history span.
    private let playDuration: TimeInterval = 14
    /// Creation dates sorted ascending — playback advances through EVENTS
    /// at constant rate, so a back-loaded history doesn't mean a dead first
    /// act and a frantic finale.
    private var sortedDates: [Date] = []
    private var playhead: Double = 0   // fractional index into sortedDates

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
        sortedDates = model.graph.nodes.compactMap(\.createdDate).sorted()
        guard let lo = sortedDates.first, let hi = sortedDates.last, lo < hi else {
            range = nil; return
        }
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
        generation += 1
        model.setReplayRendering(true)
        // align the playhead with wherever the cursor currently sits
        if let current = cursor {
            playhead = Double(sortedDates.firstIndex(where: { $0 > current }) ?? sortedDates.count)
        }
        let step = Double(sortedDates.count) / (playDuration * 30)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(step: step) }
        }
    }

    private func tick(step: Double) {
        guard let model, let range, let current = cursor, !sortedDates.isEmpty else { return }
        playhead = min(playhead + step, Double(sortedDates.count))
        let idx = min(Int(playhead), sortedDates.count - 1)
        let next = min(max(sortedDates[idx], current), range.upperBound)
        markBirths(from: current, to: next)
        cursor = next
        model.replayChanged()
        if playhead >= Double(sortedDates.count) {
            pause()
            // hold the completed picture; keep blooms fading naturally. Capture the
            // generation so a scrub during the hold (which pauses too) cancels this.
            let gen = generation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if self.generation == gen && !self.isPlaying { self.exitReplay() }
            }
        }
    }

    /// Live mode: bloom pages that just arrived from the backend poll.
    func noteLiveBirths(indices: [Int]) {
        guard !indices.isEmpty, let model else { return }
        let now = CACurrentMediaTime()
        // Resolve to stable ids against the just-installed graph.
        for i in indices where i < model.graph.nodes.count { birthTimes[model.graph.nodes[i].id] = now }
        model.setReplayRendering(true)
        model.replayChanged()
        // wind the render loop back down once the blooms settle
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if !self.isPlaying && !self.isActive { self.model?.setReplayRendering(false) }
        }
    }

    private func markBirths(from: Date, to: Date) {
        guard let model else { return }
        let now = CACurrentMediaTime()
        for node in model.graph.nodes {
            guard let d = node.createdDate else { continue }
            if d > from && d <= to { birthTimes[node.id] = now }
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
        generation += 1   // cancel any pending post-completion auto-exit
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
