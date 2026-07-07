import SwiftUI
import AuthenticationServices
import SettCore

/// First-run flow (design-ux §6), five simple pages: invite code, Sign in with
/// Apple, units, Oura pitch, meet-your-rival. Local-only in this build — the
/// invite code and Apple identity are not verified against a server yet.
/// Presented as a fullScreenCover from Home while `settings.hasOnboarded == false`.
struct OnboardingView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Page: Int, Hashable, CaseIterable {
        case invite, signIn, units, oura, rival
    }

    @State private var page: Page = .invite
    @State private var inviteCode = ""
    @State private var displayedPowerLevel = 0

    var body: some View {
        TabView(selection: $page) {
            invitePage.tag(Page.invite)
            signInPage.tag(Page.signIn)
            unitsPage.tag(Page.units)
            ouraPage.tag(Page.oura)
            rivalPage.tag(Page.rival)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(SettColor.screen.ignoresSafeArea())
        .onChange(of: page) { _, newPage in
            if newPage == .rival { rollUpPowerLevel() }
        }
    }

    // MARK: Page 1 — invite code

    private var invitePage: some View {
        VStack(spacing: 20) {
            Spacer()
            auraMark
            Text("Enter your invite code")
                .font(.title2.bold())
            Text("sett is invite-only. Ask a friend who trains.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("SAIYAN-XXXXXX", text: $inviteCode)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 14)
                .background(SettColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: inviteCode) { _, newValue in
                    let uppercased = newValue.uppercased()
                    if uppercased != newValue { inviteCode = uppercased }
                }
            Spacer()
            continueButton("Continue", enabled: trimmedCode.count >= 6) {
                advance(to: .signIn)
            }
        }
        .padding(24)
    }

    private var trimmedCode: String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var auraMark: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 44))
            .foregroundStyle(Aura.cyan)
            .padding(28)
            .background(
                RadialGradient(colors: [SettColor.heroCyan.opacity(0.25), .clear],
                               center: .center, startRadius: 4, endRadius: 70),
                in: Circle()
            )
            .accessibilityHidden(true)
    }

    // MARK: Page 2 — Sign in with Apple

    private var signInPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(Aura.cyan)
            Text("Your training data, your account.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Nothing else. No feed, no ads.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            Button("Continue without account") {
                advance(to: .units)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(24)
    }

    // MARK: Page 3 — units

    private var unitsPage: some View {
        @Bindable var settings = services.settings
        return VStack(spacing: 20) {
            Spacer()
            Image(systemName: "scalemass.fill")
                .font(.system(size: 44))
                .foregroundStyle(Aura.cyan)
            Text("How do you load the bar?")
                .font(.title2.bold())
            Picker("Weight unit", selection: $settings.unit) {
                Text("lb").tag(WeightUnit.lb)
                Text("kg").tag(WeightUnit.kg)
            }
            .pickerStyle(.segmented)
            Text("Increment: \(services.settings.displayWeight(services.settings.incrementGrams)) per tap — change it anytime in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            continueButton("Continue") {
                advance(to: .oura)
            }
        }
        .padding(24)
        .onChange(of: services.settings.unit) { _, newUnit in
            services.settings.incrementGrams = newUnit.defaultIncrementGrams
            Haptics.selection()
        }
    }

    // MARK: Page 4 — Oura pitch

    private var ouraPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bed.double.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(uiColor: .systemIndigo))
            Text("See how sleep moves your lifts")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Skipping loses nothing — connect Oura anytime in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
            continueButton("Skip for now") {
                advance(to: .rival)
            }
        }
        .padding(24)
    }

    // MARK: Page 5 — meet your rival

    private var rivalPage: some View {
        VStack(spacing: 24) {
            Spacer()
            rivalCard
            VStack(spacing: 8) {
                Text("YOUR POWER LEVEL")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.5)
                    .foregroundStyle(.secondary)
                PowerNumeral(displayedPowerLevel, size: .xl)
            }
            Spacer()
            continueButton("Begin training") {
                finish()
            }
        }
        .padding(24)
    }

    private var rivalCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 72))
                .foregroundStyle(SettColor.villainCrimson)
                .accessibilityHidden(true)
            Text("EMPEROR VEXETH")
                .font(.title3.weight(.heavy))
                .kerning(2)
                .foregroundStyle(.white)
            Text("the Crimson Star")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            Text("“Power level \(rivalPowerLevel) and climbing. You start at 100. Catch me — if your species can.”")
                .font(.subheadline)
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var rivalPowerLevel: Int {
        services.progression.config?.rival["startPL"] as? Int ?? 3000
    }

    /// 0 → 100 roll-up (`contentTransition(.numericText)` inside PowerNumeral).
    /// Reduce Motion snaps straight to 100.
    private func rollUpPowerLevel() {
        guard displayedPowerLevel == 0 else { return }
        if reduceMotion {
            displayedPowerLevel = 100
            return
        }
        Task { @MainActor in
            for value in [8, 27, 61, 100] {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.snappy) { displayedPowerLevel = value }
            }
            Haptics.levelUp()
        }
    }

    // MARK: Navigation

    private func continueButton(_ title: String, enabled: Bool = true,
                                action: @escaping () -> Void) -> some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Aura.cyan, in: Capsule())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func advance(to newPage: Page) {
        withAnimation(.snappy) { page = newPage }
    }

    private func finish() {
        services.settings.hasOnboarded = true
        dismiss()
    }
}
