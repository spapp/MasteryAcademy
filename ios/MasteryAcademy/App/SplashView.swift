import SwiftUI

/// Shown for a moment after the system launch screen, so the app opens on its mark instead of a flash of white.
/// The system launch screen (Info.plist, UILaunchScreen) uses the same colour and logo, so the hand-over is seamless.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.19, green: 0.18, blue: 0.63), Color(red: 0.49, green: 0.23, blue: 0.93)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
                    .accessibilityHidden(true)
                Text("Mastery Academy")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Every course in one place")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .opacity(appeared ? 1 : 0.6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mastery Academy")
    }
}

/// Puts the splash over the app at launch and fades it out.
struct SplashGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var showSplash = true

    var body: some View {
        ZStack {
            content()
            if showSplash {
                SplashView().transition(.opacity).zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeInOut(duration: 0.35)) { showSplash = false }
        }
    }
}
