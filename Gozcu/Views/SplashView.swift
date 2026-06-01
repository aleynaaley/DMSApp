import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    var onFinished: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#060D1A"), Color(hex: "#0D2040")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                Spacer().frame(height: 28)
                Text("GÖZCÜ")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(8)
                    .opacity(textOpacity)
                Spacer().frame(height: 12)
                Text("Siz Yola Odaklanın, O Size.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(Color(hex: "#8BAABF"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .opacity(taglineOpacity)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in LoadingDot(delay: Double(i) * 0.2) }
                }
                .opacity(textOpacity)
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { logoOpacity = 1; logoScale = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) { textOpacity = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.9)) { taglineOpacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { onFinished() }
        }
    }
}

private struct LoadingDot: View {
    let delay: Double
    @State private var opacity: Double = 0.3
    var body: some View {
        Circle()
            .fill(Color(hex: "#1E88E5"))
            .frame(width: 8, height: 8)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    opacity = 1
                }
            }
    }
}
