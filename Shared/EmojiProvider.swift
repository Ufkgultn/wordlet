import Foundation

public struct EmojiProvider {
    public static func emoji(for word: String) -> String {
        let w = word.lowercased().trimmingCharacters(in: .whitespaces)
        
        let mapping: [String: String] = [
            // Doğa
            "gate": "🚪", "earthquake": "🌋", "invite": "✉️", "wedding": "💍",
            "star": "⭐", "night": "🌙", "day": "☀️", "gift": "🎁",
            "rich": "💰", "slice": "🍕", "butter": "🧈", "card": "💳",
            "sad": "😔", "language": "🗣️", "desert": "🏜️", "island": "🏝️",
            "mountain": "🏔️", "river": "🏞️", "fire": "🔥", "water": "💧",
            "sun": "☀️", "moon": "🌙", "tree": "🌳", "flower": "🌸",
            
            // Eylemler & Duygular
            "upset": "😢", "cry": "😭", "happy": "😊", "smile": "🙂",
            "angry": "😠", "love": "❤️", "friendship": "🤝", "success": "🏆",
            "fail": "❌", "danger": "⚠️", "security": "🔒", "protect": "🛡️",
            "save": "💾", "edit": "✍️", "reply": "↩️", "interrupt": "🚫",
            
            // Günlük Hayat
            "book": "📖", "school": "🏫", "hospital": "🏥", "airport": "✈️",
            "watch": "⌚", "tie": "👔", "money": "💵", "sale": "🏷️",
            "bread": "🍞", "coffee": "☕", "food": "🍎", "drink": "🥤",
            "house": "🏠", "car": "🚗", "plane": "✈️", "phone": "📱",
            "computer": "💻", "music": "🎵", "camera": "📷", "art": "🎨"
        ]
        
        if let direct = mapping[w] { return direct }
        
        for (key, val) in mapping {
            if w.contains(key) { return val }
        }
        
        // Eğer hiçbir şey bulamazsa kelimenin ilk harfine göre bir şey dönebiliriz veya genel bir ikon
        return "✨" 
    }
}
