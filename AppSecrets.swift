import Foundation
import Security

enum AppSecrets {
    /// Reads a local build setting. Never commit a production key to this file,
    /// Info.plist, or a checked-in xcconfig.
    static var pokemonTCGApiKey: String? {
        let plistValue = Bundle.main.object(forInfoDictionaryKey: "POKEMON_TCG_API_KEY") as? String
        let environmentValue = ProcessInfo.processInfo.environment["POKEMON_TCG_API_KEY"]

        return [plistValue, environmentValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { value in
                !value.isEmpty
                    && value != "$(POKEMON_TCG_API_KEY)"
                    && value.uppercased() != "POKEMON_TCG_API_KEY"
            })
    }

    static var hasPokemonTCGKey: Bool {
        pokemonTCGApiKey != nil
    }

    static var priceChartingAPIToken: String? {
        configuredValue(named: "PRICECHARTING_API_TOKEN")
    }

    static var hasPriceChartingToken: Bool {
        priceChartingAPIToken != nil
    }

    static var cardSightAPIKey: String? {
        configuredValue(named: "CARDSIGHT_API_KEY")
            ?? keychainValue(account: "CARDSIGHT_API_KEY")
    }

    static var hasCardSightAPIKey: Bool {
        cardSightAPIKey != nil
    }

    @discardableResult
    static func saveCardSightAPIKey(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.carlinjon.held.api",
            kSecAttrAccount as String: "CARDSIGHT_API_KEY"
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return true }

        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static var numistaAPIKey: String? {
        configuredValue(named: "NUMISTA_API_KEY")
    }

    static var hasNumistaAPIKey: Bool {
        numistaAPIKey != nil
    }

    private static func configuredValue(named key: String) -> String? {
        let plistValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let environmentValue = ProcessInfo.processInfo.environment[key]
        return [plistValue, environmentValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "$(\(key))" && $0.uppercased() != key }
    }

    private static func keychainValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.carlinjon.held.api",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
