import Foundation
import CoreFoundation

public enum APIProtocol: String, Codable, CaseIterable, Sendable {
    case responses, chatCompletions
    public var supported: Bool { self == .responses }
}

/// No credential value, request content or arbitrary headers are serializable configuration.
public struct GenericAPIConfiguration: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: String
    public var model: String
    public var apiProtocol: APIProtocol
    public init(id: UUID = UUID(), name: String, baseURL: String, model: String, apiProtocol: APIProtocol = .responses) {
        self.id = id; self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines); self.apiProtocol = apiProtocol
    }
    public var providerID: String { "custom." + id.uuidString.lowercased() }
    public var productID: String { providerID + ".responses" }
    public var credentialIdentity: CredentialIdentity { .init(providerID: providerID, productID: productID) }
    public var descriptor: ProductDescriptor {
        .init(id: productID, providerID: providerID, displayName: name, reliability: .officialLocalState, connection: "responses")
    }
    public func endpoint() throws -> URL {
        guard !name.isEmpty, name.count <= 60, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              model.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$"#, options: .regularExpression) != nil,
              baseURL.utf8.count <= 2048, apiProtocol.supported,
              var parts = URLComponents(string: baseURL), parts.scheme == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw ResponsesUsageError.configuration
        }
        let path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = "/" + (path.split(separator: "/").last == "responses" ? path : (path.isEmpty ? "responses" : path + "/responses"))
        guard let url = parts.url else { throw ResponsesUsageError.configuration }
        return url
    }
}

public enum ResponsesUsageError: Error, LocalizedError, Equatable {
    case configuration, authentication, rateLimited, timeout, transport, schema, storage
    public var errorDescription: String? {
        switch self {
        case .configuration: "Use an HTTPS API base URL without credentials or query parameters, a name and a model."
        case .authentication: "The API rejected this key (401/403)."
        case .rateLimited: "The API rate limit was reached. Try again later."
        case .timeout: "The API request timed out."
        case .transport: "Could not reach the Responses endpoint. Check the base URL and protocol."
        case .schema: "The endpoint did not return valid Responses usage. No usage was recorded."
        case .storage: "Could not save local usage."
        }
    }
}

/// Ephemeral, no cookies/cache, no redirect forwarding of Authorization to another endpoint.
public final class ResponsesHTTPClient: NSObject, ProviderHTTPClient, URLSessionTaskDelegate, @unchecked Sendable {
    public override init() { super.init() }
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > 4_194_304 { throw ResponsesUsageError.schema }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 4_194_304 else { throw ResponsesUsageError.schema }
            data.append(byte)
        }
        return (data, response)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct ResponsesTokenUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let totalTokens: Int64
    public let cachedTokens: Int64?
    public let reasoningTokens: Int64?
    public func validated() throws -> Self {
        let limit: Int64 = 1_000_000_000_000
        guard (0...limit).contains(inputTokens), (0...limit).contains(outputTokens),
              totalTokens == inputTokens + outputTokens,
              cachedTokens.map({ (0...inputTokens).contains($0) }) ?? true,
              reasoningTokens.map({ (0...outputTokens).contains($0) }) ?? true else { throw ResponsesUsageError.schema }
        return self
    }
    public static func parse(_ data: Data) throws -> Self {
        guard data.count <= 4_194_304,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["object"] as? String == "response",
              ["completed", "incomplete"].contains(root["status"] as? String ?? ""),
              root["error"] == nil || root["error"] is NSNull,
              let usage = root["usage"] as? [String: Any] else { throw ResponsesUsageError.schema }
        func count(_ value: Any?) throws -> Int64 {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 2_000_000_000_000,
                  number.doubleValue.rounded(.towardZero) == number.doubleValue else { throw ResponsesUsageError.schema }
            return number.int64Value
        }
        func optional(_ group: String, _ key: String) throws -> Int64? {
            guard let value = usage[group], !(value is NSNull) else { return nil }
            guard let details = value as? [String: Any] else { throw ResponsesUsageError.schema }
            guard let value = details[key], !(value is NSNull) else { return nil }
            return try count(value)
        }
        return try Self(inputTokens: count(usage["input_tokens"]), outputTokens: count(usage["output_tokens"]),
            totalTokens: count(usage["total_tokens"]), cachedTokens: optional("input_tokens_details", "cached_tokens"),
            reasoningTokens: optional("output_tokens_details", "reasoning_tokens")).validated()
    }
}

public struct ResponsesUsageTransport: Sendable {
    private let client: any ProviderHTTPClient
    public init(client: any ProviderHTTPClient = ResponsesHTTPClient()) { self.client = client }
    /// Explicit user-initiated probe only. Automatic refresh never calls this method.
    public func validate(_ config: GenericAPIConfiguration, credential: String) async throws -> ResponsesTokenUsage {
        try await usage(for: config, credential: credential, input: "Reply OK.", maxOutputTokens: 16)
    }
    /// Adapter integration boundary. Input is transient; this transport returns only allowlisted usage.
    /// Callers must explicitly authorize a request and append a content-free ObservedUsageRecord.
    public func usage(for config: GenericAPIConfiguration, credential: String, input: String,
                      maxOutputTokens: Int) async throws -> ResponsesTokenUsage {
        guard !input.isEmpty, input.utf8.count <= 65_536, (1...4096).contains(maxOutputTokens) else {
            throw ResponsesUsageError.configuration
        }
        var request = URLRequest(url: try config.endpoint())
        guard !credential.isEmpty, !credential.contains("\n"), !credential.contains("\r") else { throw ResponsesUsageError.authentication }
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("Bearer " + credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": config.model, "input": input,
            "max_output_tokens": maxOutputTokens, "stream": false, "store": false])
        do {
            let (data, response) = try await client.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ResponsesUsageError.transport }
            switch http.statusCode {
            case 200: return try ResponsesTokenUsage.parse(data)
            case 401, 403: throw ResponsesUsageError.authentication
            case 429: throw ResponsesUsageError.rateLimited
            default: throw ResponsesUsageError.transport
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as ResponsesUsageError { throw error }
        catch let error as URLError where error.code == .timedOut { throw ResponsesUsageError.timeout }
        catch { throw ResponsesUsageError.transport }
    }
}
