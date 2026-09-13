import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPassword = false

    var body: some View {
        ZStack {
            // Full-screen dark gradient background
            LinearGradient(
                colors: [Color.flDarkBg, Color.flSurface, Color.flDarkBg],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle grid pattern overlay
            GridPattern()
                .opacity(0.04)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // Logo + Brand
                    VStack(spacing: 18) {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.flCyan.opacity(0.3), .flPurple.opacity(0.2), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 110, height: 110)

                            // Icon background
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.flPurple, .flCyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 90, height: 90)
                                .overlay(
                                    Image(systemName: "network")
                                        .font(.system(size: 38, weight: .medium))
                                        .foregroundStyle(.white)
                                )

                            // Pulse ring
                            Circle()
                                .stroke(Color.flCyan.opacity(0.4), lineWidth: 1)
                                .frame(width: 100, height: 100)
                        }

                        VStack(spacing: 8) {
                            // FREELLMAP wordmark
                            HStack(spacing: 2) {
                                Text("FREE")
                                    .foregroundStyle(Color.flCyan)
                                Text("LLMAP")
                                    .foregroundStyle(Color.flPurpleLight)
                            }
                            .font(.system(size: 30, weight: .black, design: .rounded))

                            Text("CONNECT")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.flSubtle)
                                .tracking(6)

                            Text("AI Gateway Dashboard")
                                .font(.caption)
                                .foregroundStyle(Color.flMuted)
                        }
                    }

                    Spacer().frame(height: 50)

                    // Form
                    VStack(spacing: 18) {
                        FLInputField(
                            label: "Gateway-URL",
                            text: $appState.serverURL,
                            icon: "link",
                            placeholder: "http://dein-server:20128",
                            autocapitalization: .never,
                            keyboardType: .URL
                        )

                        FLInputField(
                            label: "Email",
                            text: $appState.email,
                            icon: "envelope",
                            placeholder: "you@example.com",
                            autocapitalization: .never,
                            keyboardType: .emailAddress
                        )

                        FLInputField(
                            label: "Passwort",
                            text: $appState.password,
                            icon: "key.fill",
                            placeholder: "Gateway Passwort",
                            isSecure: !showPassword,
                            showToggle: true,
                            onToggle: { showPassword.toggle() }
                        )
                    }
                    .padding(.horizontal, 24)

                    if let err = appState.loginError {
                        FLErrorBanner(message: err)
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.3), value: appState.loginError)
                    }

                    Spacer().frame(height: 40)

                    // Login button
                    FLGlowButton(
                        title: "Verbinden",
                        icon: "bolt.fill",
                        accent: .flCyan,
                        isLoading: appState.isLoggingIn
                    ) {
                        Task { await appState.login() }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Footer
                    VStack(spacing: 6) {
                        FLDivider()
                            .padding(.horizontal, 40)
                        Text("FreeLLMAP Gateway \u{00B7} v1.0")
                            .font(.caption2)
                            .foregroundStyle(Color.flMuted)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// ── Grid pattern background ──────────────────────────────────────────────────

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 28
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += spacing
        }
        return path
    }
}

// ── Custom Input Field ────────────────────────────────────────────────────────

struct FLInputField: View {
    let label: String
    @Binding var text: String
    var icon: String? = nil
    var placeholder: String = ""
    var isSecure: Bool = false
    var showToggle: Bool = false
    var onToggle: (() -> Void)? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFocused ? Color.flCyan : Color.flSubtle)
                        .frame(width: 16)
                }
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.flSubtle)
            }

            HStack(spacing: 10) {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                            .textContentType(.password)
                    } else {
                        TextField(placeholder, text: $text)
                            .textInputAutocapitalization(autocapitalization)
                            .keyboardType(keyboardType)
                    }
                }
                .font(.body)
                .foregroundStyle(.flText)
                .tint(.flCyan)
                .focused($isFocused)

                if showToggle {
                    Button { onToggle?() } label: {
                        Image(systemName: isSecure ? "eye.slash" : "eye")
                            .font(.footnote)
                            .foregroundStyle(isFocused ? Color.flCyan : Color.flSubtle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.flCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFocused
                            ? AnyShapeStyle(LinearGradient(colors: [.flCyan.opacity(0.6), .flPurple.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.flBorder.opacity(0.5)),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
        }
    }
}
