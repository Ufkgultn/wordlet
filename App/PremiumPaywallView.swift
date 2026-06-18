import SwiftUI
import StoreKit
import WidgetKit

struct PremiumPaywallView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var selectedProductID = StoreKitManager.yearlyID
    
    // Fallback Mock Ürünler (Eğer StoreKit App Store'a henüz bağlanamadıysa)
    let mockProducts = [
        (id: StoreKitManager.monthlyID, title: "Aylık", price: "$1.99", desc: "Her ay otomatik yenilenir", badge: ""),
        (id: StoreKitManager.yearlyID, title: "Yıllık", price: "$9.99", desc: "Her yıl otomatik yenilenir (Tasarruf %58)", badge: "En Avantajlı"),
        (id: StoreKitManager.lifetimeID, title: "Ömür Boyu", price: "$19.99", desc: "Tek seferlik ödeme, sınırsız erişim", badge: "En Popüler")
    ]
    
    var body: some View {
        ZStack {
            // Ultra Premium Gradient Background
            AppBackground()
            
            // Background blur effects
            VStack {
                HStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 200, height: 200)
                        .blur(radius: 60)
                        .offset(x: -50, y: -50)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 250, height: 250)
                        .blur(radius: 80)
                        .offset(x: 80, y: 80)
                }
            }
            
            ScrollView {
                VStack(spacing: 28) {
                    
                    // Kapatma Butonu
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                    }
                    
                    // Üst Görsel ve Başlık
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.yellow.opacity(0.1))
                                .frame(width: 90, height: 90)
                            
                            Image(systemName: "crown.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.yellow)
                                .shadow(color: .yellow.opacity(0.5), radius: 10, x: 0, y: 4)
                        }
                        
                        Text("Vocab Daily Premium")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Kelime haznenizi sınırsızca genişletin, widget deneyiminizi özelleştirin.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    
                    // Özellik Listesi
                    VStack(alignment: .leading, spacing: 16) {
                        featureRow(icon: "rectangle.3.group.bubble.fill", color: Theme.accent, title: "Sınırsız Widget Değişikliği", subtitle: "Widget üzerindeki butona basarak anında yeni kelimeye geçin.")
                        featureRow(icon: "bolt.fill", color: .yellow, title: "Tüm CEFR Seviyeleri", subtitle: "A1'den C2'ye kadar olan tüm kelime listelerine erişim sağlayın.")
                        featureRow(icon: "speaker.wave.3.fill", color: .cyan, title: "Detaylı Telaffuzlar", subtitle: "Örnek cümlelerin doğru telaffuzlarını dinleyin.")
                        featureRow(icon: "graduationcap.fill", color: .purple, title: "İlerleme Raporları", subtitle: "Öğrendiğiniz kelimelerin detaylı analizini takip edin.")
                    }
                    .padding(24)
                    .glassCard(cornerRadius: 24)
                    .padding(.horizontal, 20)
                    
                    // Ürün Kartları
                    VStack(spacing: 12) {
                        if !storeManager.products.isEmpty {
                            // StoreKit'ten yüklenen gerçek ürünler
                            ForEach(storeManager.products, id: \.id) { product in
                                productCard(
                                    id: product.id,
                                    title: product.displayName,
                                    price: product.displayPrice,
                                    desc: product.description,
                                    badge: product.id == StoreKitManager.yearlyID ? "En Avantajlı" : (product.id == StoreKitManager.lifetimeID ? "Tek Seferlik" : "")
                                )
                            }
                        } else {
                            // Mock Ürünler (Fallback)
                            ForEach(mockProducts, id: \.id) { product in
                                productCard(
                                    id: product.id,
                                    title: product.title,
                                    price: product.price,
                                    desc: product.desc,
                                    badge: product.badge
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // StoreKit Simülasyon Durumu Uyarısı
                    if storeManager.products.isEmpty {
                        Text("⚠️ StoreKit Simülasyonu Aktif Değil\n(Xcode şemasından Products.storekit seçilmediği için sanal ödeme ekranı açılmaz, doğrudan premium yapılır.)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.yellow.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    // Hata Mesajı
                    if let errorMsg = storeManager.purchaseError {
                        Text(errorMsg)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    // Satın Alma ve Geri Yükleme Butonları
                    VStack(spacing: 14) {
                        Button {
                            Task {
                                await handlePurchase()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if storeManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Premium Üyeliği Başlat")
                                        .font(.headline.bold())
                                }
                                Spacer()
                            }
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.yellow)
                                    .shadow(color: Color.yellow.opacity(0.3), radius: 12, x: 0, y: 6)
                            )
                            .foregroundColor(Theme.gradientStart)
                        }
                        .disabled(storeManager.isLoading)
                        .padding(.horizontal, 20)
                        
                        HStack(spacing: 24) {
                            Button("Satın Alımları Geri Yükle") {
                                Task {
                                    await storeManager.restorePurchases()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.white.opacity(0.3))
                            
                            Button("Simülatör Premium Testi") {
                                storeManager.toggleDebugPremium()
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                dismiss()
                            }
                        }
                        .font(.footnote.bold())
                        .foregroundColor(.white.opacity(0.6))
                    }
                    
                    // Yasal Uyarı Metinleri
                    VStack(spacing: 6) {
                        Text("Abonelikler otomatik olarak yenilenir ve istediğiniz zaman App Store ayarlarından iptal edilebilir.")
                        Text("Kullanım Koşulları & Gizlilik Politikası geçerlidir.")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Row Helper
    
    @ViewBuilder
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 24)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    // MARK: - Card Helper
    
    @ViewBuilder
    private func productCard(id: String, title: String, price: String, desc: String, badge: String) -> some View {
        let isSelected = selectedProductID == id
        
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedProductID = id
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 16) {
                // Seçim Dairesi
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.yellow : Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 12, height: 12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        
                        if !badge.isEmpty {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Theme.gradientStart)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.yellow))
                        }
                    }
                    
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Text(price)
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(isSelected ? .yellow : .white)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.yellow.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Purchase Action
    
    private func handlePurchase() async {
        if !storeManager.products.isEmpty {
            // StoreKit ile gerçek/simüle satın alım yap
            if let product = storeManager.products.first(where: { $0.id == selectedProductID }) {
                let success = await storeManager.purchase(product)
                if success {
                    dismiss()
                }
            }
        } else {
            // StoreKit bağlı değilse yerel debug premium modunu aktifleştir (Simulator test kolaylığı)
            AppSettingsManager.shared.isPremium = true
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
        }
    }
}

#Preview {
    PremiumPaywallView()
}
