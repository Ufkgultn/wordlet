import Foundation
import Supabase

public class SupabaseManager {
    public static let shared = SupabaseManager()
    
    public let client: SupabaseClient
    
    private init() {
        self.client = SupabaseClient(
            supabaseURL: Secrets.supabaseURL,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }
}
