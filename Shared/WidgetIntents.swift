import AppIntents
import WidgetKit

@available(iOS 17.0, *)
public struct NextWordIntent: AppIntent {
    public static var title: LocalizedStringResource = "Sıradaki Kelime"

    public init() {}

    public func perform() async throws -> some IntentResult {
        let manager = AppSettingsManager.shared
        
        // Sadece premium kullanıcıların kelimeyi değiştirmesine izin ver
        guard manager.isPremium else {
            return .result()
        }
        
        manager.forceNextWord()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
