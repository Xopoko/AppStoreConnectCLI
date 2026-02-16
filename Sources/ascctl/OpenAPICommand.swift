import AppStoreConnectAPI
import ArgumentParser
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct OpenAPICommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "openapi",
        abstract: "Spec-driven universal access to the App Store Connect OpenAPI specification.",
        subcommands: [
            Spec.self,
            Ops.self,
            Op.self,
            Schemas.self,
        ]
    )

    struct SpecOptions: ParsableArguments {
        @Option(name: .customLong("spec"), help: "Path to OpenAPI spec JSON file (default: ./openapi.oas.json).")
        var specPath: String?
    }

    static func resolveSpecURL(specPath: String?) throws -> URL {
        if let specPath, !specPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: PathUtils.expandTilde(specPath))
        }
        let local = URL(fileURLWithPath: "openapi.oas.json")
        if FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        throw CLIError.missingRequiredOption("Missing OpenAPI spec. Run `ascctl openapi spec update` or pass --spec.")
    }

    static func loadSpec(_ spec: SpecOptions) throws -> (url: URL, spec: OpenAPISpec) {
        let url = try resolveSpecURL(specPath: spec.specPath)
        let data = try Data(contentsOf: url)
        return (url: url, spec: try OpenAPISpec(data: data))
    }

    // MARK: - openapi spec

    struct Spec: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "spec",
            abstract: "Manage the pinned OpenAPI spec.",
            subcommands: [
                Update.self
            ]
        )

        struct Update: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                commandName: "update",
                abstract: "Download and write the pinned OpenAPI spec (openapi.oas.json)."
            )

            @Option(help: "Spec URL to fetch (ZIP or JSON). Supports file:// URLs.")
            var url: String?

            @Option(help: "Output path (default: ./openapi.oas.json).")
            var out: String?

            @Flag(help: "Overwrite existing output file.")
            var force: Bool = false

            @OptionGroup
            var global: GlobalOptions

            func run() async throws {
                let command = "openapi.spec.update"

                let fetchURL: URL = {
                    if let url, let u = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme != nil {
                        return u
                    }
                    return URL(string: "https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip")!
                }()

                let outURL: URL = {
                    if let out, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return URL(fileURLWithPath: PathUtils.expandTilde(out))
                    }
                    return URL(fileURLWithPath: "openapi.oas.json")
                }()

                if FileManager.default.fileExists(atPath: outURL.path), !force {
                    throw CLIError.invalidArgument("File already exists: \(outURL.path). Use --force to overwrite.")
                }

                if global.verbose {
                    Output.info("Fetching OpenAPI spec: \(fetchURL.absoluteString)")
                }

                let fetchedBytes: Data
                if fetchURL.isFileURL {
                    do {
                        fetchedBytes = try Data(contentsOf: fetchURL)
                    } catch {
                        throw CLIError.invalidArgument("Failed to read spec from file URL: \(fetchURL.path)")
                    }
                } else {
                    let (data, response) = try await URLSession.shared.data(from: fetchURL)
                    if let http = response as? HTTPURLResponse {
                        guard (200..<300).contains(http.statusCode) else {
                            throw CLIError.network("Failed to fetch OpenAPI spec (status \(http.statusCode)).")
                        }
                    }
                    fetchedBytes = data
                }

                let specData: Data
                if let any = try? JSONSerialization.jsonObject(with: fetchedBytes, options: []),
                   let obj = any as? [String: Any],
                   obj["openapi"] != nil,
                   obj["paths"] != nil
                {
                    specData = fetchedBytes
                } else {
                    specData = try extractSpecJSON(zipData: fetchedBytes)
                }
                let parsed = try OpenAPISpec(data: specData)

                try PathUtils.ensureParentDir(outURL)
                try specData.write(to: outURL, options: [.atomic])

                let downloadedAt = ISO8601DateFormatter().string(from: Date())
                let meta: [String: Any] = [
                    "out": outURL.path,
                    "downloadedAt": downloadedAt,
                    "sourceURL": fetchURL.absoluteString,
                    "sha256": SHA256Hex.digest(specData),
                    "bytes": specData.count,
                    "openapi": parsed.openapi ?? "",
                    "infoTitle": parsed.title ?? "",
                    "infoVersion": parsed.version ?? "",
                    "paths": parsed.pathsCount,
                    "operations": parsed.operationsCount,
                ]

                try Output.envelopeOK(command: command, data: meta, pretty: global.pretty)
            }

            private func extractSpecJSON(zipData: Data) throws -> Data {
                let temp = FileManager.default.temporaryDirectory
                let zipURL = temp.appendingPathComponent("ascctl-openapi-\(UUID().uuidString).zip")
                try zipData.write(to: zipURL, options: [.atomic])
                defer { try? FileManager.default.removeItem(at: zipURL) }

                let zipPath = zipURL.path

                // 1) unzip -p <zip> openapi.oas.json
                do {
                    let result = try ProcessRunner.run(executable: "unzip", arguments: ["-p", zipPath, "openapi.oas.json"])
                    if result.exitCode == 0, !result.stdout.isEmpty {
                        return result.stdout
                    }
                } catch {
                    // ignore, try python
                }

                // 2) python3 zipfile extraction
                let code = "import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); sys.stdout.buffer.write(z.read(sys.argv[2]))"
                do {
                    let result = try ProcessRunner.run(executable: "python3", arguments: ["-c", code, zipPath, "openapi.oas.json"])
                    if result.exitCode == 0, !result.stdout.isEmpty {
                        return result.stdout
                    }
                    let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
                    throw CLIError.invalidArgument("python3 failed to extract OpenAPI spec. \(stderr)")
                } catch let err as CLIError {
                    throw err
                } catch {
                    throw CLIError.missingRequiredOption("Could not extract OpenAPI ZIP. Install `unzip` or `python3`.")
                }
            }
        }
    }

    // MARK: - openapi ops

    struct Ops: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "ops",
            abstract: "Navigate OpenAPI operations.",
            subcommands: [
                List.self
            ]
        )

        struct List: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List operations."
            )

            @OptionGroup
            var spec: SpecOptions

            @Option(parsing: .upToNextOption, help: "Filter by tag (repeatable).")
            var tag: [String] = []

            @Option(parsing: .upToNextOption, help: "Filter by HTTP method (repeatable).")
            var method: [String] = []

            @Option(name: .customLong("path-prefix"), help: "Filter by path prefix.")
            var pathPrefix: String?

            @Option(help: "Text search filter (case-insensitive).")
            var text: String?

            @Option(help: "Max items to return (ignored with --all).")
            var limit: Int = 50

            @Flag(help: "Return all results.")
            var all: Bool = false

            @Flag(name: .customLong("details"), help: "Include derived details (required params, content-types, dangerous).")
            var details: Bool = false

            @OptionGroup
            var global: GlobalOptions

            func run() async throws {
                let command = "openapi.ops.list"
                let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

                var filtered = parsed.filterOperations(tags: tag, methods: method, pathPrefix: pathPrefix, text: text)
                if !all {
                    filtered = Array(filtered.prefix(max(0, limit)))
                }

                let ops = filtered.map { op -> [String: Any] in
                    var obj: [String: Any] = [
                        "method": op.method,
                        "path": op.path,
                        "operationId": op.operationId,
                        "summary": op.summary ?? "",
                        "tags": op.tags,
                    ]
                    if details {
                        let plan = parsed.plan(for: op)
                        obj["dangerous"] = plan.requiresConfirm
                        obj["requiresConfirm"] = plan.requiresConfirm
                        obj["requiredPathParams"] = plan.requiredPathParams
                        obj["requiredQueryParams"] = plan.requiredQueryParams
                        obj["requiredHeaderParams"] = plan.requiredHeaderParams
                        obj["requestBodyRequired"] = plan.requestBodyRequired
                        obj["requestContentTypes"] = plan.requestContentTypes
                        obj["responseContentTypes"] = plan.responseContentTypes
                    }
                    return obj
                }

                try Output.envelopeOK(
                    command: command,
                    data: [
                        "count": ops.count,
                        "specPath": specURL.path,
                        "operations": ops,
                    ],
                    pretty: global.pretty
                )
            }
        }
    }

    // MARK: - openapi op

    struct Op: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "op",
            abstract: "Inspect or execute a single OpenAPI operation.",
            subcommands: [
                Show.self,
                Run.self,
                Template.self,
            ]
        )

        struct OperationSelector: ParsableArguments {
            @Option(name: .customLong("id"), help: "OpenAPI operationId.")
            var operationId: String?

            @Option(name: .customLong("method"), help: "HTTP method.")
            var method: String?

            @Option(name: .customLong("path"), help: "OpenAPI path (e.g. /v1/apps/{id}).")
            var path: String?
        }

        static func resolveOperation(selector: OperationSelector, spec: OpenAPISpec) -> OpenAPIOperation? {
            if let byId = spec.lookup(operationId: selector.operationId) {
                return byId
            }
            return spec.lookup(method: selector.method, path: selector.path)
        }

        struct Show: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                commandName: "show",
                abstract: "Show operation details."
            )

            @OptionGroup
            var selector: OperationSelector

            @OptionGroup
            var spec: SpecOptions

            @OptionGroup
            var global: GlobalOptions

            func run() async throws {
                let command = "openapi.op.show"
                let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

                guard let op = OpenAPICommand.Op.resolveOperation(selector: selector, spec: parsed) else {
                    throw CLIError.invalidArgument("Operation not found. Provide --id or (--method and --path).")
                }

                let plan = parsed.plan(for: op)
                let params = normalizedParameters(op.parameters)

                let details: [String: Any] = [
                    "specPath": specURL.path,
                    "method": op.method,
                    "path": op.path,
                    "operationId": op.operationId,
                    "tags": op.tags,
                    "summary": op.summary ?? "",
                    "description": op.description ?? "",
                    "dangerous": plan.requiresConfirm,
                    "requiresConfirm": plan.requiresConfirm,
                    "required": [
                        "path": plan.requiredPathParams,
                        "query": plan.requiredQueryParams,
                        "header": plan.requiredHeaderParams,
                    ],
                    "parameters": params,
                    "request": [
                        "bodyRequired": plan.requestBodyRequired,
                        "contentTypes": plan.requestContentTypes,
                        "contentType": plan.contentType as Any,
                    ],
                    "response": [
                        "contentTypes": plan.responseContentTypes,
                        "accept": plan.accept as Any,
                        "kind": responseKind(op: op, spec: parsed),
                    ],
                ]

                try Output.envelopeOK(command: command, data: details, pretty: global.pretty)
            }

            private func normalizedParameters(_ params: [[String: Any]]) -> [String: Any] {
                var grouped: [String: [[String: Any]]] = [:]
                for p in params {
                    guard let place = p["in"] as? String else { continue }
                    grouped[place, default: []].append(normalizeParam(p))
                }
                for k in grouped.keys {
                    grouped[k]?.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
                }
                return grouped
            }

            private func normalizeParam(_ p: [String: Any]) -> [String: Any] {
                var out: [String: Any] = [:]
                out["name"] = p["name"] as? String ?? ""
                out["in"] = p["in"] as? String ?? ""
                out["required"] = (p["required"] as? Bool) == true
                if let schema = p["schema"] as? [String: Any] {
                    out["schema"] = summarizeSchema(schema)
                }
                if let desc = p["description"] as? String {
                    out["description"] = desc
                }
                return out
            }

            private func summarizeSchema(_ schema: [String: Any]) -> [String: Any] {
                var out: [String: Any] = [:]
                if let ref = schema["$ref"] as? String {
                    out["$ref"] = ref
                }
                if let type = schema["type"] as? String {
                    out["type"] = type
                }
                if let values = schema["enum"] as? [Any] {
                    out["enum"] = values
                }
                return out
            }

            private func responseKind(op: OpenAPIOperation, spec: OpenAPISpec) -> String {
                guard let responses = op.responses else { return "unknown" }
                for (_, rAny) in responses.sorted(by: { $0.key < $1.key }) {
                    guard let r = rAny as? [String: Any] else { continue }
                    let content = r["content"] as? [String: Any] ?? [:]
                    for (_, vAny) in content.sorted(by: { $0.key < $1.key }) {
                        guard let v = vAny as? [String: Any],
                              let schema = v["schema"] as? [String: Any]
                        else { continue }
                        let resolved = OpenAPISchemaResolver(spec: spec).resolveSchema(schema)
                        if let type = resolved["type"] as? String {
                            if type == "array" { return "array" }
                            if type == "object" { return "object" }
                        }
                        if resolved["properties"] != nil { return "object" }
                        if resolved["$ref"] != nil { return "object" }
                    }
                }
                return "unknown"
            }
        }

        struct Template: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                commandName: "template",
                abstract: "Generate a minimal template for `openapi op run`."
            )

            @OptionGroup
            var selector: OperationSelector

            @OptionGroup
            var spec: SpecOptions

            @OptionGroup
            var global: GlobalOptions

            func run() async throws {
                let command = "openapi.op.template"
                let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

                guard let op = OpenAPICommand.Op.resolveOperation(selector: selector, spec: parsed) else {
                    throw CLIError.invalidArgument("Operation not found. Provide --id or (--method and --path).")
                }

                let plan = parsed.plan(for: op)
                let resolver = OpenAPISchemaResolver(spec: parsed)

                // Pick request body schema (prefer application/json).
                var bodyAny: Any? = nil
                if let rb = op.requestBody,
                   let content = rb["content"] as? [String: Any],
                   !content.isEmpty
                {
                    let ct: String = {
                        if content.keys.contains("application/json") { return "application/json" }
                        return content.keys.sorted().first ?? "application/json"
                    }()
                    if let entry = content[ct] as? [String: Any],
                       let schema = entry["schema"] as? [String: Any]
                    {
                        bodyAny = resolver.skeleton(from: schema)
                    }
                }

                var argv: [String] = ["ascctl", "openapi", "op", "run", "--method", plan.method, "--path", plan.pathTemplate]
                for p in plan.requiredPathParams {
                    argv.append("--path-param")
                    argv.append("\(p)=VALUE")
                }
                for q in plan.requiredQueryParams {
                    argv.append("--query")
                    argv.append("\(q)=VALUE")
                }
                if plan.requiresConfirm {
                    argv.append("--confirm")
                }
                if !plan.addJSONHeaders {
                    argv.append("--no-json-headers")
                    if let accept = plan.accept, !accept.isEmpty {
                        argv.append("--accept")
                        argv.append(accept)
                    }
                }
                if let ct = plan.contentType, !ct.isEmpty, (ct != "application/json" || !plan.addJSONHeaders) {
                    argv.append("--content-type")
                    argv.append(ct)
                }
                if let bodyAny {
                    let bodyString = try serializeJSON(bodyAny)
                    argv.append("--body-json")
                    argv.append(bodyString)
                }

                try Output.envelopeOK(
                    command: command,
                    data: [
                        "specPath": specURL.path,
                        "operationId": plan.operationId,
                        "argv": argv,
                        "body": bodyAny as Any,
                        "hints": [
                            "pathParams": plan.requiredPathParams,
                            "requiredQuery": plan.requiredQueryParams,
                            "requiredHeaders": plan.requiredHeaderParams,
                            "contentType": plan.contentType as Any,
                            "accept": plan.accept as Any,
                            "dangerous": plan.requiresConfirm,
                        ],
                    ],
                    pretty: global.pretty
                )
            }

            private func serializeJSON(_ any: Any) throws -> String {
                guard JSONSerialization.isValidJSONObject(any) else {
                    throw CLIError.invalidArgument("Template body skeleton is not a valid JSON object.")
                }
                let data = try JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])
                return String(data: data, encoding: .utf8) ?? "{}"
            }
        }

        struct Run: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                commandName: "run",
                abstract: "Execute an OpenAPI operation using the App Store Connect API."
            )

            @OptionGroup
            var selector: OperationSelector

            @OptionGroup
            var spec: SpecOptions

            @Option(name: .customLong("path-param"), parsing: .upToNextOption, help: "Path parameter(s) in the form key=value. Repeatable.")
            var pathParam: [String] = []

            @Option(name: .customLong("query"), parsing: .upToNextOption, help: "Query parameter(s) in the form key=value. Repeatable.")
            var query: [String] = []

            @Option(name: .customLong("header"), parsing: .upToNextOption, help: "Header(s) in the form key=value. Repeatable.")
            var header: [String] = []

            @Option(name: .customLong("body-json"), help: "Request body as JSON.")
            var bodyJson: String?

            @Option(name: .customLong("body-file"), help: "Path to a request body file.")
            var bodyFile: String?

            @Option(help: "Override the Accept header.")
            var accept: String?

            @Option(name: .customLong("content-type"), help: "Override the Content-Type header.")
            var contentType: String?

            @Flag(name: .customLong("no-json-headers"), help: "Do not auto-add JSON Accept/Content-Type headers.")
            var noJSONHeaders: Bool = false

            @Option(help: "Write response bytes to a file instead of stdout JSON.")
            var out: String?

            @Flag(name: .customLong("dry-run"), help: "Resolve the request and exit without calling the API.")
            var dryRun: Bool = false

            @Flag(help: "Confirm the operation.")
            var confirm: Bool = false

            @Flag(help: "Paginate GET list responses using JSON:API links.next.")
            var paginate: Bool = false

            @Option(help: "Max items to return when paginating. Use 0 for unlimited. Default: 200 (with --paginate).")
            var limit: Int?

            @Option(help: "JSON pointer selection (e.g. /data/0/id). Returns only the selected fragment.")
            var select: String?

            @Option(help: "Record resolved request + response metadata and body bytes to a directory.")
            var record: String?

            @Option(help: "Replay a previously recorded request/response directory (no network).")
            var replay: String?

            @OptionGroup
            var global: GlobalOptions

            func run() async throws {
                let command = "openapi.op.run"

                if record != nil, replay != nil {
                    throw CLIError.invalidArgument("Provide only one of --record or --replay.")
                }

                let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)
                guard let op = OpenAPICommand.Op.resolveOperation(selector: selector, spec: parsed) else {
                    throw CLIError.invalidArgument("Operation not found. Provide --id or (--method and --path).")
                }

                let plan = parsed.plan(for: op)

                // Confirm guard for mutating operations (preflight; do not require creds/network).
                if plan.requiresConfirm, !dryRun, replay == nil, !confirm {
                    throw CLIError.confirmRequired("Refusing to perform \(plan.method) without --confirm.")
                }

                // Parse inputs (preflight).
                let pathParams = try KeyValueInput.parseDictionary(pairs: pathParam)
                let queryItems = try QueryInput.parse(pairs: query)
                var headers = try KeyValueInput.parseDictionary(pairs: header)
                // The ASC client adds Authorization itself; never echo/record it via the agent contract.
                for k in headers.keys where k.lowercased() == "authorization" {
                    headers.removeValue(forKey: k)
                }
                let body = try JSONInput.data(
                    fromJson: bodyJson,
                    fromFile: bodyFile,
                    jsonFlag: "--body-json",
                    fileFlag: "--body-file"
                )

                // Validate required query/body before building the URL.
                try validatePreflight(plan: plan, op: op, pathParams: pathParams, queryItems: queryItems, headers: headers, body: body)

                if let replayDir = replay {
                    let replayURL = URL(fileURLWithPath: PathUtils.expandTilde(replayDir))
                    let recorded = try RecordIO.read(dir: replayURL)
                    try emitSuccess(
                        command: command,
                        specPath: specURL.path,
                        plan: plan,
                        request: recorded.request,
                        response: recorded.response,
                        jsonBody: try parseJSONBodyOrNull(recorded.response.body),
                        paginateInfo: recorded.paginate,
                        select: select,
                        out: out,
                        pretty: global.pretty
                    )
                    return
                }

                // Resolve baseURL (no auth needed for dry-run).
                let (settings, _, _) = try SettingsResolver.resolve(global: global, requireAuth: !dryRun)
                let apiRoot = settings.baseURL.deletingLastPathComponent()

                let resolved = try OpenAPIRunner.resolveRequest(
                    plan: plan,
                    apiRoot: apiRoot,
                    pathParams: pathParams,
                    queryItems: queryItems,
                    extraHeaders: headers,
                    body: body,
                    acceptOverride: accept,
                    contentTypeOverride: contentType,
                    noJSONHeaders: noJSONHeaders
                )

                if dryRun {
                    try Output.envelopeOK(
                        command: command,
                        data: [
                            "specPath": specURL.path,
                            "operationId": plan.operationId,
                            "dryRun": true,
                            "requiresConfirm": plan.requiresConfirm,
                            "request": [
                                "method": resolved.method,
                                "url": resolved.url.absoluteString,
                                "headers": resolved.headers,
                                "bodyBytes": resolved.bodyBytes,
                                "addJSONHeaders": resolved.addJSONHeaders,
                            ],
                        ],
                        pretty: global.pretty
                    )
                    return
                }

                // Network execution (requires auth).
                let client = try settings.makeClient()
                let performer = ASCClientPerformer(client: client)

                let recordDirURL = record.map { URL(fileURLWithPath: PathUtils.expandTilde($0)) }

                if paginate {
                    let effectiveLimit: Int? = {
                        if let limit {
                            if limit < 0 { return -1 }
                            if limit == 0 { return nil }
                            return limit
                        }
                        return 200
                    }()
                    if effectiveLimit == -1 {
                        throw CLIError.invalidArgument("--limit must be >= 0.")
                    }

                    let result = try await OpenAPIRunner.executePaginatedGET(
                        plan: plan,
                        apiRoot: apiRoot,
                        pathParams: pathParams,
                        queryItems: queryItems,
                        extraHeaders: headers,
                        acceptOverride: accept,
                        noJSONHeaders: noJSONHeaders,
                        performer: performer,
                        limit: effectiveLimit
                    )

                    let bodyData = try JSONSerialization.data(withJSONObject: result.json, options: [])
                    let response = RecordedResponse(
                        statusCode: result.statusCode,
                        headers: result.headers,
                        body: bodyData
                    )
                    let request = RecordedRequest(
                        method: result.firstRequest.method,
                        url: result.firstRequest.url.absoluteString,
                        headers: result.firstRequest.headers,
                        body: body
                    )

                    if let recordDirURL {
                        try RecordIO.write(
                            dir: recordDirURL,
                            operationId: plan.operationId,
                            request: request,
                            response: response,
                            paginate: ["enabled": true, "limit": effectiveLimit ?? NSNull(), "items": result.items, "pages": result.pages]
                        )
                    }

                    try emitSuccess(
                        command: command,
                        specPath: specURL.path,
                        plan: plan,
                        request: request,
                        response: response,
                        jsonBody: result.json,
                        paginateInfo: ["enabled": true, "limit": effectiveLimit ?? NSNull(), "items": result.items, "pages": result.pages],
                        select: select,
                        out: out,
                        pretty: global.pretty
                    )
                    return
                }

                let raw = try await OpenAPIRunner.execute(
                    plan: plan,
                    apiRoot: apiRoot,
                    pathParams: pathParams,
                    queryItems: queryItems,
                    extraHeaders: headers,
                    body: body,
                    acceptOverride: accept,
                    contentTypeOverride: contentType,
                    noJSONHeaders: noJSONHeaders,
                    performer: performer
                )

                let response = RecordedResponse(statusCode: raw.statusCode, headers: raw.headers, body: raw.body)
                let request = RecordedRequest(method: resolved.method, url: resolved.url.absoluteString, headers: resolved.headers, body: body)

                if let recordDirURL {
                    try RecordIO.write(dir: recordDirURL, operationId: plan.operationId, request: request, response: response, paginate: nil)
                }

                // Convert non-2xx into a structured error.
                guard (200..<300).contains(raw.statusCode) else {
                    throw CLIError.apiError(
                        status: raw.statusCode,
                        message: "API request failed with status \(raw.statusCode).",
                        details: RecordIO.apiErrorDetails(from: raw.body)
                    )
                }

                try emitSuccess(
                    command: command,
                    specPath: specURL.path,
                    plan: plan,
                    request: request,
                    response: response,
                    jsonBody: try parseJSONBodyOrNull(raw.body),
                    paginateInfo: nil,
                    select: select,
                    out: out,
                    pretty: global.pretty
                )
            }

            private func validatePreflight(
                plan: OpenAPICallPlan,
                op: OpenAPIOperation,
                pathParams: [String: String],
                queryItems: [URLQueryItem],
                headers: [String: String],
                body: Data?
            ) throws {
                let providedQuery = Set(queryItems.map(\.name))
                let missingQuery = plan.requiredQueryParams.filter { !providedQuery.contains($0) }

                var details: [String: Any] = [:]
                if !missingQuery.isEmpty {
                    details["missingQuery"] = missingQuery
                }
                if plan.requestBodyRequired, body == nil {
                    details["missingBody"] = true
                }
                if !details.isEmpty {
                    throw CLIError.validationFailed(message: "Validation failed.", details: details)
                }

                // Lightweight type/enum checks where schema is simple.
                var invalid: [[String: Any]] = []
                let queryMap = Dictionary(grouping: queryItems, by: { $0.name })
                for p in op.parameters {
                    guard let name = p["name"] as? String,
                          let place = p["in"] as? String,
                          let schema = p["schema"] as? [String: Any]
                    else { continue }

                    let values: [String] = {
                        switch place {
                        case "path":
                            return pathParams[name].map { [$0] } ?? []
                        case "query":
                            return queryMap[name]?.compactMap { $0.value } ?? []
                        case "header":
                            return headers[name].map { [$0] } ?? []
                        default:
                            return []
                        }
                    }()
                    if values.isEmpty { continue }

                    for value in values {
                        if let type = schema["type"] as? String {
                            if type == "integer", Int(value) == nil {
                                invalid.append(["name": name, "in": place, "type": type, "value": value])
                                continue
                            }
                            if type == "number", Double(value) == nil {
                                invalid.append(["name": name, "in": place, "type": type, "value": value])
                                continue
                            }
                            if type == "boolean" {
                                let v = value.lowercased()
                                if v != "true" && v != "false" {
                                    invalid.append(["name": name, "in": place, "type": type, "value": value])
                                    continue
                                }
                            }
                        }
                        if let values = schema["enum"] as? [Any], !values.isEmpty {
                            let allowed = Set(values.map { String(describing: $0) })
                            if !allowed.contains(value) {
                                invalid.append(["name": name, "in": place, "enum": Array(allowed).sorted(), "value": value])
                            }
                        }
                    }
                }

                if !invalid.isEmpty {
                    throw CLIError.validationFailed(message: "Parameter validation failed.", details: ["invalid": invalid])
                }
            }

            private func parseJSONBodyOrNull(_ data: Data) throws -> Any {
                if data.isEmpty { return NSNull() }
                if let any = try? JSONSerialization.jsonObject(with: data, options: []) {
                    return any
                }
                return NSNull()
            }

            private func emitSuccess(
                command: String,
                specPath: String,
                plan: OpenAPICallPlan,
                request: RecordedRequest,
                response: RecordedResponse,
                jsonBody: Any,
                paginateInfo: [String: Any]?,
                select: String?,
                out: String?,
                pretty: Bool
            ) throws {
                // For non-JSON payloads, require --out.
                let contentType = RecordIO.headerValue(response.headers, "Content-Type")

                if let out, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let outURL = URL(fileURLWithPath: PathUtils.expandTilde(out))
                    try PathUtils.ensureParentDir(outURL)
                    try response.body.write(to: outURL, options: [.atomic])
                    try Output.envelopeOK(
                        command: command,
                        data: [
                            "specPath": specPath,
                            "operationId": plan.operationId,
                            "paginate": paginateInfo as Any,
                            "request": request.asJSON(),
                            "response": [
                                "status": response.statusCode,
                                "contentType": contentType as Any,
                                "bytes": response.body.count,
                                "out": outURL.path,
                            ],
                        ],
                        pretty: pretty
                    )
                    return
                }

                if jsonBody is NSNull, !response.body.isEmpty {
                    throw CLIError.nonJSONRequiresOut(contentType: contentType)
                }

                if let select, !select.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let selected = try JSONPointer.select(jsonBody, pointer: select)
                    try Output.envelopeOK(
                        command: command,
                        data: [
                            "specPath": specPath,
                            "operationId": plan.operationId,
                            "paginate": paginateInfo as Any,
                            "request": request.asJSON(),
                            "response": [
                                "status": response.statusCode,
                                "contentType": contentType as Any,
                                "bytes": response.body.count,
                            ],
                            "result": selected,
                        ],
                        pretty: pretty
                    )
                    return
                }

                try Output.envelopeOK(
                    command: command,
                    data: [
                        "specPath": specPath,
                        "operationId": plan.operationId,
                        "paginate": paginateInfo as Any,
                        "request": request.asJSON(),
                        "response": [
                            "status": response.statusCode,
                            "contentType": contentType as Any,
                            "bytes": response.body.count,
                            "body": jsonBody,
                        ],
                    ],
                    pretty: pretty
                )
            }
        }
    }

    // MARK: - openapi schemas

    struct Schemas: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "schemas",
            abstract: "Navigate OpenAPI component schemas.",
            subcommands: [
                List.self,
                Show.self,
            ]
        )

        struct List: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List schema names."
            )

            @OptionGroup
            var spec: SpecOptions

            @Option(help: "Filter schema names by substring (case-insensitive).")
            var filter: String?

            @Option(help: "Max items to return.")
            var limit: Int = 200

            @OptionGroup
            var global: GlobalOptions

            func run() async throws {
                let command = "openapi.schemas.list"
                let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

                let schemas = ((parsed.raw["components"] as? [String: Any])?["schemas"] as? [String: Any]) ?? [:]
                var names = Array(schemas.keys).sorted()

                if let filter, !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let needle = filter.lowercased()
                    names = names.filter { $0.lowercased().contains(needle) }
                }
                names = Array(names.prefix(max(0, limit)))

                try Output.envelopeOK(
                    command: command,
                    data: [
                        "specPath": specURL.path,
                        "count": names.count,
                        "schemas": names,
                    ],
                    pretty: global.pretty
                )
            }
        }

        struct Show: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                commandName: "show",
                abstract: "Show a schema JSON object."
            )

            @Option(help: "Schema name (from `openapi schemas list`).")
            var name: String

            @OptionGroup
            var spec: SpecOptions

            @OptionGroup
            var global: GlobalOptions

            func run() async throws {
                let command = "openapi.schemas.show"
                let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

                let schemas = ((parsed.raw["components"] as? [String: Any])?["schemas"] as? [String: Any]) ?? [:]
                guard let schemaAny = schemas[name] else {
                    throw CLIError.invalidArgument("Schema not found: \(name)")
                }

                try Output.envelopeOK(
                    command: command,
                    data: [
                        "specPath": specURL.path,
                        "name": name,
                        "schema": schemaAny,
                    ],
                    pretty: global.pretty
                )
            }
        }
    }
}

