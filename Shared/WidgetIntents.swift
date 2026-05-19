import AppIntents
import WidgetKit

@available(iOS 17.0, *)
public struct NextWordIntent: AppIntent {
    public static var title: LocalizedStringResource = "Sıradaki Kelime"

    public init() {}

    public func perform() async throws -> some IntentResult {
        let manager = AppSettingsManager.shared
        
        // Premium değilse ve limit (5) dolduysa değiştirme (sessizce dön)
        if !manager.isPremium && manager.dailyManualChangeCount >= 5 {
            return .result()
        }
        
        // Değişim yap ve kotayı artır
        if !manager.isPremium {
            manager.dailyManualChangeCount += 1
        }
        
        manager.forceNextWord()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
