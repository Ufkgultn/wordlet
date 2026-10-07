# Wordlet (DailyWordWidget) 🚀

Wordlet, İngilizce kelime dağarcığınızı geliştirmenize yardımcı olan, tamamen **Swift** ve **SwiftUI** kullanılarak geliştirilmiş modern bir iOS uygulamasıdır. 

Ana ekranınıza ekleyebileceğiniz **Günlük Kelime Widget**'ı ile her gün yeni kelimeler öğrenebilir, CEFR standartlarındaki (A1-B2) seviye sistemiyle kendi hızınızda ilerleyebilirsiniz.

## ✨ Öne Çıkan Özellikler

- 📱 **Günlük Kelime Widget'ı:** Uygulamayı açmanıza bile gerek kalmadan ana ekranınızda her gün yeni bir İngilizce kelime ve anlamını görün.
- 🎯 **CEFR Seviyeleri (A1 - B2):** Kendi seviyenize uygun kelimelerle çalışın. Sınavları geçerek yeni zorluk seviyelerinin kilitlerini açın.
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
   git clone https://github.com/Ufkgultn/wordlet.git
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

## 📚 Kelime Verisi

Kelimelerin seviyesi (`level`), türü (`pos`) ve sıklığı (`freqRank`) `tools/wordpipeline/build_words.py` ile üretilir ve `Shared/words.json` içine yazılır. Kelime eklendiğinde veya değiştirildiğinde yeniden çalıştırın:

```bash
python3 -m venv .venv && .venv/bin/pip install -r tools/wordpipeline/requirements.txt
.venv/bin/python tools/wordpipeline/build_words.py
```

Raporlar (`tools/wordpipeline/reports/`): seviye dağılımı, şablon/zor örnek cümleler, şüpheli çeviriler ve eksik temel kelimeler.

Örnek cümle üretimi ve anlam incelemesi bir dil modeliyle yapılır (varsayılan: Antigravity CLI `agy`; `--backend gemini` ile Gemini API):

```bash
.venv/bin/python tools/wordpipeline/generate_content.py examples --level A1   # şablon/zor cümleleri yeniden yaz
.venv/bin/python tools/wordpipeline/generate_content.py missing --level A1    # eksik temel kelimeleri ekle
.venv/bin/python tools/wordpipeline/review_agy.py --level A1                   # anlam incelemesi (Draw ≠ beraberlik gibi)
```

Her çıktı doğrulanır (seviyeye uygunluk, hedef kelimenin cümlede geçmesi). `reports/review_*.csv` her değişikliği gerekçesiyle listeler; yayından önce en az A1–A2 bir insan tarafından gözden geçirilmelidir.

**Kaynaklar ve atıf**
- The CEFR-J Wordlist Version 1.5. Compiled by Yukio Tono, Tokyo University of Foreign Studies. http://www.cefr-j.org/download.html (via [Open Language Profiles](https://github.com/openlanguageprofiles/olp-en-cefrj))
- Kelime sıklığı: [wordfreq](https://github.com/rspeer/wordfreq) (Robyn Speer)

## 📜 Lisans

Bu proje kişisel/özel bir projedir. Tüm hakları saklıdır.
