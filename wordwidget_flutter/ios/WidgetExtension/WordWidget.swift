import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WordEntry {
        WordEntry(date: Date(), word: "Book", meaning: "kitap", example: "I read a book.")
    }

    func getSnapshot(in context: Context, completion: @escaping (WordEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WordEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> WordEntry {
        let defaults = UserDefaults(suiteName: "group.com.example.wordwidget")
        return WordEntry(
            date: Date(),
            word: defaults?.string(forKey: "word") ?? "Word",
            meaning: defaults?.string(forKey: "meaning") ?? "Anlam",
            example: defaults?.string(forKey: "example") ?? "Example"
        )
    }
}

struct WordEntry: TimelineEntry {
    let date: Date
    let word: String
    let meaning: String
    let example: String
}

struct WordWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.word).font(.headline)
            Text(entry.meaning).font(.subheadline).foregroundColor(.secondary)
            Text(entry.example).font(.caption)
        }
        .padding()
    }
}

struct WordWidget: Widget {
    let kind: String = "WordWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WordWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("WordWidget")
        .description("Learn a new English word from your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
