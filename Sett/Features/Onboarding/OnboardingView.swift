import SwiftUI
import AuthenticationServices
import SettCore

/// First-run flow (design-ux §6), six pages: invite code, Sign in with Apple, units,
/// phase, Oura pitch, meet-your-rival. Local-only in this build — the invite code and
/// Apple identity are not verified against a server yet.
///
/// v2: pages are a gated ZStack switch, NOT a paging TabView — the old page style let
/// a swipe skip the invite and phase gates entirely. Day zero now opens under the
/// chamber sky with the same marks the rest of the app wears; the rival reveal is the
/// flow's one crimson moment.
struct OnboardingView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Page: Int, Hashable, CaseIterable {
        case invite, signIn, units, phase, oura, rival
    }

    @State private var page: Page = .invite
    @State private var inviteCode = ""

    var body: some View {
        ZStack(alignment: .top) {
            SettColor.screen.ignoresSafeArea()
            realmGlow
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 18)
                Group {
                    switch page {
                    case .invite: invitePage
                    case .signIn: signInPage
                    case .units: unitsPage
                    case .phase: phasePage
                    case .oura: ouraPage
                    case .rival: rivalPage
                    }
                }
                // RM keeps a plain cross-fade (never nil — pages must not hard-pop).
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                          removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: page)
        .interactiveDismissDisabled()
    }

    /// The chamber sky over day zero — same treatment as home's header glow.
    private var realmGlow: some View {
        Image(ChamberBackground.resolve(services.settings.chamberBackground).assetName)
            .resizable()
            .scaledToFill()
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .clipped()
            .opacity(page == .rival ? 0.25 : 0.45)   // the rival's crimson owns that page
            .mask {
                LinearGradient(stops: [.init(color: .white, location: 0),
                                       .init(color: .white.opacity(0.5), location: 0.5),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Six charge dots — the week-slot grammar marking how far into the forge you are.
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= page.rawValue
                          ? SettColor.heroCyan.opacity(0.85)
                          : TimeChamber.void.opacity(0.4))
                    .overlay {
                        Circle().strokeBorder(step.rawValue <= page.rawValue
                                              ? SettColor.heroCyan
                                              : SettColor.iron.opacity(0.5), lineWidth: 1)
                    }
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
    }

    // MARK: Page 1 — invite code

    private var invitePage: some View {
        VStack(spacing: 20) {
            Spacer()
            heroMedallion("ExArt_muscle_other")
            Text("Enter your invite code")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(SettColor.bone)
            Text("sett is invite-only. Ask a friend who trains.")
                .font(.subheadline)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
            TextField("CHAMBER-XXXXXX", text: $inviteCode)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 14)
                .background(SettColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(SettColor.heroCyan.opacity(trimmedCode.count >= 6 ? 0.5 : 0.15),
                                      lineWidth: 1)
                }
                .onChange(of: inviteCode) { _, newValue in
                    let uppercased = newValue.uppercased()
                    if uppercased != newValue { inviteCode = uppercased }
                }
            Spacer()
            // TODO: server-side invite validation once auth ships — length is a stub gate.
            continueButton("Continue", enabled: trimmedCode.count >= 6) {
                advance(to: .signIn)
            }
        }
        .padding(24)
    }

    private var trimmedCode: String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A warrior-art medallion instead of a floating SF Symbol — day zero shows the
    /// same marks the rest of the app wears. ONE ringed ~104pt treatment shared by
    /// every page's hero so the centered mark doesn't jump size/framing as you page
    /// (the rival's carded set-piece is the deliberate exception).
    private func heroMedallion(_ asset: String) -> some View {
        ExerciseArtView(asset: asset, size: 64, color: SettColor.heroCyan)
            .padding(20)
            .background {
                Circle().fill(TimeChamber.void.opacity(0.6))
                Circle().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1.5)
            }
            .shadow(color: SettColor.heroCyan.opacity(0.35), radius: 10)
            .accessibilityHidden(true)
    }

    // MARK: Page 2 — Sign in with Apple

    private var signInPage: some View {
        VStack(spacing: 20) {
            Spacer()
            heroMedallion("ExArt_muscle_back")
            Text("Your training data, your account.")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
            Text("Nothing else. No feed, no ads.")
                .font(.subheadline)
                .foregroundStyle(SettColor.ash)
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                switch result {
                case .success:
                    Haptics.success()
                    advance(to: .units)
                case .failure:
                    Haptics.error()
                }
            }
            .frame(height: 50)
            .clipShape(Capsule())
            ghostButton("CONTINUE WITHOUT ACCOUNT") {
                advance(to: .units)
            }
        }
        .padding(24)
    }

    // MARK: Page 3 — units

    private var unitsPage: some View {
        @Bindable var settings = services.settings
        return VStack(spacing: 20) {
            Spacer()
            EquipmentGlyph(equipment: .barbell, color: SettColor.heroCyan)
                .frame(width: 64, height: 64)
                .padding(20)
                .background {
                    Circle().fill(TimeChamber.void.opacity(0.6))
                    Circle().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1.5)
                }
                .shadow(color: SettColor.heroCyan.opacity(0.35), radius: 10)
                .accessibilityHidden(true)
            Text("How do you load the bar?")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(SettColor.bone)
            ChamberSegments(selection: $settings.unit,
                            options: [(WeightUnit.lb, "lb"), (WeightUnit.kg, "kg")])
            Text("Increment: \(services.settings.displayWeight(services.settings.incrementGrams)) per tap — change it anytime in Settings.")
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
            Spacer()
            continueButton("Continue") {
                advance(to: .phase)
            }
        }
        .padding(24)
        .onChange(of: services.settings.unit) { _, newUnit in
            services.settings.incrementGrams = newUnit.defaultIncrementGrams
            Haptics.selection()
        }
    }

    // MARK: Page 4 — training phase

    private var phasePage: some View {
        VStack(spacing: 20) {
            Spacer()
            heroMedallion("ExArt_muscle_core")
            Text("What are you training for?")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
            Text("This sets how the Scanner scores you — you can switch anytime.")
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                ForEach(TrainingPhase.allCases) { phase in
                    phaseChoice(phase)
                }
            }
            Spacer()
            continueButton("Continue", enabled: services.settings.hasChosenPhase) {
                advance(to: .oura)
            }
        }
        .padding(24)
    }

    private func phaseChoice(_ phase: TrainingPhase) -> some View {
        let selected = services.settings.hasChosenPhase && services.settings.phase == phase
        return Button {
            services.settings.trainingPhase = phase.rawValue
            services.settings.hasChosenPhase = true
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: phase.symbolName)
                    .font(.title2)
                    .foregroundStyle(selected ? SettColor.heroCyan : SettColor.ash)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title)
                        .font(.headline)
                        .foregroundStyle(SettColor.bone)
                    Text(phase.creed)
                        .font(.footnote)
                        .foregroundStyle(SettColor.ash)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SettColor.heroCyan)
                }
            }
            .padding(14)
            .background(SettColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? SettColor.heroCyan : SettColor.cardBorder,
                                  lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Page 5 — Oura pitch

    private var ouraPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bed.double.fill")
                .font(.system(size: 44))
                .foregroundStyle(TimeChamber.indigo)
                .padding(30)
                .background {
                    Circle().fill(TimeChamber.void.opacity(0.6))
                    Circle().strokeBorder(TimeChamber.indigo.opacity(0.4), lineWidth: 1.5)
                }
                .accessibilityHidden(true)
            Text("See how sleep moves your lifts")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
            Text("Skipping loses nothing — connect Oura anytime in Settings.")
                .font(.subheadline)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
            } label: {
                Text("Connect Oura — coming with sync")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SettColor.card, in: Capsule())
            }
            .disabled(true)
            .foregroundStyle(SettColor.ash)
            continueButton("Skip for now") {
                advance(to: .rival)
            }
        }
        .padding(24)
    }

    // MARK: Page 6 — meet your rival

    private var rivalPage: some View {
        VStack(spacing: 24) {
            Spacer()
            rivalCard
            VStack(spacing: 8) {
                Eyebrow("YOUR POWER LEVEL")
                PowerNumeral(0, size: .xl)
                Text("Earn it — every set raises it.")
                    .font(.footnote)
                    .foregroundStyle(SettColor.ash)
            }
            Spacer()
            continueButton("Begin training") {
                finish()
            }
        }
        .padding(24)
    }

    /// The flow's emotional beat — Vexeth wears the ONLY crimson in the app.
    private var rivalCard: some View {
        VStack(spacing: 12) {
            ZStack {
                BreathingAura(gradient: Aura.villain)
                    .frame(width: 124, height: 124)
                Circle()
                    .fill(RadialGradient(colors: [SettColor.villainCrimson.opacity(0.35),
                                                  SettColor.villainVoid],
                                         center: .center, startRadius: 4, endRadius: 60))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(SettColor.villainCrimson.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                SettSigil(size: 44, color: SettColor.villainCrimson)
            }
            .shadow(color: SettColor.villainCrimson.opacity(0.5), radius: 14)
            .accessibilityHidden(true)
            Text("EMPEROR VEXETH")
                .font(.system(.title3, design: .monospaced).weight(.heavy))
                .kerning(2)
                .foregroundStyle(SettColor.bone)
            Text("the Crimson Star")
                .font(.footnote)
                .foregroundStyle(SettColor.villainCrimson.opacity(0.8))
            Text("“Power level \(rivalPowerLevel) and climbing. You? Starting from zero. Every set closes the gap — catch me if your species can.”")
                .font(.subheadline)
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .hudCard(tint: SettColor.villainCrimson)
        .materialize()
        // The reveal's one hit — rigid, so it reads apart from the Continue taps.
        .onAppear { Haptics.rigid() }
    }

    private var rivalPowerLevel: Int {
        services.progression.config?.rival["startPL"] as? Int ?? 3000
    }

    // MARK: Navigation

    private func continueButton(_ title: String, enabled: Bool = true,
                                action: @escaping () -> Void) -> some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.etch)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(SettColor.heroCyan, in: Capsule())
        }
        // Silent press — the action already fires Haptics.medium, no stacking.
        .buttonStyle(PressableSlabStyle(haptic: nil))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.heroCyan)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background { Capsule().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func advance(to newPage: Page) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) { page = newPage }
    }

    private func finish() {
        services.settings.hasOnboarded = true
        dismiss()
    }
}
