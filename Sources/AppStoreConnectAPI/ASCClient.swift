import Foundation
#if canImport(Crypto)
import Crypto
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor ASCClient {
    private var auth: ASCAuthorization
    private let configuration: ASCClientConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        credentials: ASCCredentials,
        configuration: ASCClientConfiguration = .default,
        session: URLSession? = nil
    ) {
        self.auth = ASCAuthorization(credentials: credentials)
        self.configuration = configuration

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = configuration.timeoutSeconds
            config.timeoutIntervalForResource = configuration.timeoutSeconds
            self.session = URLSession(configuration: config)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        self.decoder = decoder
    }

    public struct ASCRawResponse: Sendable {
        public let statusCode: Int
        public let headers: [String: String]
        public let body: Data
    }

    /// Like `performRaw`, but does not throw on non-2xx status codes. This is useful for
    /// tooling that needs access to the raw status/headers/body to implement its own
    /// error handling and output contract.
    public func performRawResponse(
        method: String,
        url: URL,
        body: Data?,
        authorize: Bool = true,
        addJSONHeaders: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> ASCRawResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await execute(request: request, authorize: authorize, addJSONHeaders: addJSONHeaders)
        var outHeaders: [String: String] = [:]
        for (k, v) in response.allHeaderFields {
            guard let key = k as? String else { continue }
            if let value = v as? String {
                outHeaders[key] = value
            } else {
                outHeaders[key] = String(describing: v)
            }
        }
        return ASCRawResponse(statusCode: response.statusCode, headers: outHeaders, body: data)
    }

    public func performRaw(
        method: String,
        url: URL,
        body: Data?,
        authorize: Bool = true,
        addJSONHeaders: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> Data {
        let raw = try await performRawResponse(
            method: method,
            url: url,
            body: body,
            authorize: authorize,
            addJSONHeaders: addJSONHeaders,
            headers: headers
        )
        guard (200..<300).contains(raw.statusCode) else {
            throw decodeError(statusCode: raw.statusCode, data: raw.body)
        }
        return raw.body
    }

    public func download(url: URL) async throws -> Data {
        try await performRaw(method: "GET", url: url, body: nil, authorize: false, addJSONHeaders: false)
    }

    func decodeError(statusCode: Int, data: Data) -> Error {
        if let apiError = try? decoder.decode(ASCApiErrorResponse.self, from: data), !apiError.errors.isEmpty {
            return ASCError.apiErrors(statusCode: statusCode, errors: apiError.errors)
        }
        let message = String(data: data, encoding: .utf8) ?? ""
        return ASCError.invalidStatusCode(statusCode, message)
    }

    func execute(request: URLRequest, authorize: Bool, addJSONHeaders: Bool) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        let attempts = authorize ? configuration.retryPolicy.count : 0

        for attempt in 0...attempts {
            do {
                var request = request
                if authorize {
                    let token = try auth.bearerToken()
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                if addJSONHeaders {
                    if request.value(forHTTPHeaderField: "Accept") == nil {
                        request.setValue("application/json", forHTTPHeaderField: "Accept")
                    }
                    if (request.httpBody != nil || request.httpBodyStream != nil),
                       request.value(forHTTPHeaderField: "Content-Type") == nil
                    {
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                }

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ASCError.invalidResponse
                }

                if authorize, (http.statusCode == 429 || http.statusCode >= 500) {
                    lastError = decodeError(statusCode: http.statusCode, data: data)
                    if authorize, attempt < attempts {
                        let delay = retryDelaySeconds(attempt: attempt, response: http)
                        if delay > 0 {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                        continue
                    }
                }

                return (data, http)
            } catch {
                lastError = error
                if authorize, attempt < attempts {
                    let delay = retryDelaySeconds(attempt: attempt, response: nil)
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    continue
                }
            }
        }

        if let lastError {
            if let asc = lastError as? ASCError { throw asc }
            throw ASCError.transport(String(describing: lastError))
        }
        throw ASCError.invalidResponse
    }

    private func retryDelaySeconds(attempt: Int, response: HTTPURLResponse?) -> Double {
        if let response,
           let value = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
           seconds > 0
        {
            return seconds
        }
        return configuration.retryPolicy.baseDelaySeconds * Double(attempt + 1)
    }
}
