import SwiftUI
import SwiftData
import SettCore

// MARK: - Directive Panel (Dark Chamber v3 — the ONLY quest surface in the app)

/// `TODAY'S DIRECTIVES` — exactly three imperative rows computed from today's
/// data: enter the chamber, log bodyweight, feed the Scanner ten sets. Each
/// row carries a three-state trailing control: iron GO → pulsing gold CLAIM
/// (a sanctioned reward pulse) → dimmed CLAIMED ✓. Claims persist per local
/// day under `sett.directives.<yyyymmdd>`.
struct DirectivePanel: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services

    @Query private var todaysWorkouts: [Workout]
    @Query private var todaysBodyweight: [BodyweightEntry]
    @Query private var todaysSets: [SetEntry]
    @Query private var latestBodyweight: [BodyweightEntry]
    @Query private var routines: [Routine]

    @State private var claimedKeys: Set<String>
    @State private var isLoggingBodyweight = false

    private enum DirectiveKey {
        static let chamber = "chamber"
        static let bodyweight = "bodyweight"
        static let scanner = "scanner"
    }

    init() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let workoutFilter = #Predicate<Workout> {
            $0.endedAt != nil && $0.deletedAt == nil
                && $0.startedAt >= dayStart && $0.startedAt < dayEnd
        }
        _todaysWorkouts = Query(filter: workoutFilter)

        let bodyweightFilter = #Predicate<BodyweightEntry> {
            $0.deletedAt == nil && $0.loggedAt >= dayStart && $0.loggedAt < dayEnd
        }
        _todaysBodyweight = Query(filter: bodyweightFilter)

        let setFilter = #Predicate<SetEntry> {
            $0.deletedAt == nil && $0.completedAt >= dayStart && $0.completedAt < dayEnd
        }
        _todaysSets = Query(filter: setFilter)

        // Latest entry overall, to prefill the log sheet (same pattern as Home).
        let anyBodyweight = #Predicate<BodyweightEntry> { $0.deletedAt == nil }
        var latestDescriptor = FetchDescriptor<BodyweightEntry>(
            predicate: anyBodyweight,
            sortBy: [SortDescriptor(\BodyweightEntry.loggedAt, order: .reverse)]
        )
        latestDescriptor.fetchLimit = 1
        _latestBodyweight = Query(latestDescriptor)

        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _routines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])

        _claimedKeys = State(initialValue: Self.loadClaims())
    }

    /// The routine you'd start now (weekday match or rotation next-up), so the chamber
    /// directive starts the planned session instead of a blank one.
    private var todaysRoutine: Routine? {
        Scheduling.nextRoutine(routines, settings: services.settings)
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

    // MARK: The three directives

    private struct Directive: Identifiable {
        let key: String
        let title: String
        let progress: String
        let isMet: Bool
        var id: String { key }
    }

    private var directives: [Directive] {
        let trained = todaysWorkouts.isEmpty ? 0 : 1
        let weighed = todaysBodyweight.isEmpty ? 0 : 1
        let setCount = min(todaysSets.count, 10)
        return [
            Directive(key: DirectiveKey.chamber,
                      title: todaysRoutine.map { "Start \($0.name)" } ?? "Enter the chamber",
                      progress: "\(trained)/1", isMet: trained == 1),
            Directive(key: DirectiveKey.bodyweight, title: "Log bodyweight",
                      progress: "\(weighed)/1", isMet: weighed == 1),
            Directive(key: DirectiveKey.scanner, title: "Feed the Scanner",
                      progress: "\(setCount)/10", isMet: setCount >= 10),
        ]
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TODAY'S DIRECTIVES")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(SettColor.bone)
            VStack(spacing: 12) {
                ForEach(directives) { directive in
                    row(directive)
                }
            }
        }
        .settCard()
        .sheet(isPresented: $isLoggingBodyweight) {
            BodyweightLogSheet(latest: latestBodyweight.first)
        }
    }

    @ViewBuilder
    private func row(_ directive: Directive) -> some View {
        let isClaimed = claimedKeys.contains(directive.key)
        HStack(spacing: 12) {
            Text(directive.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SettColor.bone)
            Spacer(minLength: 8)
            Text(directive.progress)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettColor.ash)
            control(for: directive, isClaimed: isClaimed)
        }
        .opacity(isClaimed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(for: directive, isClaimed: isClaimed))
    }

    /// The three-state control: iron GO → pulsing gold CLAIM → CLAIMED ✓.
    @ViewBuilder
    private func control(for directive: Directive, isClaimed: Bool) -> some View {
        if isClaimed {
            Text("CLAIMED ✓")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettColor.ash)
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
            .buttonStyle(.plain)
            .accessibilityLabel("Go: \(directive.title)")
        }
    }

    private func accessibilityText(for directive: Directive, isClaimed: Bool) -> String {
        let state = isClaimed ? "claimed" : (directive.isMet ? "complete, ready to claim" : "in progress")
        return "\(directive.title), \(directive.progress), \(state)"
    }

    // MARK: Actions

    private func go(_ key: String) {
        switch key {
        case DirectiveKey.chamber:
            startTodaysSession()
        case DirectiveKey.bodyweight:
            isLoggingBodyweight = true
        case DirectiveKey.scanner:
            if session.activeWorkout == nil {
                startTodaysSession()
            } else {
                session.isPresentingWorkout = true
            }
        default:
            break
        }
    }

    /// Start today's scheduled routine if one exists (feeding its planned sets),
    /// otherwise a blank quick-start.
    private func startTodaysSession() {
        if let routine = todaysRoutine {
            session.start(routine: routine)
        } else {
            session.quickStart()
        }
    }

    private func claim(_ key: String) {
        Haptics.success()
        withAnimation(.easeOut(duration: 0.25)) {
            _ = claimedKeys.insert(key)
        }
        UserDefaults.standard.set(claimedKeys.sorted(), forKey: Self.dayKey)
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
        .buttonStyle(.plain)
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
