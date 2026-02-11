import Foundation

struct ConnectionConfig {

    private static let gatewayURLKey = "gatewayURL"
    private static let sessionKeyKey = "sessionKey"
    private static let tokenKeychainKey = "gatewayToken"

    var gatewayURL: String {
        get { UserDefaults.standard.string(forKey: Self.gatewayURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.gatewayURLKey) }
    }

    var sessionKey: String {
        get { UserDefaults.standard.string(forKey: Self.sessionKeyKey) ?? "agent:main:main" }
        set { UserDefaults.standard.set(newValue, forKey: Self.sessionKeyKey) }
    }

    var token: String {
        get { KeychainService.load(key: Self.tokenKeychainKey) ?? "" }
        set { KeychainService.save(key: Self.tokenKeychainKey, value: newValue) }
    }

    var isConfigured: Bool {
        !gatewayURL.isEmpty && !token.isEmpty
    }
}
