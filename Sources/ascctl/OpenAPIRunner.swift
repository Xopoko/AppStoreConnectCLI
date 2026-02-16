import AppStoreConnectAPI
import Foundation

protocol RawHTTPPerformer {
    func perform(
        method: String,
        url: URL,
        body: Data?,
        addJSONHeaders: Bool,
        headers: [String: String]
    ) async throws -> OpenAPIRawResponse
}

struct OpenAPIRawResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

struct ASCClientPerformer: RawHTTPPerformer {
    let client: ASCClient

    func perform(
        method: String,
        url: URL,
        body: Data?,
        addJSONHeaders: Bool,
        headers: [String: String]
    ) async throws -> OpenAPIRawResponse {
        let response = try await client.performRawResponse(
            method: method,
            url: url,
            body: body,
            authorize: true,
            addJSONHeaders: addJSONHeaders,
            headers: headers
        )
        return OpenAPIRawResponse(statusCode: response.statusCode, headers: response.headers, body: response.body)
    }
}

struct OpenAPIResolvedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let bodyBytes: Int
    let addJSONHeaders: Bool
}

enum OpenAPIRunner {
    static func resolveRequest(
        plan: OpenAPICallPlan,
        apiRoot: URL,
        pathParams: [String: String],
        queryItems: [URLQueryItem],
        extraHeaders: [String: String],
        body: Data?,
        acceptOverride: String?,
        contentTypeOverride: String?,
        noJSONHeaders: Bool
    ) throws -> OpenAPIResolvedRequest {
        let missing = plan.requiredPathParams.filter { pathParams[$0] == nil }
        if !missing.isEmpty {
            throw CLIError.invalidArgument("Missing --path-param for: \(missing.joined(separator: ", ")).")
        }

        let resolvedPath = try substitutePathParams(pathTemplate: plan.pathTemplate, values: pathParams)

        var relative = resolvedPath
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        guard let baseURL = URL(string: relative, relativeTo: apiRoot) else {
            throw CLIError.invalidArgument("Invalid URL path: \(resolvedPath)")
        }

        let finalURL = try applyQueryItems(url: baseURL, items: queryItems)

        // Header selection.
        let trimmedAccept = acceptOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptFromHeaders = extraHeaders["Accept"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveAccept = (trimmedAccept?.isEmpty == false) ? trimmedAccept : ((acceptFromHeaders?.isEmpty == false) ? acceptFromHeaders : plan.accept)

        let trimmedContentType = contentTypeOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentTypeFromHeaders = extraHeaders["Content-Type"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveContentType = (trimmedContentType?.isEmpty == false) ? trimmedContentType : ((contentTypeFromHeaders?.isEmpty == false) ? contentTypeFromHeaders : plan.contentType)

        let addJSONHeaders: Bool = {
            if noJSONHeaders { return false }
            if effectiveAccept == nil || effectiveAccept == "application/json" { return true }
            return false
        }()

        var headers = extraHeaders
        if let effectiveAccept, !effectiveAccept.isEmpty {
            if !addJSONHeaders || effectiveAccept != "application/json" || (trimmedAccept?.isEmpty == false) {
                headers["Accept"] = effectiveAccept
            }
        }

        if let body, let effectiveContentType, !effectiveContentType.isEmpty {
            _ = body // for clarity
            if !addJSONHeaders || effectiveContentType != "application/json" || (trimmedContentType?.isEmpty == false) {
                headers["Content-Type"] = effectiveContentType
            }
        }

        return OpenAPIResolvedRequest(
            method: plan.method,
            url: finalURL,
            headers: headers,
            bodyBytes: body?.count ?? 0,
            addJSONHeaders: addJSONHeaders
        )
    }

    static func execute(
        plan: OpenAPICallPlan,
        apiRoot: URL,
        pathParams: [String: String],
        queryItems: [URLQueryItem],
        extraHeaders: [String: String],
        body: Data?,
        acceptOverride: String?,
        contentTypeOverride: String?,
        noJSONHeaders: Bool,
        performer: RawHTTPPerformer
    ) async throws -> OpenAPIRawResponse {
        let resolved = try resolveRequest(
            plan: plan,
            apiRoot: apiRoot,
            pathParams: pathParams,
            queryItems: queryItems,
            extraHeaders: extraHeaders,
            body: body,
            acceptOverride: acceptOverride,
            contentTypeOverride: contentTypeOverride,
            noJSONHeaders: noJSONHeaders
        )

        return try await performer.perform(
            method: resolved.method,
            url: resolved.url,
            body: body,
            addJSONHeaders: resolved.addJSONHeaders,
            headers: resolved.headers
        )
    }

    struct PaginatedJSONResult {
        let statusCode: Int
        let headers: [String: String]
        let json: [String: Any]
        let pages: Int
        let items: Int
        let firstRequest: OpenAPIResolvedRequest
    }

    static func executePaginatedGET(
        plan: OpenAPICallPlan,
        apiRoot: URL,
        pathParams: [String: String],
        queryItems: [URLQueryItem],
        extraHeaders: [String: String],
        acceptOverride: String?,
        noJSONHeaders: Bool,
        performer: RawHTTPPerformer,
        limit: Int?
    ) async throws -> PaginatedJSONResult {
        guard plan.method.uppercased() == "GET" else {
            throw CLIError.invalidArgument("--paginate is only supported for GET operations.")
        }

        let hardLimit = limit.map { max(0, $0) }

        // Page size defaults to 200, but don't ask for more than needed.
        let pageSize = min(max(hardLimit ?? 200, 1), 200)

        func withPageSize(_ items: [URLQueryItem]) -> [URLQueryItem] {
            var out = items.filter { $0.name != "limit" }
            out.append(URLQueryItem(name: "limit", value: String(pageSize)))
            return out
        }

        func apiErrorDetails(from body: Data) -> [String: Any] {
            if let any = try? JSONSerialization.jsonObject(with: body, options: []),
               JSONSerialization.isValidJSONObject(any)
            {
                return ["body": any]
            }
            return ["body": String(data: body, encoding: .utf8) ?? ""]
        }

        func nextLink(from json: [String: Any]) -> String? {
            guard let links = json["links"] as? [String: Any] else { return nil }
            let value = links["next"]
            if value is NSNull { return nil }
            return (value as? String)
                .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        func resolveNextURL(_ next: String) -> URL? {
            if let absolute = URL(string: next), absolute.scheme != nil {
                return absolute
            }
            return URL(string: next, relativeTo: apiRoot)
        }

        func applyPageSize(to url: URL) -> URL {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "limit" }
            items.append(URLQueryItem(name: "limit", value: String(pageSize)))
            components.queryItems = items
            return components.url ?? url
        }

        let firstRequest = try resolveRequest(
            plan: plan,
            apiRoot: apiRoot,
            pathParams: pathParams,
            queryItems: withPageSize(queryItems),
            extraHeaders: extraHeaders,
            body: nil,
            acceptOverride: acceptOverride,
            contentTypeOverride: nil,
            noJSONHeaders: noJSONHeaders
        )

        if hardLimit == 0 {
            return PaginatedJSONResult(
                statusCode: 200,
                headers: [:],
                json: ["data": []],
                pages: 0,
                items: 0,
                firstRequest: firstRequest
            )
        }

        let first = try await performer.perform(
            method: firstRequest.method,
            url: firstRequest.url,
            body: nil,
            addJSONHeaders: firstRequest.addJSONHeaders,
            headers: firstRequest.headers
        )

        guard (200..<300).contains(first.statusCode) else {
            throw CLIError.apiError(
                status: first.statusCode,
                message: "API request failed with status \(first.statusCode).",
                details: apiErrorDetails(from: first.body)
            )
        }

        guard let firstAny = try? JSONSerialization.jsonObject(with: first.body, options: []),
              var firstJSON = firstAny as? [String: Any],
              let firstDataArray = firstJSON["data"] as? [Any]
        else {
            throw CLIError.invalidArgument("--paginate requires a JSON response with a top-level object containing `data` as an array.")
        }

        var collectedData: [Any] = firstDataArray
        var includedMerged: [Any] = []
        var includedKeys: Set<String> = []

        if let included = firstJSON["included"] as? [Any] {
            for item in included {
                if let dict = item as? [String: Any],
                   let type = dict["type"] as? String,
                   let id = dict["id"] as? String
                {
                    let key = "\(type)|\(id)"
                    if includedKeys.contains(key) { continue }
                    includedKeys.insert(key)
                }
                includedMerged.append(item)
            }
        }

        var lastLinks: [String: Any]? = firstJSON["links"] as? [String: Any]
        var next = nextLink(from: firstJSON)
        var pages = 1

        while let nextString = next, let nextURL = resolveNextURL(nextString) {
            if let hardLimit, collectedData.count >= hardLimit {
                break
            }

            let urlWithLimit = applyPageSize(to: nextURL)
            let page = try await performer.perform(
                method: "GET",
                url: urlWithLimit,
                body: nil,
                addJSONHeaders: firstRequest.addJSONHeaders,
                headers: firstRequest.headers
            )

            guard (200..<300).contains(page.statusCode) else {
                throw CLIError.apiError(
                    status: page.statusCode,
                    message: "API request failed with status \(page.statusCode).",
                    details: apiErrorDetails(from: page.body)
                )
            }

            guard let pageAny = try? JSONSerialization.jsonObject(with: page.body, options: []),
                  let pageJSON = pageAny as? [String: Any],
                  let pageDataArray = pageJSON["data"] as? [Any]
            else {
                break
            }

            collectedData.append(contentsOf: pageDataArray)

            if let included = pageJSON["included"] as? [Any] {
                for item in included {
                    if let dict = item as? [String: Any],
                       let type = dict["type"] as? String,
                       let id = dict["id"] as? String
                    {
                        let key = "\(type)|\(id)"
                        if includedKeys.contains(key) { continue }
                        includedKeys.insert(key)
                    }
                    includedMerged.append(item)
                }
            }

            lastLinks = pageJSON["links"] as? [String: Any] ?? lastLinks
            next = nextLink(from: pageJSON)
            pages += 1
        }

        if let hardLimit, collectedData.count > hardLimit {
            collectedData = Array(collectedData.prefix(hardLimit))
        }

        firstJSON["data"] = collectedData
        if !includedMerged.isEmpty {
            firstJSON["included"] = includedMerged
        }
        if let lastLinks {
            firstJSON["links"] = lastLinks
        }

        return PaginatedJSONResult(
            statusCode: first.statusCode,
            headers: first.headers,
            json: firstJSON,
            pages: pages,
            items: collectedData.count,
            firstRequest: firstRequest
        )
    }

    private static func substitutePathParams(pathTemplate: String, values: [String: String]) throws -> String {
        var out = pathTemplate
        for (name, rawValue) in values {
            let token = "{\(name)}"
            guard out.contains(token) else { continue }
            let encoded = percentEncodePathComponent(rawValue)
            out = out.replacingOccurrences(of: token, with: encoded)
        }
        return out
    }

    private static func percentEncodePathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func applyQueryItems(url: URL, items: [URLQueryItem]) throws -> URL {
        guard !items.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw CLIError.invalidArgument("Invalid URL: \(url.absoluteString)")
        }
        var existing = components.queryItems ?? []
        existing.append(contentsOf: items)
        components.queryItems = existing
        guard let final = components.url else {
            throw CLIError.invalidArgument("Invalid URL after applying query parameters.")
        }
        return final
    }
}
