import SwiftUI
import SwiftData
import UIKit
import SettCore

// MARK: - Directive Panel (Dark Chamber v3 — the day's NON-workout asks)

/// `TODAY'S DIRECTIVES` — the day's asks that DON'T start a workout: log
/// bodyweight (and, later, sleep / rest notes). The workout-start rows moved
/// out entirely: the doorway hero above IS the start affordance, so a "Start
/// Push Day 0/1" row here was the same call a third time. Each row's trailing
/// control runs iron GO → pulsing gold CLAIM (a sanctioned reward pulse) →
/// dimmed CLAIMED ✓. Claims persist per local day under `sett.directives.<yyyymmdd>`.
/// If a day ever has no non-workout asks the panel hides itself.
struct DirectivePanel: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    @Query private var todaysBodyweight: [BodyweightEntry]
    @Query private var latestBodyweight: [BodyweightEntry]

    @State private var claimedKeys: Set<String>
    @State private var isLoggingBodyweight = false
    /// The key claimed THIS moment — drives the row's gold burst + stamp punch,
    /// then clears (~0.9 s) so the dormant dim can settle in.
    @State private var burstKey: String?

    private enum DirectiveKey {
        static let bodyweight = "bodyweight"
    }

    init() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let bodyweightFilter = #Predicate<BodyweightEntry> {
            $0.deletedAt == nil && $0.loggedAt >= dayStart && $0.loggedAt < dayEnd
        }
        _todaysBodyweight = Query(filter: bodyweightFilter)

        // Latest entry overall, to prefill the log sheet (same pattern as Home).
        let anyBodyweight = #Predicate<BodyweightEntry> { $0.deletedAt == nil }
        var latestDescriptor = FetchDescriptor<BodyweightEntry>(
            predicate: anyBodyweight,
            sortBy: [SortDescriptor(\BodyweightEntry.loggedAt, order: .reverse)]
        )
        latestDescriptor.fetchLimit = 1
        _latestBodyweight = Query(latestDescriptor)

        _claimedKeys = State(initialValue: Self.loadClaims())
    }

    // MARK: Claims (per local day)

    /// One claim list per local day: `sett.directives.<yyyymmdd>`.
    private static var dayKey: String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "sett.directives.%04d%02d%02d",
                      comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private static func loadClaims() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dayKey) ?? [])
    }

    // MARK: The directives (non-workout asks only)

    private struct Directive: Identifiable {
        let key: String
        let title: String
        let progress: String
        let isMet: Bool
        var id: String { key }
    }

    private var directives: [Directive] {
        let weighed = todaysBodyweight.isEmpty ? 0 : 1
        return [
            Directive(key: DirectiveKey.bodyweight, title: bodyweightTitle,
                      progress: "\(weighed)/1", isMet: weighed == 1),
        ]
    }

    /// The old bodyweight chip's grammar folded into the row — the glanceable
    /// latest reading ("· 182.4 lb 1d ago") survives the chip's removal from Home.
    private var bodyweightTitle: String {
        guard let latest = latestBodyweight.first else { return "Log bodyweight" }
        let value = BodyweightFormat.valueWithUnit(grams: latest.weightGrams,
                                                   unit: services.settings.unit)
        return "Log bodyweight · \(value) \(BodyweightFormat.relativeDay(latest.loggedAt))"
    }

    // MARK: Body

    var body: some View {
        // Empty is possible once sleep/rest asks land conditionally — hide rather
        // than render a titled card with nothing under it.
        if !directives.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("TODAY'S DIRECTIVES", tint: SettColor.bone)
                VStack(spacing: 12) {
                    ForEach(directives) { directive in
                        row(directive)
                    }
                }
            }
            .hudCard()
            // The panel is built once inside the persistent Home tab, so init's live
            // dayKey freezes at first appearance. Re-seed the claim set when the app
            // returns to foreground or the clock crosses local midnight, so a session
            // left alive across midnight shows the new day's (empty) claims, not stale ✓.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { claimedKeys = Self.loadClaims() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                claimedKeys = Self.loadClaims()
            }
            .sheet(isPresented: $isLoggingBodyweight) {
                BodyweightLogSheet(latest: latestBodyweight.first)
            }
        }
    }

    @ViewBuilder
    private func row(_ directive: Directive) -> some View {
        let isClaimed = claimedKeys.contains(directive.key)
        HStack(spacing: 12) {
            Text(directive.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(SettColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(directive.progress)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettColor.ash)
            control(for: directive, isClaimed: isClaimed)
        }
        // A freshly claimed row holds full brightness while its burst plays,
        // then eases down to the dormant dim.
        .opacity(isClaimed && burstKey != directive.key ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(for: directive, isClaimed: isClaimed))
    }

    /// The three-state control: iron GO → pulsing gold CLAIM → CLAIMED ✓.
    @ViewBuilder
    private func control(for directive: Directive, isClaimed: Bool) -> some View {
        if isClaimed {
            ClaimedStamp(justClaimed: burstKey == directive.key)
                .overlay {
                    if burstKey == directive.key {
                        // One-shot gold payoff centered on the trailing control.
                        AuraBurstView(gold: true)
                            .frame(width: 120, height: 120)
                    }
                }
        } else if directive.isMet {
            ClaimCapsule { claim(directive.key) }
        } else {
            Button {
                go(directive.key)
            } label: {
                Text("GO")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.bone)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(SettColor.cardNested, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(PressableSlabStyle(haptic: .light))
            .accessibilityLabel("Go: \(directive.title)")
        }
    }

    private func accessibilityText(for directive: Directive, isClaimed: Bool) -> String {
        let state = isClaimed ? "claimed" : (directive.isMet ? "complete, ready to claim" : "in progress")
        return "\(directive.title), \(directive.progress), \(state)"
    }

    // MARK: Actions

    private func go(_ key: String) {
        if key == DirectiveKey.bodyweight { isLoggingBodyweight = true }
    }

    private func claim(_ key: String) {
        Haptics.success()
        burstKey = key
        withAnimation(.easeOut(duration: 0.25)) {
            _ = claimedKeys.insert(key)
        }
        UserDefaults.standard.set(claimedKeys.sorted(), forKey: Self.dayKey)
        // Let the 0.8 s burst finish, then release it (a spent TimelineView would
        // keep ticking invisibly) and ease the row down to its dormant dim.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard burstKey == key else { return }
            withAnimation(.easeOut(duration: 0.25)) { burstKey = nil }
        }
    }
}

// MARK: - The CLAIMED ✓ stamp

/// Lands with a 1.3 → 1.0 spring punch on a fresh claim; older claims (and
/// Reduce Motion) render static.
private struct ClaimedStamp: View {
    let justClaimed: Bool

    @State private var stampScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("CLAIMED ✓")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(SettColor.ash)
            .scaleEffect(stampScale)
            .onAppear {
                guard justClaimed, !reduceMotion else { return }
                stampScale = 1.3
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { stampScale = 1 }
            }
    }
}

// MARK: - The pulsing gold CLAIM capsule

/// Opacity pulse, repeat-forever; static at full opacity under Reduce Motion.
/// One of the few sanctioned uses of gold outside the sacred number.
private struct ClaimCapsule: View {
    let action: () -> Void

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text("CLAIM")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.etch)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Aura.gold, in: Capsule())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .opacity(reduceMotion ? 1 : (pulsing ? 1 : 0.55))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityLabel("Claim directive reward")
    }
}
