import SwiftUI
import SwiftData
import SettCore

/// The full trophy room: every badge in progression_config.json in a 3-column
/// grid, rarest first. Rank reads from the frame material (v3 rarity ladder):
/// earned = engraved gold, earned legendary = prismatic, locked = matte iron
/// in grayscale with its criteria visible — the locked grid IS the empty state.
struct BadgeCaseView: View {
    @Environment(AppServices.self) private var services

    @Environment(ProgressionStore.self) private var progression

    @Query private var awards: [BadgeAward]

    @State private var selectedAward: BadgeAward?

    init() {
        let awardFilter = #Predicate<BadgeAward> { $0.deletedAt == nil }
        _awards = Query(filter: awardFilter, sort: [SortDescriptor(\BadgeAward.earnedAt, order: .reverse)])
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            if orderedBadges.isEmpty {
                EmptyChamber(title: "Badge case unavailable",
                             message: "Couldn't load the trophy room — try again shortly.")
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                    ForEach(orderedBadges, id: \.key) { definition in
                        badgeCell(definition)
                    }
                }
                .padding(16)
            }
        }
        .dungeonBackground()
        .navigationTitle("Badge Case")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedAward) { award in
            BadgeDetailSheet(award: award)
        }
    }

    // MARK: Ordering — rarity descending (legendary → bronze), then name

    private var orderedBadges: [ProgressionConfig.BadgeDef] {
        (progression.config?.badges ?? []).sorted { lhs, rhs in
            let lhsRank = Self.rarityRank(lhs.rarity)
            let rhsRank = Self.rarityRank(rhs.rarity)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            return lhs.name < rhs.name
        }
    }

    private static func rarityRank(_ rarity: BadgeRarity) -> Int {
        BadgeRarity.allCases.firstIndex(of: rarity) ?? 0
    }

    private func award(for key: String) -> BadgeAward? {
        awards.first { $0.badgeKey == key }
    }

    // MARK: Cells

    @ViewBuilder
    private func badgeCell(_ definition: ProgressionConfig.BadgeDef) -> some View {
        if let award = award(for: definition.key) {
            earnedCell(definition, award: award)
        } else {
            unearnedCell(definition)
        }
    }

    /// Earned slot: bone medal on a slab circle; the GOLD lives in the frame
    /// material only — prismatic for legendary.
    private func earnedCell(_ definition: ProgressionConfig.BadgeDef, award: BadgeAward) -> some View {
        Button {
            selectedAward = award
            Haptics.light()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(SettColor.card)
                    Image(systemName: "medal.fill")
                        .font(.title2)
                        .foregroundStyle(SettColor.bone)
                    // Prestige pin — the countable badges never go dead: clearing the
                    // threshold again stamps ×2, ×3… on the same medal.
                    if let count = services.progression.snapshot?.badgeCounts[definition.key],
                       count >= 2 {
                        Text("×\(count)")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(SettColor.etch)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(SettColor.saiyanGold, in: Capsule())
                            .offset(x: 22, y: -22)
                    }
                }
                .frame(width: 64, height: 64)
                Text(definition.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.bone)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SettColor.cardNested))
            .frameMaterial(definition.rarity == .legendary ? .prismatic : .gold)
        }
        .buttonStyle(.plain)
        .accessibilityLabel({
            var label = "\(definition.name), \(definition.rarity.rawValue) badge, earned"
            if let count = services.progression.snapshot?.badgeCounts[definition.key], count >= 2 {
                label += ", earned \(count) times"
            }
            return label
        }())
    }

    /// Locked slot: matte iron frame, grayscale, criteria visible.
    private func unearnedCell(_ definition: ProgressionConfig.BadgeDef) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(SettColor.iron, lineWidth: 2)
                Image(systemName: "medal.fill")
                    .font(.title2)
                    .foregroundStyle(SettColor.iron)
            }
            .frame(width: 64, height: 64)
            Text(definition.name)
                .font(.caption2)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(criteriaText(for: definition.key))
                .font(.caption2)
                .foregroundStyle(SettColor.iron)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SettColor.cardNested))
        .frameMaterial(.iron)
        .grayscale(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(definition.name), locked. \(criteriaText(for: definition.key))")
    }
}

// MARK: - Earned badge detail sheet

private struct BadgeDetailSheet: View {
    let award: BadgeAward

    @Environment(ProgressionStore.self) private var progression

