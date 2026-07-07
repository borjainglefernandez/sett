# sett v2 — Implementation Contracts

Read this FULLY before writing code. The design docs live at:
`/private/tmp/claude-501/-Users-borja-Projects/ef5ed7e3-d912-4fd7-b1e9-9caf91c457fb/scratchpad/design-{client,ux,gamification,backend}.md`

## Ground rules
- Swift: Swift 6 syntax, `@Observable` (never ObservableObject), no third-party deps, no Combine.
- The Mac has NO working Xcode/SwiftPM right now (broken CLT). You CANNOT run `swift build`/`swift test`.
  Verify each Swift file with `swiftc -parse <file>` (syntax only) and be rigorous about types by hand.
- Write tests with **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`). They run later.
- Weights are ALWAYS integer grams (`weightGrams: Int`). Display conversion via `Units` (SettCore/Models/Enums.swift).
- All engine code is PURE: value-type inputs (`SetSample` etc. in Engine/EngineTypes.swift), no SwiftData imports
  outside `SampleExtractor`/`ProgressionReconciler`/seeders.
- SwiftData models: see Models/Models.swift. Soft deletes: filter `deletedAt == nil` everywhere.
- App target: everything under `Sett/`. Theme tokens/haptics: `Sett/Theme/SettTheme.swift`
  (SettColor, Aura, PowerNumeral, .settCard(), Haptics). Stores: `Sett/App/*.swift` — READ THEM; they compile against you.

## Engine APIs that MUST exist with these exact signatures (SettCore/Sources/SettCore/Engine/)

```swift
public enum ProgressEngine {
    /// Epley with reps capped at 12: w * (1 + min(r,12)/30). Rounded to Int grams.
    public static func e1RMGrams(weightGrams: Int, reps: Int) -> Int
    /// Strict previous-calendar-bucket net for one exercise (nil = all exercises).
    public static func netSummary(samples: [SetSample], exerciseID: UUID?, period: Period,
                                  containing date: Date, calendar: Calendar) -> NetSummary
    /// Net per exercise for the bucket containing `date`.
    public static func perExerciseNets(samples: [SetSample], period: Period,
                                       containing date: Date, calendar: Calendar) -> [UUID: NetSummary]
    /// This workout's volume/reps minus the previous same-exercise sessions' (workout-level rollup).
    public static func workoutNet(samples: [SetSample], workoutID: UUID) -> NetSummary
    /// Best e1RM per distinct workout session, chronological, for charts.
    public static func bestE1RMSeries(samples: [SetSample], exerciseID: UUID) -> [(date: Date, e1RMGrams: Int)]
    /// Total volume (gram·reps) per bucket, chronological, last `count` buckets ending at `date`.
    public static func volumeSeries(samples: [SetSample], period: Period, endingAt date: Date,
                                    count: Int, calendar: Calendar) -> [(bucket: BucketKey, volumeGrams: Int)]
    public static func bucketKey(for date: Date, period: Period, calendar: Calendar) -> BucketKey
}

public enum StreakEngine {
    /// Consecutive completed ISO weeks (before the week containing asOf) with >= minDaysPerWeek
    /// distinct workout days; the in-progress week extends but never breaks.
    public static func streakWeeks(workoutDates: [Date], minDaysPerWeek: Int,
                                   calendar: Calendar, asOf: Date) -> Int
}

public enum GoalEvaluator {
    public static func progress(goal: GoalSample, setSamples: [SetSample], workoutSamples: [WorkoutSample],
                                calendar: Calendar, asOf: Date) -> GoalProgress
}
```

## Progression API (SettCore/Sources/SettCore/Progression/)

```swift
public struct BadgeGrant: Sendable, Hashable {
    public let key: String
    public let earnedAt: Date
    public let valueSnapshot: Int
    public let workoutID: UUID?
    public let exerciseID: UUID?
}

public struct ProgressionSnapshot: Sendable {
    public let powerLevel: Int
    public let allTimePeakPL: Int          // max(previous peak, current)
    public let strengthScore: Int
    public let weeklyVolumeLb: Int
    public let consistencyMultiplier: Double
    public let streakWeeks: Int
    public let characterXP: [CharacterKey: Int]
    public let characterLevels: [CharacterKey: Int]  // from 100 * L^1.8 cumulative curve
    public let tiers: [CharacterKey: TransformationTier]
    public let badges: [BadgeGrant]        // ALL currently-earned badges (derived, idempotent)
    public let rivalPL: Int                // Vexeth's scripted PL as of now
    public let rivalForm: Int              // 1...3
}

public struct ProgressionInput: Sendable {
    public let sets: [SetSample]
    public let workouts: [WorkoutSample]
    public let sleep: [SleepSample]
    public let goals: [GoalSample]
    public let previousPeakPL: Int
    public let firstWorkoutDate: Date?     // anchors Vexeth's pacing script
    // include an init with all fields
}

public enum ProgressionEngine {
    /// Pure + deterministic. Implements the full gamification design doc:
    /// effective sets, qualifying workouts, PR verification (provisional/verified),
    /// PL = round((4*SS + 8*sqrt(WVL)) * CM), XP economy + anti-cheese, all 30 badges,
    /// tier gates (level + keystone), Vexeth pacing (startPL + weeklyGrowth per week since
    /// firstWorkoutDate; form advances each time user PL first exceeds rivalPL, max forms).
    public static func compute(input: ProgressionInput, config: ProgressionConfig,
                               calendar: Calendar, asOf: Date) -> ProgressionSnapshot
}

/// SwiftData bridge: extract samples, compute, reconcile BadgeAward rows
/// (insert new grants, soft-delete revoked), update SaiyanState cache, save.
@MainActor
public enum ProgressionReconciler {
    @discardableResult
    public static func reconcile(context: ModelContext, config: ProgressionConfig) throws -> ProgressionSnapshot
}
```

## Demo data (SettCore/Sources/SettCore/Demo/DemoData.swift)

```swift
@MainActor
public enum DemoData {
    /// DEBUG hook: seeds only when no finished workouts exist.
    public static func seedIfRequested(context: ModelContext)
    /// ~6 months of realistic data. Deterministic (seeded RNG).
    public static func seed(context: ModelContext, monthsBack: Int)
}
```

## App views that MUST exist (referenced by RootView / stores)
- `HomeTabView`, `TrainTabView`, `ProgressTabView`, `PowerTabView` — root of each tab, own NavigationStack.
- `ActiveWorkoutView` — full-screen session UI (reads `WorkoutSessionStore` from environment).
- `WorkoutSummaryView(summary: WorkoutSummaryData)` — the Power Scan.
- `SettingsView` — sheet from Home gear.
- Environment objects available: `AppServices`, `WorkoutSessionStore`, `ProgressionStore` (via `.environment`),
  plus `\.modelContext` (SwiftData `.modelContainer` is installed at the root).

## Commentary (already implemented — SettCore/AI/Commentary.swift)
`CommentaryFacts`, `CommentaryFallback.generate(facts:) -> (String, InsightSource)`,
`WorkoutCommentator.generate(facts:) async` behind `#if canImport(FoundationModels)`.

## Backend (backend/)
FastAPI per design-backend.md. Python 3.12 via uv. Tests: pytest + httpx AsyncClient + aiosqlite
(SQLite for tests, Postgres in prod via DATABASE_URL). Must include: auth (SIWA verify mocked in tests,
invite redemption), cursor sync push/pull with sync_seq, oura endpoints (httpx mocked), digest pipeline
(anthropic client injected/mocked), gyms nearby + chamber logs, friends. Alembic migrations,
docker-compose.prod.yml + Dockerfile + GitHub Actions workflow matching the design doc.
