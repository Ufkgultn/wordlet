import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct Theme {
    // ── Temaya göre değişen renkler ───────────────────────────────────────
    // Koyu temada eskisiyle birebir aynı (beyaz); açık temada koyu lacivert.
    // ContentView .preferredColorScheme ile temayı belirlediği için renkler kendiliğinden çözülür.
    private static func adaptive(dark: Color, light: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        return dark
        #endif
    }

    /// Ana ön plan rengi: yazılar, ikonlar ve yarı saydam yüzeyler (fg.opacity(0.06) gibi)
    public static let fg = adaptive(dark: .white, light: Color(red: 0.118, green: 0.106, blue: 0.227)) // #1E1B3A mürekkep

    /// fg'nin tersi: fg.opacity(0.9) gibi dolu zeminlerin üstündeki yazı (koyu temada koyu, açıkta beyaz)
    public static let fgInverse = adaptive(dark: Color(red: 0.05, green: 0.05, blue: 0.10), light: .white)

    /// Tam ekran sayfa zemini (AppBackground kullanmayan ekranlar): koyu temada lacivert, açık temada krem
    public static let pageBackground = adaptive(dark: Color(red: 0.05, green: 0.05, blue: 0.10),
                                                light: Color(red: 0.980, green: 0.973, blue: 0.961))

    /// Premium/altın vurgu: koyu temada sarı, açık zeminde okunması için koyu altın (#B07D00)
    public static let gold = adaptive(dark: .yellow, light: Color(red: 0.69, green: 0.49, blue: 0.0))

    /// Açılır pencere / kart yüzeyi: koyu temada lacivert, açık temada beyaz
    public static let surface = adaptive(dark: Color(red: 0.05, green: 0.05, blue: 0.10), light: .white)

    /// Yazı olarak kullanılan vurgu rengi: açık zeminde nane yeşili okunmadığı için koyu turkuaz
    public static let accentText = adaptive(dark: Color(red: 0.50, green: 0.95, blue: 0.80),
                                            light: Color(red: 0.294, green: 0.282, blue: 0.784)) // #4B48C8, krem üstünde 6.5:1

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
    public static let cardBackground  = fg.opacity(0.10)

    // ── Typography ───────────────────────────────────────────────────────
    public static let textPrimary   = fg
    public static let textSecondary = fg.opacity(0.7)
    public static let textTertiary  = fg.opacity(0.5)

    // ── Accent ───────────────────────────────────────────────────────────
    // Koyu temada canlı nane; açık temada sakin indigo (#5B5BD6, beyaz yazıyla 5.4:1)
    public static let accent      = adaptive(dark: Color(red: 0.50, green: 0.95, blue: 0.80),
                                             light: Color(red: 0.357, green: 0.357, blue: 0.839))
    /// Seçili sekme rengi: koyu temada sistem mavisi (eskisi gibi), açık temada indigo
    public static let tabTint = adaptive(dark: Color.blue, light: Color(red: 0.357, green: 0.357, blue: 0.839))
    /// Dolu vurgu zemininin üstündeki yazı: koyu temada nane üstünde siyah, açık temada indigo üstünde beyaz
    public static let onAccent    = adaptive(dark: .black, light: .white)
    public static let accentLight = accent.opacity(0.2)

    /// Büyük kelime kartı: koyu temada canlı nane, açık temada yumuşak lavanta (#EEEDFC)
    public static let cardFill = adaptive(dark: Color(red: 0.50, green: 0.95, blue: 0.80),
                                          light: Color(red: 0.933, green: 0.929, blue: 0.988))
    /// Kart gölgesi: açık zeminde koyu gölge kirli hale gibi durmasın
    public static let cardShadow = adaptive(dark: Color.black.opacity(0.2), light: Color.black.opacity(0.07))
    /// Kartın içindeki kutular (örnek cümle): koyu temada kararan, açık temada beyazlaşan
    public static let cardInset = adaptive(dark: Color.black.opacity(0.2), light: Color.white.opacity(0.75))

    // ── Quiz colours ────────────────────────────────────────────────────
    public static let correct = Color(red: 0.25, green: 0.90, blue: 0.55)
    public static let wrong   = Color(red: 1.00, green: 0.35, blue: 0.45)
}

// MARK: - Premium Glass Card Modifier
public struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    public func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
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
                    .stroke(Theme.fg.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Dynamic App Background
public struct AppBackground: View {
    // Tema ContentView'da .preferredColorScheme ile seçilir; arka plan da yazı renkleri (Theme.fg)
    // gibi gerçek renk şemasına bakar, böylece ikisi hiç ayrışmaz
    @Environment(\.colorScheme) var colorScheme
    
    public init() {}
    
    public var body: some View {
        if colorScheme == .dark {
            Color.black.ignoresSafeArea()
        } else {
            // Açık tema: kremden çok hafif lavantaya (#FAF8F5 → #F3F1FA), saf beyazdan yumuşak
            LinearGradient(
                colors: [Color(red: 0.980, green: 0.973, blue: 0.961), Color(red: 0.953, green: 0.945, blue: 0.980)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

public struct AppBackgroundModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(AppBackground())
    }
}

public extension View {
    func neumorphism() -> some View {
        self.modifier(NeumorphismModifier())
    }
    func glassCard(cornerRadius: CGFloat = 28) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
    func appBackground() -> some View {
        self.modifier(AppBackgroundModifier())
    }
}

// MARK: - Reusable User Avatar (Photo or Emoji)
#if canImport(UIKit)
import UIKit

public struct UserAvatarView: View {
    let emoji: String
    var size: CGFloat
    var customPhotoData: Data?
    
    public init(emoji: String, size: CGFloat = 54, customPhotoData: Data? = nil) {
        self.emoji = emoji
        self.size = size
        self.customPhotoData = customPhotoData
    }
    
    private var photoData: Data? {
        customPhotoData ?? UserDefaults.standard.data(forKey: "user_profile_photo_data")
    }
    
    public var body: some View {
        if let data = photoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.accent.opacity(0.8), lineWidth: 1.5))
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.35), Color.blue.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(Theme.fg.opacity(0.15), lineWidth: 1))
                
                Text(emoji.isEmpty ? "🚀" : emoji)
                    .font(.system(size: size * 0.52))
            }
        }
    }
}
#endif
