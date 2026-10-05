import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            word: Word(id: "0", english: "Elegance", turkish: "Zerafet", example: "True elegance is simple and often found in the most unexpected places.", level: .b2)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(SimpleEntry(date: Date(), word: resolveCurrentWord()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let now = Date()
        let manager = AppSettingsManager.shared
        let intervalMinutes = max(5, min(300, manager.settings.widgetUpdateIntervalMinutes))
        let intervalSeconds = Double(intervalMinutes) * 60
        
        let lastChange = manager.getLastWordChangeDate() ?? Date(timeIntervalSince1970: 0)
        let elapsedSeconds = now.timeIntervalSince(lastChange)
        
        // Eğer aralık süresi dolmuşsa kelimeyi otomatik değiştir
        if elapsedSeconds >= intervalSeconds {
            manager.forceNextWord()
        }
        
        let currentWord = resolveCurrentWord()
        let entries = [SimpleEntry(date: now, word: currentWord)]
        
        // Bir sonraki güncelleme zamanını hesapla (son değişim + aralık)
        let updatedLastChange = manager.getLastWordChangeDate() ?? now
        let nextUpdateDate = max(updatedLastChange.addingTimeInterval(intervalSeconds), now.addingTimeInterval(30))
        
        completion(Timeline(entries: entries, policy: .after(nextUpdateDate)))
    }

    private func resolveCurrentWord() -> Word {
        let level = ProgressManager.shared.progress.currentLevel
        let levelWords = WordManager.shared.words(for: level)
        if let id = AppSettingsManager.shared.getCurrentWordId(), let current = levelWords.first(where: { $0.id == id }) {
            return current
        }
        return levelWords.first ?? Word(id: "0", english: "Style", turkish: "Stil", example: "Simplicity is the ultimate sophistication.", level: .a1)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let word: Word
}

// MARK: - "Class & Simple" Widget View

// MARK: - Apple Translucent Glass Widget View

struct DailyWordWidgetExtensionEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) var colorScheme

    private var visualData: (symbol: String, colors: [Color]) {
        EmojiProvider.visuals(for: entry.word.english)
    }

    // Apple New Translucent Light Glass Background
    private var appleGlassBackground: some View {
        ZStack {
            // Base luminous white translucent layer
            Color.white.opacity(0.78)

            // Dynamic soft pastel ambient tint from category
            LinearGradient(
                colors: [
                    (visualData.colors.first ?? Color.cyan).opacity(0.24),
                    Color.white.opacity(0.2),
                    (visualData.colors.last ?? Color.blue).opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Frosted top-down glass specular sheen
            LinearGradient(
                colors: [Color.white.opacity(0.7), Color.white.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle elegant watermark symbol
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: visualData.symbol)
                        .font(.system(size: family == .systemSmall ? 75 : 95, weight: .light))
                        .foregroundColor(Color.black)
                        .opacity(0.04)
                        .offset(x: 12, y: 12)
                }
            }
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("\(entry.word.english): \(entry.word.turkish)", systemImage: visualData.symbol)
                    .widgetAccentable()
                
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: visualData.symbol)
                            .font(.system(size: 10, weight: .semibold))
                        Text(entry.word.level.rawValue)
                            .font(.system(size: 9.5, weight: .black, design: .rounded))
                        Spacer()
                    }
                    .opacity(0.8)
                    
                    Text(entry.word.english)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .widgetAccentable()
                    
                    Text(entry.word.turkish)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(0.88)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: visualData.symbol)
                        .font(.title3)
                    Text(entry.word.english)
                        .font(.system(size: 9.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                
            case .systemSmall:
                // Small Widget: Perfectly fitted, balanced spacing
                VStack(alignment: .leading, spacing: 0) {
                    // Top: Level pill & Category Symbol
                    HStack {
                        HStack(spacing: 4) {
                            Text(entry.word.level.rawValue)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                            Text("•")
                                .font(.system(size: 8))
                                .opacity(0.6)
                            Text(entry.word.level.description)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.15, green: 0.20, blue: 0.30))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.85))
                                .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.8))
                        )
                        
                        Spacer()
                        
                        Image(systemName: visualData.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.25, green: 0.35, blue: 0.45))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.75)))
                    }
                    
                    Spacer()
                    
                    // Middle: English & Turkish Words (Enlarged)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.word.english)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.08, green: 0.10, blue: 0.16))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        
                        Text(entry.word.turkish)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.28, green: 0.38, blue: 0.50))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    
                    Spacer()
                    
                    // Bottom: Action Button / Streak Indicator
                    HStack {
                        Text("Günün Kelimesi")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Color(red: 0.45, green: 0.52, blue: 0.60))
                        
                        Spacer()
                        
                        if #available(iOS 17.0, *) {
                            if AppSettingsManager.shared.isPremium {
                                Button(intent: NextWordIntent()) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(red: 0.1, green: 0.15, blue: 0.25))
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.white.opacity(0.9)))
                                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(14)
                
            default:
                // Medium Widget: Dual-card layout with enlarged sentence card
                HStack(spacing: 10) {
                    // Left Column: Word & Level (compact width ~120pt)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(entry.word.level.rawValue)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                            Text("•")
                                .font(.system(size: 8))
                                .opacity(0.6)
                            Text(entry.word.level.description)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.15, green: 0.20, blue: 0.30))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.85))
                                .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.8))
                        )
                        
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.word.english)
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.08, green: 0.10, blue: 0.16))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            
                            Text(entry.word.turkish)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(red: 0.28, green: 0.38, blue: 0.50))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        
                        Spacer()
                        
                        if #available(iOS 17.0, *) {
                            if AppSettingsManager.shared.isPremium {
                                Button(intent: NextWordIntent()) {
                                    HStack(spacing: 4) {
                                        Text("Sonraki")
                                            .font(.system(size: 10, weight: .bold))
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .foregroundColor(Color(red: 0.1, green: 0.15, blue: 0.25))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.9)))
                                    .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 9))
                                    Text("Günlük Kelime")
                                        .font(.system(size: 9.5, weight: .medium))
                                }
                                .foregroundColor(Color(red: 0.45, green: 0.52, blue: 0.60))
                            }
                        }
                    }
                    .frame(width: 120, alignment: .leading)
                    
                    // Right Column: Enlarged Frosted Glass Card for Examples
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 9))
                                .foregroundColor(Color.orange.opacity(0.8))
                            Text("ÖRNEK CÜMLE")
                                .font(.system(size: 8.5, weight: .black))
                                .foregroundColor(Color(red: 0.40, green: 0.48, blue: 0.56))
                            Spacer()
                            Image(systemName: visualData.symbol)
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.35, green: 0.45, blue: 0.55))
                        }
                        
                        Text("\"\(entry.word.example)\"")
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .italic()
                            .foregroundColor(Color(red: 0.12, green: 0.15, blue: 0.22))
                            .lineLimit(8)
                            .minimumScaleFactor(0.4)
                            .lineSpacing(2)
                        
                        if let tr = entry.word.exampleTurkish, !tr.isEmpty {
                            Text(tr)
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(red: 0.42, green: 0.50, blue: 0.60))
                                .lineLimit(6)
                                .minimumScaleFactor(0.4)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.white.opacity(0.68))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            )
                    )
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
            }
        }
        .containerBackground(for: .widget) {
            appleGlassBackground
        }
    }
}

// MARK: - Widget Configuration

@main
struct DailyWordWidgetExtension: Widget {
    let kind: String = "DailyWordWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DailyWordWidgetExtensionEntryView(entry: entry)
        }
        .configurationDisplayName("Wordlet")
        .description("Clean and classic vocabulary learning.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
