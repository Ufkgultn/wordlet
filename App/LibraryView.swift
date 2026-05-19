import SwiftUI

struct LibraryView: View {
    @State private var seenWords: [Word] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Learned Words")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(seenWords.count) kelime widget/app akışından eklendi")
                        .font(.headline)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)

            List(seenWords, id: \.id) { word in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(word.english).font(.headline)
                        Text("\(word.turkish) • \(word.example)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let trExample = word.exampleTurkish {
                            Text(trExample)
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.9))
                        }
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            SpeechManager.shared.speakEnglish(word: word.english, example: word.example)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            SpeechManager.shared.speakTurkish(meaning: word.turkish, exampleTurkish: word.exampleTurkish)
                        } label: {
                            Image(systemName: "speaker.wave.1.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            seenWords = WordManager.shared.seenWords
        }
        .onReceive(NotificationCenter.default.publisher(for: .wordFlowDidChange)) { _ in
            seenWords = WordManager.shared.seenWords
        }
    }
}
