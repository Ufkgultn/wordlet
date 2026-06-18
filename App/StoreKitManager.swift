import Foundation
import StoreKit
import WidgetKit

@MainActor
public class StoreKitManager: ObservableObject {
    public static let shared = StoreKitManager()
    
    // Product IDs
    public static let monthlyID = "com.ufuk.DailyWordWidget.monthly"
    public static let yearlyID = "com.ufuk.DailyWordWidget.yearly"
    public static let lifetimeID = "com.ufuk.DailyWordWidget.lifetime"
    
    private let productIDs = [monthlyID, yearlyID, lifetimeID]
    
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchasedProductIDs = Set<String>()
    @Published public var isLoading = false
    @Published public var purchaseError: String? = nil
    
    private var transactionListenerTask: Task<Void, Error>? = nil
    
    private init() {
        // İşlemleri dinlemeye başla
        transactionListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }
    
    deinit {
        transactionListenerTask?.cancel()
    }
    
    // MARK: - Load Products
    
    public func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: productIDs)
            // Tanımladığımız sırayla sırala
            self.products = storeProducts.sorted { p1, p2 in
                let id1 = p1.id
                let id2 = p2.id
                let index1 = productIDs.firstIndex(of: id1) ?? 99
                let index2 = productIDs.firstIndex(of: id2) ?? 99
                return index1 < index2
            }
        } catch {
            print("StoreKitManager: Failed to fetch products: \(error)")
        }
    }
    
    // MARK: - Purchase
    
    public func purchase(_ product: Product) async -> Bool {
        isLoading = true
        purchaseError = nil
        
        defer { isLoading = false }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                
                // Başarılı satın alım sonrası işlemleri kaydet
                await updatePurchasedProducts()
                await transaction.finish()
                
                // Widget'ı yenile
                WidgetCenter.shared.reloadAllTimelines()
                return true
                
            case .pending:
                purchaseError = "Satın alma bekliyor. Ödeme yönteminizi doğrulamanız gerekebilir."
                return false
                
            case .userCancelled:
                return false
                
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    public func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            purchaseError = "Satın alımlar geri yüklenirken hata oluştu: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Verification Helper
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.networkError(URLError(.cannotDecodeContentData))
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Update Purchase Status
    
    public func updatePurchasedProducts() async {
        var activePurchases = Set<String>()
        
        // Aktif işlem geçmişini tara
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                activePurchases.insert(transaction.productID)
            } catch {
                print("StoreKitManager: Transaction verification failed: \(error)")
            }
        }
        
        self.purchasedProductIDs = activePurchases
        
        // Eğer en az bir ürün satın alınmışsa Premium yap, yoksa normal yap
        let isPremiumUser = !activePurchases.isEmpty
        AppSettingsManager.shared.isPremium = isPremiumUser
    }
    
    // MARK: - Background Transaction Listener
    
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                    await WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    print("StoreKitManager: Background update verification failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Simulator Debug Buy Helper (Test Kolaylığı İçin)
    
    public func toggleDebugPremium() {
        let current = AppSettingsManager.shared.isPremium
        AppSettingsManager.shared.isPremium = !current
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum StoreKitError: Error {
    case networkError(Error)
}
