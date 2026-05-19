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
        let currentWord = resolveCurrentWord()
        let manager = AppSettingsManager.shared
        let intervalMinutes = max(5, min(300, manager.settings.widgetUpdateIntervalMinutes))
        
        let entries = [SimpleEntry(date: now, word: currentWord)]
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Double(intervalMinutes) * 60))))
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

struct DailyWordWidgetExtensionEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) var colorScheme

    private var emoji: String {
        EmojiProvider.emoji(for: entry.word.english)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("\(emoji) \(entry.word.english): \(entry.word.turkish)")
                    .widgetAccentable()
                
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(emoji)
                        Text(entry.word.level.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .opacity(0.8)
                    }
                    
                    Text(entry.word.english)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    
                    Text(entry.word.turkish)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(emoji)
                        .font(.title2)
                    Text(entry.word.english)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                
            default:
                // Standart Ana Ekran Widgetları (Small/Medium)
                VStack(alignment: .leading, spacing: 0) {
                    // Üst Kısım: Seviye ve Emoji
                    HStack {
                        Text(entry.word.level.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.4))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).stroke(colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.1), lineWidth: 1))
                        
                        Spacer()
                        
                        Text(emoji)
                            .font(.title2)
                    }
                    .padding(.bottom, 6)
                    
                    Spacer()
                    
                    // Orta Kısım: Kelime ve Anlam
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.word.english)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        Text(entry.word.turkish)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Alt Kısım: Örnek Cümle
                    if family != .systemSmall {
                        Text(entry.word.example)
                            .font(.system(size: 13))
                            .italic()
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
                            .lineLimit(4)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    
                    // Buton (iOS 17+)
                    if #available(iOS 17.0, *) {
                        HStack {
                            Spacer()
                            Button(intent: NextWordIntent()) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(6)
                                    .background(Circle().fill(colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(14)
            }
        }
        .containerBackground(colorScheme == .dark ? Color(white: 0.1) : Color.white, for: .widget)
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
        .configurationDisplayName("Daily Word")
        .description("Clean and classic vocabulary learning.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
