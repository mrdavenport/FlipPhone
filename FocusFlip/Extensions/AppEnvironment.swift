import Foundation
import UIKit

extension Bundle {
    /// Returns true if the app is running in TestFlight
    var isTestFlight: Bool {
        #if DEBUG
        // For testing: Set to true to test the thank you screen in DEBUG mode
        // Set to false for normal development
        return false // Change to true to test thank you screen
        #else
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return false
        }
        return receiptURL.lastPathComponent == "sandboxReceipt"
        #endif
    }
}

