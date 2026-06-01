import SwiftUI

struct AuthView: View {
    @EnvironmentObject var auth: LocalAuthService
    @State private var isLogin = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMsg = ""
    @FocusState private var focused: Field?

    enum Field { case name, email, password }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#EBF3FF"), Color(hex: "#F4F8FF")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        Image("AppLogo").resizable().scaledToFit().frame(width: 80, height: 80)
                        Text("GÖZCÜ").font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(GTheme.Color.primary).tracking(6)
                        Text("Güvenli sürüş asistanın").font(.system(size: 14)).foregroundColor(GTheme.Color.textSecondary)
                    }
                    .padding(.top, 60).padding(.bottom, 40)

                    VStack(spacing: 20) {
                        HStack(spacing: 0) {
                            ForEach(["Giriş Yap", "Kayıt Ol"], id: \.self) { tab in
                                let selected = (tab == "Giriş Yap") == isLogin
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { isLogin = (tab == "Giriş Yap"); errorMsg = "" }
                                } label: {
                                    Text(tab).font(.system(size: 15, weight: selected ? .semibold : .regular))
                                        .foregroundColor(selected ? GTheme.Color.primary : GTheme.Color.textSecondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                }
                                .background(selected ? GTheme.Color.primary.opacity(0.08) : Color.clear)
                                .cornerRadius(10)
                            }
                        }
                        .background(Color(hex: "#EEF4FF")).cornerRadius(12)

                        if !isLogin {
                            AuthField(icon: "person", placeholder: "Ad Soyad", text: $name, focused: $focused, field: .name)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        AuthField(icon: "envelope", placeholder: "E-posta adresi", text: $email, focused: $focused, field: .email, keyboard: .emailAddress)
                        AuthField(icon: "lock", placeholder: "Şifre", text: $password, focused: $focused, field: .password, isSecure: true)

                        if !errorMsg.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                                Text(errorMsg).font(.caption)
                            }
                            .foregroundColor(GTheme.Color.danger)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                        }

                        Button { Task { await submit() } } label: {
                            ZStack {
                                if isLoading { ProgressView().tint(.white) }
                                else { Text(isLogin ? "Giriş Yap" : "Hesap Oluştur").font(.system(size: 16, weight: .semibold)).foregroundColor(.white) }
                            }
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(LinearGradient(colors: [Color(hex: "#1565C0"), Color(hex: "#1E88E5")], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(GTheme.Radius.medium)
                        }
                        .disabled(isLoading || !isFormValid)
                        .opacity(isFormValid ? 1 : 0.6)
                    }
                    .padding(24).background(Color.white).cornerRadius(GTheme.Radius.large)
                    .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)
                    .padding(.horizontal, 24)
                }
            }
        }
        .onTapGesture { focused = nil }
    }

    private var isFormValid: Bool {
        let base = !email.isEmpty && password.count >= 6
        return isLogin ? base : (base && !name.isEmpty)
    }

    private func submit() async {
        isLoading = true; errorMsg = ""
        do {
            if isLogin { try await auth.signIn(email: email, password: password) }
            else { try await auth.signUp(name: name, email: email, password: password) }
        } catch {
            errorMsg = auth.errorMessage ?? "Hata oluştu, tekrar deneyin."
        }
        isLoading = false
    }
}

private struct AuthField: View {
    let icon, placeholder: String
    @Binding var text: String
    var focused: FocusState<AuthView.Field?>.Binding
    let field: AuthView.Field
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(GTheme.Color.textSecondary).frame(width: 22)
            if isSecure {
                SecureField(placeholder, text: $text).focused(focused, equals: field).font(.system(size: 15)).foregroundColor(.black).environment(\.colorScheme, .light)
            } else {
                TextField(placeholder, text: $text).focused(focused, equals: field).keyboardType(keyboard)
                    .autocapitalization(.none).autocorrectionDisabled().font(.system(size: 15)).foregroundColor(.black).environment(\.colorScheme, .light)
            }
        }
        .padding(.horizontal, 16).frame(height: 52).background(Color(hex: "#F4F8FF")).cornerRadius(GTheme.Radius.small)
        .overlay(RoundedRectangle(cornerRadius: GTheme.Radius.small)
            .stroke(focused.wrappedValue == field ? GTheme.Color.primaryLight : Color(hex: "#D8E4F0"), lineWidth: 1.5))
    }
}
