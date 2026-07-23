import SwiftUI

/// Branded splash shown while the app bootstraps (cache + first network).
struct SplashView: View {
    var isFinishing: Bool = false

    @State private var pulse = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            SportsColors.voidBlack
                .ignoresSafeArea()

            // Soft green radial wash
            RadialGradient(
                colors: [
                    SportsColors.live.opacity(0.18),
                    SportsColors.gold.opacity(0.06),
                    .clear,
                ],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 0)

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.22, style: .continuous))
                    .shadow(color: SportsColors.live.opacity(0.35), radius: pulse ? 28 : 14, y: 8)
                    .shadow(color: SportsColors.gold.opacity(0.25), radius: pulse ? 18 : 8, y: 4)
                    .scaleEffect(appeared ? (isFinishing ? 1.06 : 1.0) : 0.86)
                    .opacity(appeared ? (isFinishing ? 0.0 : 1.0) : 0.0)

                VStack(spacing: 8) {
                    Text("SportsDash")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(SportsColors.text)
                    Text("Live sports · IPTV")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SportsColors.muted)
                }
                .opacity(appeared ? (isFinishing ? 0.0 : 1.0) : 0.0)
                .offset(y: appeared ? 0 : 12)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(SportsColors.gold)
                    Text("Loading…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SportsColors.muted)
                }
                .padding(.bottom, 48)
                .opacity(appeared && !isFinishing ? 1 : 0)
            }
            .padding(.horizontal, 32)
        }
        .opacity(isFinishing ? 0 : 1)
        .animation(.easeInOut(duration: 0.35), value: isFinishing)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SportsDash loading")
    }

    private var logoSize: CGFloat {
        #if os(tvOS)
        220
        #else
        132
        #endif
    }
}

#Preview {
    SplashView()
}
