import SwiftUI
import UIKit

struct OnboardingWelcomeView: View {
    let onServerConnected: () -> Void

    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?
    @State private var showingServerForm = false
    @State private var appeared = false
    @AppStorage("minidisc.localMusicEnabled") private var localMusicEnabled = false

    var body: some View {
        ZStack {
            MinidiscColors.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    welcomeContent
                        .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
            appeared = true
        }
        .onChange(of: container?.serverState.activeServer != nil) { _, connected in
            if connected { showingServerForm = false }
        }
        .sheet(isPresented: $showingServerForm, onDismiss: {
            if container?.serverState.activeServer != nil { onServerConnected() }
        }) {
            if let viewModel {
                NavigationStack { ServerFormView(viewModel: viewModel) }
            }
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: MinidiscSpacing.xl)

            AnimatedMinidiscHero()
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.7)
                .animation(.spring(duration: 0.6, bounce: 0.4), value: appeared)

            Spacer().frame(height: MinidiscSpacing.xxxxl)

            VStack(spacing: MinidiscSpacing.m) {
                Text("Your music.\nYour rules.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(MinidiscColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.05), value: appeared)

                Text("Stream your library from your own server.\nNo subscriptions. No big tech.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(MinidiscColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.1), value: appeared)
            }
            .padding(.horizontal, MinidiscSpacing.xxxl)

            Spacer(minLength: MinidiscSpacing.xl)

            Button { localMusicEnabled = true } label: {
                Text("Use Local Files", tableName: "LocalMusic")
            }
            .padding(.bottom, MinidiscSpacing.l)

            getStartedButton
                .padding(.horizontal, MinidiscSpacing.xxxl)
                .padding(.bottom, MinidiscSpacing.xxxl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 30)
                .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.2), value: appeared)
        }
    }

    private var getStartedButton: some View {
        Button {
            triggerHaptic()
            showingServerForm = true
        } label: {
            Text("Get Started")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(MinidiscColors.accent)
        .disabled(viewModel == nil)
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Animated Minidisc Hero

private struct AnimatedMinidiscHero: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(MinidiscColors.accent.opacity(0.08))
                .frame(width: 290, height: 290)
                .blur(radius: 60)

            MinidiscLogoView(isSpinning: true)
                .frame(width: 210)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .accessibilityHidden(true)
        }
    }
}
