import SwiftUI
import SwiftData
import SettCore

/// The full trophy room: every badge in progression_config.json in a 3-column
/// grid, rarest first. Earned = gold medallion; unearned = grayscale outline
/// with its criteria visible — the locked grid IS the empty state.
struct BadgeCaseView: View {
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
            LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                ForEach(orderedBadges, id: \.key) { definition in
                    badgeCell(definition)
                }
            }
            .padding(16)
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

    private func earnedCell(_ definition: ProgressionConfig.BadgeDef, award: BadgeAward) -> some View {
        Button {
            selectedAward = award
            Haptics.light()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Aura.gold)
                    Image(systemName: "medal.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                Text(definition.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(definition.name), \(definition.rarity.rawValue) badge, earned")
    }

    private func unearnedCell(_ definition: ProgressionConfig.BadgeDef) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(Color.gray.opacity(0.45), lineWidth: 2)
                Image(systemName: "medal.fill")
                    .font(.title2)
                    .foregroundStyle(Color.gray.opacity(0.45))
            }
            .frame(width: 64, height: 64)
            Text(definition.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(criteriaText(for: definition.key))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .top)
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

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                BreathingAura(gradient: Aura.gold)
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(Aura.gold)
                    .frame(width: 96, height: 96)
                Image(systemName: "medal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 4) {
                Text("Earned \(award.earnedAt.formatted(date: .long, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if award.valueSnapshot > 0 {
                    Text("Recorded value: \(award.valueSnapshot.formatted())")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var rarityCapsule: some View {
        Text((definition?.rarity.rawValue ?? BadgeRarity.bronze.rawValue).capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(rarityColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(rarityColor.opacity(0.15), in: Capsule())
    }

    private var rarityColor: Color {
        switch definition?.rarity ?? .bronze {
        case .bronze: .brown
        case .silver: .gray
        case .gold, .legendary: SettColor.saiyanGold
        }
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
    case "scanner_breaker": "Push your power level over 9000"
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
    // Zia — sleep & recovery
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
