import SwiftUI
import SettCore

// MARK: - BreathingAura

/// The slow "idle aura" behind character art: a blurred aura-gradient circle
/// breathing between 1.0↔1.06 scale and 0.5↔0.7 opacity on a 3 s ease loop.
/// Static (no animation) under Reduce Motion.
struct BreathingAura: View {
    let gradient: LinearGradient

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    init(gradient: LinearGradient = Aura.cyan) {
        self.gradient = gradient
    }

    var body: some View {
        Circle()
            .fill(gradient)
            .blur(radius: 20)
            .scaleEffect(reduceMotion ? 1.0 : (isBreathing ? 1.06 : 1.0))
            .opacity(reduceMotion ? 0.6 : (isBreathing ? 0.7 : 0.5))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - AuraBurstView

/// One-shot celebration burst: 32 particles fly out radially with gravity and
/// opacity decay over 0.8 s from the moment the view appears.
/// Gold for earned moments, cyan otherwise. Draws nothing under Reduce Motion.
struct AuraBurstView: View {
    let gold: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate: Date = .now
    /// Flips true once the burst is spent so the driving TimelineView unmounts (below).
    @State private var finished = false

    private let particles: [Particle]

    private static let duration: TimeInterval = 0.8
    private static let gravity: Double = 220
    private static let particleCount = 32

    init(gold: Bool) {
        self.gold = gold
        self.particles = Self.makeParticles()
    }

    var body: some View {
        // `finished` collapses the burst to nothing once it's spent. TimelineView(.animation)
        // redraws every frame for as long as it is mounted and never stops on its own, so a
        // burst left in the view tree pins a CPU core the entire time its surface is visible.
        // Self-terminating here means every call site is safe by construction — no one has to
        // remember to gate or remove the burst (this class of bug bit the app repeatedly).
        if reduceMotion || finished {
            Color.clear
                .allowsHitTesting(false)
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    guard elapsed >= 0, elapsed <= Self.duration else { return }
                    let progress = elapsed / Self.duration
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let color = gold ? SettColor.saiyanGold : SettColor.heroCyan
                    for particle in particles {
                        let distance = particle.speed * elapsed
                        let drop = 0.5 * Self.gravity * elapsed * elapsed
                        let x = center.x + CGFloat(cos(particle.angle) * distance)
                        let y = center.y + CGFloat(sin(particle.angle) * distance + drop)
                        let diameter = CGFloat(particle.diameter)
                        let rect = CGRect(x: x - diameter / 2, y: y - diameter / 2,
                                          width: diameter, height: diameter)
                        context.opacity = 1 - progress
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .seconds(Self.duration + 0.15))
                finished = true
            }
        }
    }

    // MARK: Particles (deterministic — same burst every time)

    private struct Particle: Sendable {
        let angle: Double     // radians
        let speed: Double     // pt/s radial velocity
        let diameter: Double  // 2–5 pt per the design spec
    }

    private static func makeParticles() -> [Particle] {
        var generator = SplitMix64(seed: 0x5E77_AB01)
        return (0..<particleCount).map { index in
            let baseAngle = Double(index) / Double(particleCount) * 2 * .pi
            return Particle(
                angle: baseAngle + Double.random(in: -0.12...0.12, using: &generator),
                speed: Double.random(in: 70...170, using: &generator),
                diameter: Double.random(in: 2...5, using: &generator)
            )
        }
    }

    private struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}
