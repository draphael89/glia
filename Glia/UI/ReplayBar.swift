import SwiftUI

/// Bottom-center replay control. Idle: a quiet "Replay growth" pill.
/// Active: play/pause, a scrubber with the weekly-creation histogram
/// etched into the track, the cursor date, and an exit button.
struct ReplayBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack {
            Spacer()
            if model.replay.isActive {
                activeBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                idlePill
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 18)
        .animation(.spring(duration: 0.32), value: model.replay.isActive)
    }

    private var idlePill: some View {
        Button {
            model.clearFocus()
            model.replay.play()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.fill").font(.system(size: 10))
                Text("Replay growth").font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var activeBar: some View {
        HStack(spacing: 14) {
            Button {
                model.replay.togglePlay()
            } label: {
                Image(systemName: model.replay.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.replay.isPlaying ? "Pause replay" : "Play replay")

            ScrubTrack(model: model)
                .frame(width: 380, height: 34)

            Text(cursorLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
                .contentTransition(.numericText())

            Button {
                model.replay.exitReplay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit replay")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .panelBackground(cornerRadius: 14)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var cursorLabel: String {
        guard let cursor = model.replay.cursor else { return "" }
        return cursor.formatted(.dateTime.year().month(.abbreviated).day())
    }
}

/// Histogram + scrubber in one strip.
private struct ScrubTrack: View {
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let bars = weeklyHistogram()
            let progress = model.replay.progress
            ZStack(alignment: .leading) {
                // histogram
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { i, value in
                        let fraction = bars.count > 1 ? Double(i) / Double(bars.count - 1) : 0
                        RoundedRectangle(cornerRadius: 1)
                            .fill(fraction <= progress ? Theme.accent.opacity(0.75)
                                                       : Color.white.opacity(0.14))
                            .frame(height: max(2, value * (geo.size.height - 8)))
                            .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: geo.size.height, alignment: .bottom)

                // playhead
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: geo.size.height)
                    .offset(x: geo.size.width * progress - 1)
                    .shadow(color: Theme.accent.opacity(0.8), radius: 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        model.replay.scrub(to: g.location.x / geo.size.width)
                    }
            )
        }
        // The drag-to-seek track was invisible to VoiceOver and had no keyboard seek —
        // the only way to scrub. Expose it as one adjustable element so assistive tech
        // (and ⌃⌥←/→) can move the playhead in 5% steps.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Replay timeline")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            let cur = model.replay.progress
            switch direction {
            case .increment: model.replay.scrub(to: min(1, cur + step))
            case .decrement: model.replay.scrub(to: max(0, cur - step))
            @unknown default: break
            }
        }
    }

    /// Spoken position for VoiceOver — the cursor date if we have one, else a percent.
    private var accessibilityValue: String {
        if let cursor = model.replay.cursor {
            return cursor.formatted(.dateTime.year().month(.abbreviated).day())
        }
        return "\(Int((model.replay.progress * 100).rounded())) percent"
    }

    private func weeklyHistogram() -> [Double] {
        guard let range = model.replay.range else { return [] }
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        let buckets = max(24, min(80, Int(total / 604_800)))   // ~weekly
        var counts = [Double](repeating: 0, count: buckets)
        for node in model.graph.nodes {
            guard let d = node.createdDate else { continue }
            let f = d.timeIntervalSince(range.lowerBound) / total
            let b = min(buckets - 1, max(0, Int(f * Double(buckets))))
            counts[b] += 1
        }
        let peak = max(counts.max() ?? 1, 1)
        return counts.map { $0 / peak }
    }
}