// MARK: - Record IO

private struct RecordedRequest {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data?

    func asJSON() -> [String: Any] {
        [
            "method": method,
            "url": url,
            "headers": headers,
            "bodyBytes": body?.count ?? 0,
        ]
    }
}

private struct RecordedResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

private enum RecordIO {
    static func write(
        dir: URL,
        operationId: String,
        request: RecordedRequest,
        response: RecordedResponse,
        paginate: [String: Any]?
    ) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        let paginateValue: Any = paginate ?? NSNull()
        let contentTypeValue: Any = headerValue(response.headers, "Content-Type") ?? NSNull()

        let record: [String: Any] = [
            "recordedAt": ISO8601DateFormatter().string(from: Date()),
            "operationId": operationId,
            "request": request.asJSON(),
            "response": [
                "status": response.statusCode,
                "headers": response.headers,
                "bytes": response.body.count,
                "contentType": contentTypeValue,
            ],
            "paginate": paginateValue,
        ]

        let recordURL = dir.appendingPathComponent("record.json")
        let recordData = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try recordData.write(to: recordURL, options: [.atomic])

        let responseURL = dir.appendingPathComponent("response.body")
        try response.body.write(to: responseURL, options: [.atomic])

        if let body = request.body {
            let requestURL = dir.appendingPathComponent("request.body")
            try body.write(to: requestURL, options: [.atomic])
        }
    }

    static func read(dir: URL) throws -> (request: RecordedRequest, response: RecordedResponse, paginate: [String: Any]?) {
        let recordURL = dir.appendingPathComponent("record.json")
        let responseURL = dir.appendingPathComponent("response.body")
        let requestBodyURL = dir.appendingPathComponent("request.body")

        let recordData = try Data(contentsOf: recordURL)
        let recordAny = try JSONSerialization.jsonObject(with: recordData, options: [])
        guard let record = recordAny as? [String: Any] else {
            throw CLIError.invalidArgument("Invalid record.json (not an object).")
        }

        guard let req = record["request"] as? [String: Any],
              let method = req["method"] as? String,
              let url = req["url"] as? String
        else {
            throw CLIError.invalidArgument("Invalid record.json (missing request fields).")
        }

        let requestHeaders: [String: String] = {
            guard let raw = req["headers"] as? [String: Any] else { return [:] }
            var out: [String: String] = [:]
            for (k, v) in raw {
                out[k] = v as? String ?? String(describing: v)
            }
            return out
        }()

        guard let resp = record["response"] as? [String: Any],
              let status = resp["status"] as? Int
        else {
            throw CLIError.invalidArgument("Invalid record.json (missing response fields).")
        }

        let responseHeaders: [String: String] = {
            guard let raw = resp["headers"] as? [String: Any] else { return [:] }
            var out: [String: String] = [:]
            for (k, v) in raw {
                out[k] = v as? String ?? String(describing: v)
            }
            return out
        }()

        let responseBody = try Data(contentsOf: responseURL)
        let requestBody: Data? = FileManager.default.fileExists(atPath: requestBodyURL.path) ? (try Data(contentsOf: requestBodyURL)) : nil

        let paginate = record["paginate"] as? [String: Any]
        return (
            request: RecordedRequest(method: method, url: url, headers: requestHeaders, body: requestBody),
            response: RecordedResponse(statusCode: status, headers: responseHeaders, body: responseBody),
            paginate: paginate
        )
    }

    static func headerValue(_ headers: [String: String], _ name: String) -> String? {
        if let v = headers[name] { return v }
        let lower = name.lowercased()
        if let v = headers[lower] { return v }
        for (k, v) in headers where k.lowercased() == lower {
            return v
        }
        return nil
    }

    static func apiErrorDetails(from body: Data) -> [String: Any] {
        if let any = try? JSONSerialization.jsonObject(with: body, options: []),
           JSONSerialization.isValidJSONObject(any)
        {
            return ["body": any]
        }
        return ["body": String(data: body, encoding: .utf8) ?? ""]
    }
}
