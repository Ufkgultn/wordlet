import Foundation
import SwiftUI

public struct EmojiProvider {
    public static func visuals(for word: String) -> (symbol: String, colors: [Color]) {
        let w = word.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Anlamlara göre sembol ve gradient renk çiftleri
        let mapping: [String: (String, [Color])] = [
            // Doğa & Çevre
            "earthquake": ("mountain.2.fill", [Color.brown.opacity(0.4), Color.orange.opacity(0.4)]),
            "star": ("star.fill", [Color.yellow.opacity(0.4), Color.orange.opacity(0.4)]),
            "night": ("moon.stars.fill", [Color.indigo.opacity(0.4), Color.black.opacity(0.6)]),
            "day": ("sun.max.fill", [Color.blue.opacity(0.3), Color.yellow.opacity(0.4)]),
            "desert": ("sun.dust.fill", [Color.orange.opacity(0.4), Color.yellow.opacity(0.3)]),
            "island": ("tree.fill", [Color.green.opacity(0.4), Color.cyan.opacity(0.3)]),
            "mountain": ("mountain.2.fill", [Color.gray.opacity(0.4), Color.blue.opacity(0.2)]),
            "river": ("water.waves", [Color.blue.opacity(0.4), Color.cyan.opacity(0.4)]),
            "fire": ("flame.fill", [Color.red.opacity(0.5), Color.orange.opacity(0.5)]),
            "water": ("drop.fill", [Color.cyan.opacity(0.5), Color.blue.opacity(0.5)]),
            "sun": ("sun.max.fill", [Color.yellow.opacity(0.5), Color.orange.opacity(0.3)]),
            "moon": ("moon.fill", [Color.indigo.opacity(0.4), Color.purple.opacity(0.4)]),
            "tree": ("leaf.fill", [Color.green.opacity(0.5), Color.mint.opacity(0.4)]),
            "flower": ("camera.macro", [Color.pink.opacity(0.4), Color.purple.opacity(0.3)]),
            
            // Duygular & Durumlar
            "sad": ("face.dashed", [Color.gray.opacity(0.4), Color.blue.opacity(0.3)]),
            "upset": ("cloud.rain.fill", [Color.gray.opacity(0.5), Color.blue.opacity(0.4)]),
            "cry": ("cloud.heavyrain.fill", [Color.blue.opacity(0.5), Color.indigo.opacity(0.4)]),
            "happy": ("face.smiling", [Color.yellow.opacity(0.4), Color.orange.opacity(0.3)]),
            "smile": ("face.smiling", [Color.yellow.opacity(0.4), Color.orange.opacity(0.3)]),
            "angry": ("exclamationmark.triangle.fill", [Color.red.opacity(0.5), Color.orange.opacity(0.4)]),
            "love": ("heart.fill", [Color.red.opacity(0.4), Color.pink.opacity(0.4)]),
            "success": ("trophy.fill", [Color.yellow.opacity(0.5), Color.orange.opacity(0.4)]),
            "fail": ("xmark.octagon.fill", [Color.red.opacity(0.5), Color.gray.opacity(0.4)]),
            "danger": ("exclamationmark.shield.fill", [Color.orange.opacity(0.5), Color.red.opacity(0.4)]),
            "protect": ("shield.fill", [Color.blue.opacity(0.4), Color.cyan.opacity(0.3)]),
            
            // Günlük Nesneler & Eylemler
            "money": ("dollarsign.circle.fill", [Color.green.opacity(0.5), Color.mint.opacity(0.3)]),
            "rich": ("banknote.fill", [Color.green.opacity(0.5), Color.yellow.opacity(0.3)]),
            "hospital": ("cross.case.fill", [Color.red.opacity(0.4), Color.white.opacity(0.2)]),
            "art": ("paintpalette.fill", [Color.purple.opacity(0.4), Color.pink.opacity(0.4)]),
            "music": ("music.note", [Color.indigo.opacity(0.4), Color.pink.opacity(0.3)])
        ]
        
        // Genel fallback listesi (renksiz veya nötr renkli)
        let fallbackMapping: [String: String] = [
            "gate": "door.left.hand.open", "invite": "envelope.fill", "wedding": "rings.2",
            "slice": "chart.pie.fill", "butter": "cube.fill", "card": "creditcard.fill",
            "friendship": "person.2.fill", "security": "lock.shield.fill",
            "save": "square.and.arrow.down.fill", "edit": "pencil.line", "reply": "arrowshape.turn.up.left.fill", 
            "interrupt": "hand.raised.fill", "language": "bubble.left.and.bubble.right.fill",
            "book": "book.closed.fill", "school": "building.columns.fill", 
            "airport": "airplane.departure", "watch": "applewatch", "tie": "lanyardcard.fill", 
            "sale": "tag.fill", "bread": "bag.fill", "coffee": "cup.and.saucer.fill", 
            "food": "fork.knife", "drink": "mug.fill", "house": "house.fill", 
            "car": "car.fill", "plane": "airplane", "phone": "iphone",
            "computer": "laptopcomputer", "camera": "camera.fill"
        ]
        
        let defaultColors = [Color.gray.opacity(0.2), Color.gray.opacity(0.05)]
        
        if let direct = mapping[w] { return direct }
        if let directFallback = fallbackMapping[w] { return (directFallback, defaultColors) }
        
        for (key, val) in mapping {
            if w.contains(key) { return val }
        }
        for (key, val) in fallbackMapping {
            if w.contains(key) { return (val, defaultColors) }
        }
        
        // Premium genel ikon ve nötr arka plan (eğer kelime bulunamazsa)
        return ("sparkles", defaultColors)
    }
}
