import Foundation

/// How hard the wave's strands swing over time: a made-up beat, not the audio
/// (which the players do not share). Seeded per track, so every song gets its own
/// tempo, accents, and shimmer, and the same song always moves the same way.
struct PulseRhythm: Sendable, Equatable {
    static let tempoRange: ClosedRange<Double> = 93...129

    let seed: UInt64
    /// Beats per minute, within `tempoRange`.
    let tempo: Double
    /// Strength of each beat in a four-beat bar, the downbeat strongest.
    private let accents: [Double]
    /// How quickly a beat dies away, per second.
    private let decay: Double

    init(seed: UInt64) {
        self.seed = seed
        var random = SplitMix64(seed: seed)
        tempo = Self.tempoRange.lowerBound
            + random.nextUnit() * (Self.tempoRange.upperBound - Self.tempoRange.lowerBound)
        accents = [1, 0.55 + 0.35 * random.nextUnit(), 0.7 + 0.25 * random.nextUnit(), 0.5 + 0.35 * random.nextUnit()]
        decay = 5 + 4 * random.nextUnit()
    }

    /// One level per bar, each within 0…1, at `time` seconds on any clock.
    func levels(at time: TimeInterval, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let beatLength = 60 / tempo
        return (0..<count).map { index in
            let bar = BarVoice(seed: seed, index: index)
            // Each bar hears the beat a moment after its left neighbour, so it
            // ripples outward across the row.
            let local = max(time - Double(index) * 0.03, 0)
            let beatIndex = Int((local / beatLength).rounded(.down))
            let sinceBeat = local - Double(beatIndex) * beatLength
            // Sharp attack (20 ms), then an exponential fall.
            let attack = min(sinceBeat / 0.02, 1)
            let envelope = attack * exp(-sinceBeat * decay) * accents[beatIndex & 3]

            let shimmer = 0.5
                + 0.3 * sin(2 * .pi * bar.frequencies.0 * time + bar.phases.0)
                + 0.2 * sin(2 * .pi * bar.frequencies.1 * time + bar.phases.1)

            // Lower-indexed bars follow the beat more, the rest mostly shimmer.
            let beatWeight = count == 1 ? 0.7 : 0.8 - 0.5 * Double(index) / Double(count - 1)
            let level = 0.1 + 0.9 * (beatWeight * envelope + (1 - beatWeight) * shimmer)
            return min(max(level, 0), 1)
        }
    }

    /// One bar's shimmer, drawn from the track's seed and the bar's position.
    private struct BarVoice {
        var frequencies: (Double, Double)
        var phases: (Double, Double)

        init(seed: UInt64, index: Int) {
            var random = SplitMix64(seed: seed ^ (UInt64(index + 1) &* 0x9e37_79b9_7f4a_7c15))
            frequencies = (1 + 3 * random.nextUnit(), 1 + 3 * random.nextUnit())
            phases = (2 * .pi * random.nextUnit(), 2 * .pi * random.nextUnit())
        }
    }
}

/// A small, fast, well-mixed pseudo-random generator; the same seed always
/// yields the same sequence.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }
}