    private var definition: ProgressionConfig.BadgeDef? {
        progression.config?.badge(award.badgeKey)
    }

    private var isLegendary: Bool {
        definition?.rarity == .legendary
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 16) {
            // The reward pulse: gold breathing aura + one-shot gold burst.
            ZStack {
                BreathingAura(gradient: Aura.gold)
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(SettColor.card)
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(medallionRing, lineWidth: 2)
                    .frame(width: 96, height: 96)
                Image(systemName: "medal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(SettColor.bone)
                AuraBurstView(gold: true)
                    .frame(width: 220, height: 220)
            }
            .frame(height: 140)
            .padding(.top, 24)
            Text(definition?.name ?? award.badgeKey)
                .font(.title2.bold())
            rarityCapsule
            Text(criteriaText(for: award.badgeKey))
                .font(.subheadline)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
            VStack(spacing: 4) {
                Text("Earned \(award.earnedAt.formatted(date: .long, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(SettColor.ash)
                if award.valueSnapshot > 0 {
                    Text("Recorded value: \(award.valueSnapshot.formatted())")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.ash)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Gold-material ring — the earned frame; legendary gets the prismatic
    /// blend (static: the shine-sweep stays exclusive to card frames).
    private var medallionRing: AnyShapeStyle {
        if isLegendary {
            return AnyShapeStyle(AngularGradient(
                gradient: Gradient(colors: [
                    SettColor.heroCyan,
                    SettColor.saiyanGold,
                    SettColor.heroCyan,
                ]),
                center: .center
            ))
        }
        return AnyShapeStyle(Aura.gold)
    }

    /// Rarity as a plain word — rank already reads from the frame material,
    /// so no colored label (the v3 rarity-ladder rule).
    private var rarityCapsule: some View {
        StatusChip(definition?.rarity.rawValue ?? BadgeRarity.bronze.rawValue,
                   tint: SettColor.bone)
    }
}

// MARK: - Criteria copy (all 30 badge keys in progression_config.json)

/// Short human-readable earn criteria, shown on locked badges and detail sheets.
func criteriaText(for key: String) -> String {
    switch key {
    // Vego — PRs & power
    case "new_ceiling": "Set your first verified PR"
    case "limit_break": "Reach 10 verified PRs"
    case "walking_legend": "Reach 50 verified PRs"
    case "triple_threat": "Verified PRs in 3 muscle categories in one week"
    case "perfect_form": "Every exercise net-positive in a 4+ exercise workout"
    case "scanner_breaker": "Push your power level past 9,000"
    // Barok — volume
    case "twenty_ton_day": "Lift 20,000 lb in a single workout"
    case "hundred_grand": "Reach 100,000 lb lifetime tonnage"
    case "million_pound_club": "Reach 1,000,000 lb lifetime tonnage"
    case "ten_million": "Reach 10,000,000 lb lifetime tonnage"
    // Nyra — streaks
    case "ignition": "Finish your first qualifying workout"
    case "steady_flame": "Train 2+ days a week for 4 straight weeks"
    case "chamber_regular": "Train 3+ days a week for 4 straight weeks"
    case "chamber_resident": "Train 3+ days a week for 12 straight weeks"
    case "unbroken_year": "Train at least once a week for 52 straight weeks"
    // Torren — goals & adherence
    case "goal_getter": "Complete your first goal"
    case "marksman": "Complete a PR-target goal"
    case "serial_achiever": "Complete 10 goals"
    case "by_the_book": "Log 12 workouts on their planned routine day"
    case "planners_pride": "Hit every planned routine day for 4 straight weeks"
    // Luma — sleep & recovery
    case "lab_partner": "Connect Oura and sync 7 nights"
    case "well_rested": "5 workouts after 80+ sleep scores within 30 days"
    case "recovery_protocol": "Sleep 7+ hours all week and train 3 days in it"
    // Gosi — breadth & dawn
    case "explorer": "Train 20 different exercises"
    case "full_arsenal": "Hit all 6 muscle categories within 7 days"
    case "dawn_patrol": "Start 10 workouts before 7 AM"
    // Zyn — momentum & comebacks
    case "momentum": "5 straight net-positive sessions of the same workout"
    case "midnight_oil": "Start 10 workouts after 9 PM"
    case "return_to_form": "After a 21-day break, train 3 times within 14 days"
    case "reforged": "Match a pre-break PR within 60 days of returning"
    default: "Criteria classified — keep training"
    }
}
