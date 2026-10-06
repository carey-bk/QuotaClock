import Foundation
import QuotaCore

extension SnapshotController {
    /// Validation is opt-in and never scheduled. Only the parsed usage object survives the request.
    func validateAndAdd(_ config: GenericAPIConfiguration, key: String) async -> Bool {
        guard !onboardingPreview else { return false }
        guard !validatingAPI else { return false }
        validatingAPI = true; apiFeedback = nil
        defer { validatingAPI = false }
        let keychain = ProductKeychain(config.credentialIdentity)
        do {
            guard try apiRegistry.read() == customAPIs, !customAPIs.contains(where: { $0.id == config.id }) else {
                throw ResponsesUsageError.storage
            }
            let usage = try await ResponsesUsageTransport().validate(config, credential: key.trimmingCharacters(in: .whitespacesAndNewlines))
            try keychain.save(key)
            do {
                try await usageStore.append(ObservedUsageRecord(timestamp: .now, providerID: config.providerID,
                    productID: config.productID, model: config.model, usage: usage))
                try apiRegistry.write(customAPIs + [config])
            } catch {
                try? keychain.delete(); try? await usageStore.remove(productID: config.productID)
                throw ResponsesUsageError.storage
            }
            customAPIs.append(config)
            await coordinator?.register(GenericAPIProduct(configuration: config, store: usageStore))
            var next = platform
            next.enabledProducts.insert(config.productID)
            next.connectionOrder = (next.connectionOrder ?? []) + [config.providerID]
            next.menuOrder.append(config.providerID); next.saverOrder.append(config.providerID)
            try next.save(); platform = next
            if let coordinator {
                do { show(try await coordinator.configure(next)) }
                catch { self.error = "Could not publish display settings" }
            }
            refreshProduct(config.productID)
            apiFeedback = "API validated. Only requests observed by QuotaClock are counted."
            return true
        } catch {
            apiFeedback = (error as? ResponsesUsageError)?.errorDescription ?? "Could not save custom API settings."
            return false
        }
    }
    func validateAPI(_ config: GenericAPIConfiguration) async {
        guard !onboardingPreview else { return }
        guard !validatingAPI else { return }
        validatingAPI = true; apiFeedback = nil
        defer { validatingAPI = false }
        do {
            guard let key = ProductKeychain(config.credentialIdentity).read() else { throw ResponsesUsageError.authentication }
            let usage = try await ResponsesUsageTransport().validate(config, credential: key)
            try await usageStore.append(ObservedUsageRecord(timestamp: .now, providerID: config.providerID,
                productID: config.productID, model: config.model, usage: usage))
            refreshProduct(config.productID)
            apiFeedback = "API validated. Only requests observed by QuotaClock are counted."
        } catch { apiFeedback = (error as? ResponsesUsageError)?.errorDescription ?? "Could not save local usage." }
    }
    func removeAPI(_ config: GenericAPIConfiguration) async {
        guard !onboardingPreview else { return }
        guard !validatingAPI else { return }
        do {
            let remaining = customAPIs.filter { $0.id != config.id }
            // Hide first; a partial deletion must never leave a credential-backed active product.
            var next = platform
            next.enabledProducts.remove(config.productID); next.display[config.providerID] = nil
            next.menuOrder.removeAll { $0 == config.providerID }; next.saverOrder.removeAll { $0 == config.providerID }
            try next.save(); platform = next
            await coordinator?.unregister(config.productID)
            if let coordinator { show(try await coordinator.configure(next)) }
            try ProductKeychain(config.credentialIdentity).delete()
            try await usageStore.remove(productID: config.productID)
            try apiRegistry.write(remaining); customAPIs = remaining
            apiFeedback = nil
        } catch { apiFeedback = "Could not remove all custom API data. Try again." }
    }
}
