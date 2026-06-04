import SwiftUI

public struct Theme {
    // ── Ultra Premium Gradient Background ──────────────────────────────────────────
    public static let gradientStart = Color(red: 0.12, green: 0.08, blue: 0.28) // Deep cosmic purple
    public static let gradientMid   = Color(red: 0.20, green: 0.35, blue: 0.65) // Ocean depth blue
    public static let gradientEnd   = Color(red: 0.10, green: 0.55, blue: 0.65) // Deep cyan

    public static let backgroundGradient = LinearGradient(
        colors: [gradientStart, gradientMid, gradientEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // ── Solid fallbacks ───────────────────────────────────────────────────
    public static let background      = Color(red: 0.05, green: 0.05, blue: 0.10) 
    public static let cardBackground  = Color.white.opacity(0.10)

    // ── Typography ───────────────────────────────────────────────────────
    public static let textPrimary   = Color.white
    public static let textSecondary = Color.white.opacity(0.7)
    public static let textTertiary  = Color.white.opacity(0.5)

    // ── Accent ───────────────────────────────────────────────────────────
    public static let accent      = Color(red: 0.50, green: 0.95, blue: 0.80) // Vibrant mint
    public static let accentLight = Color(red: 0.50, green: 0.95, blue: 0.80).opacity(0.2)

    // ── Quiz colours ────────────────────────────────────────────────────
    public static let correct = Color(red: 0.25, green: 0.90, blue: 0.55)
    public static let wrong   = Color(red: 1.00, green: 0.35, blue: 0.45)
}

// MARK: - Premium Glass Card Modifier
public struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    public func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
    }
}

// MARK: - Neumorphism (kept for compat)
public struct NeumorphismModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

public extension View {
    func neumorphism() -> some View {
        self.modifier(NeumorphismModifier())
    }
    func glassCard(cornerRadius: CGFloat = 28) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
