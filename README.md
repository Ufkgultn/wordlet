# Wordlet (DailyWordWidget) 🚀

Wordlet, İngilizce kelime dağarcığınızı geliştirmenize yardımcı olan, tamamen **Swift** ve **SwiftUI** kullanılarak geliştirilmiş modern bir iOS uygulamasıdır. 

Ana ekranınıza ekleyebileceğiniz **Günlük Kelime Widget**'ı ile her gün yeni kelimeler öğrenebilir, CEFR standartlarındaki (A1-C2) seviye sistemiyle kendi hızınızda ilerleyebilirsiniz.

## ✨ Öne Çıkan Özellikler

- 📱 **Günlük Kelime Widget'ı:** Uygulamayı açmanıza bile gerek kalmadan ana ekranınızda her gün yeni bir İngilizce kelime ve anlamını görün.
- 🎯 **CEFR Seviyeleri (A1 - C2):** Kendi seviyenize uygun kelimelerle çalışın. Sınavları geçerek yeni zorluk seviyelerinin kilitlerini açın.
- 🎮 **Oyunlaştırılmış Öğrenme (Gamification):**
  - **Günlük Testler:** Her gün pratik yaparak serinizi (streak) koruyun.
  - **Seviye Sınavları:** Bir üst seviyeye geçmek için minimum %70 başarı sağlayın.
  - **Yıldız Sistemi:** Alıştırmaları tamamlayarak yıldızları toplayın ve ustalığınızı kanıtlayın.
- 🃏 **Kart Kaydırma Mantığı:** Öğrenirken bildiğiniz kelimeleri sağa, bilmediklerinizi sola kaydırarak hızlıca pratik yapın ve kelime hafızanızı ölçün.
- ☁️ **Supabase Entegrasyonu:** Güvenli kullanıcı doğrulaması (Auth) ve veri yönetimi.
- 🎨 **Modern Arayüz:** SwiftUI ile geliştirilmiş; "Glassmorphism", akıcı animasyonlar, gradient renkler ve şık geçişlerle desteklenen premium UI tasarımı.

## 🛠️ Teknolojiler & Mimari

- **Dil:** Swift
- **Arayüz (UI):** SwiftUI
- **Widget:** WidgetKit
- **Proje Yönetimi:** XcodeGen (`project.yml`)
- **Backend & Auth:** Supabase

Proje, Git geçmişinde `.xcodeproj` çakışmalarını (conflict) önlemek ve çok daha temiz bir yapı sunmak için **XcodeGen** kullanılarak yapılandırılmıştır. Tüm proje ayarları ve hedefler `project.yml` dosyasından yönetilmektedir.

---

## 🚀 Kurulum & Çalıştırma

Projeyi yerel bilgisayarınızda çalıştırmak için aşağıdaki adımları izleyin:

### Gereksinimler
- **macOS:** Güncel bir sürüm.
- **Xcode:** 14.0+ (iOS 16+ SDK desteği ile)
- **Homebrew:** XcodeGen kurulumu için.

### Adımlar

1. **Projeyi Klonlayın:**
   ```bash
   git clone https://github.com/ugurboz/wordlet.git
   cd wordlet
   ```

2. **XcodeGen'i Yükleyin (Sisteminizde yüklü değilse):**
   ```bash
   brew install xcodegen
   ```

3. **Proje Dosyasını (.xcodeproj) Oluşturun:**
   ```bash
   xcodegen generate
   ```
   *(Bu komut, `project.yml` dosyasını okuyarak `DailyWordWidget.xcodeproj` dosyasını otomatik olarak oluşturur ve Swift Package Manager bağımlılıklarını (Supabase) ekler.)*

4. **Projeyi Açın:**
   ```bash
   open DailyWordWidget.xcodeproj
   ```

5. **Supabase Ayarları:**
   Proje arka uç olarak Supabase kullanmaktadır. Uygulamanın sorunsuz çalışması için `App/SupabaseManager.swift` içerisindeki Supabase URL ve Anon Key değerlerinin tanımlı olduğundan emin olun.

6. **Derleyin ve Çalıştırın!** 🎉
   Xcode üzerinden `DailyWordWidget` hedefini (target) seçerek Simulator'da veya doğrudan cihazınızda çalıştırabilirsiniz.

---

## 📂 Proje Yapısı

- `App/`: Ana iOS uygulamasının SwiftUI görünümleri, ekranları (HomeView, QuizView, LevelView vb.) ve temel logic/Auth yönetimi.
- `Widget/`: WidgetKit kullanılarak oluşturulan iOS ana ekran widget'ı kodları ve UI bileşenleri.
- `Shared/`: Hem App hem de Widget hedefleri (targets) tarafından ortak kullanılan veri modelleri (Models), kullanıcı ilerleme durumu (ProgressManager, AppSettingsManager) ve statik kelime verileri (`words.json`).
- `project.yml`: XcodeGen konfigürasyon dosyası. Hedefleri, paketleri ve sertifika/bundle ID ayarlarını içerir.

---

## 👨‍💻 Katkıda Bulunma

Bu projeye katkıda bulunmak isterseniz, lütfen bir "Pull Request" (PR) oluşturun. Her türlü iyileştirme, kod optimizasyonu veya yeni özellik önerisine açığız!

1. Projeyi fork'layın
2. Yeni bir özellik dalı (branch) oluşturun (`git checkout -b feature/YeniOzellik`)
3. Değişikliklerinizi commit'leyin (`git commit -m 'Yeni bir özellik eklendi'`)
4. Dalınızı (branch) push'layın (`git push origin feature/YeniOzellik`)
5. Bir Pull Request açın!

---

## 📜 Lisans

Bu proje kişisel/özel bir projedir. Tüm hakları saklıdır.
