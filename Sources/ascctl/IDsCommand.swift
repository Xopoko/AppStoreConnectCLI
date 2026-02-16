import AppStoreConnectAPI
import ArgumentParser
import Foundation

struct IDsCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ids",
        abstract: "Fast ID lookups (agent-friendly sugar).",
        subcommands: [
            App.self,
            BundleID.self,
            Version.self,
            Build.self,
            BetaGroup.self,
            Tester.self,
        ]
    )

    // MARK: - ids app

    struct App: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "app",
            abstract: "Resolve an App ID by bundle ID."
        )

        @Option(name: .customLong("bundle-id"), help: "Bundle ID (e.g. com.example.app).")
        var bundleId: String

        @OptionGroup
        var spec: OpenAPICommand.SpecOptions

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "ids.app"
            let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

            _ = specURL // reserved for future meta output if needed
            let id = try await IDsLookup.appID(bundleId: bundleId, spec: parsed, global: global)

            try Output.envelopeOK(command: command, data: ["id": id], pretty: global.pretty)
        }
    }

    // MARK: - ids bundle-id

    struct BundleID: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "bundle-id",
            abstract: "Resolve a Bundle ID resource ID by its identifier."
        )

        @Option(name: .customLong("identifier"), help: "Bundle ID identifier (e.g. com.example.app).")
        var identifier: String

        @OptionGroup
        var spec: OpenAPICommand.SpecOptions

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "ids.bundle-id"
            let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

            _ = specURL // reserved for future meta output if needed
            let id = try await IDsLookup.bundleID(identifier: identifier, spec: parsed, global: global)

            try Output.envelopeOK(command: command, data: ["id": id], pretty: global.pretty)
        }
    }

    // MARK: - ids version

    struct Version: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "version",
            abstract: "Resolve an App Store Version ID by app id, platform, and version string."
        )

        enum Platform: String, ExpressibleByArgument, CaseIterable {
            case ios = "IOS"
            case macOS = "MAC_OS"
            case tvOS = "TV_OS"
            case visionOS = "VISION_OS"
        }

        @Option(name: .customLong("app-id"), help: "App resource ID.")
        var appId: String

        @Option(help: "Platform (IOS, MAC_OS, TV_OS, VISION_OS).")
        var platform: Platform

        @Option(name: .customLong("version"), help: "Version string (e.g. 1.2.3).")
        var versionString: String

        @OptionGroup
        var spec: OpenAPICommand.SpecOptions

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "ids.version"
            let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

            _ = specURL // reserved for future meta output if needed
            let id = try await IDsLookup.versionID(appId: appId, platform: platform.rawValue, versionString: versionString, spec: parsed, global: global)

            try Output.envelopeOK(command: command, data: ["id": id], pretty: global.pretty)
        }
    }

    // MARK: - ids build

    struct Build: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Resolve a Build ID."
        )

        @Option(name: .customLong("app-id"), help: "App resource ID.")
        var appId: String

        @Flag(help: "Return the latest build by uploadedDate (required).")
        var latest: Bool = false

        @OptionGroup
        var spec: OpenAPICommand.SpecOptions

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "ids.build"
            guard latest else {
                throw CLIError.invalidArgument("Only --latest is supported for now (pass --latest).")
            }
            let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

            _ = specURL // reserved for future meta output if needed
            let id = try await IDsLookup.latestBuildID(appId: appId, spec: parsed, global: global)

            try Output.envelopeOK(command: command, data: ["id": id], pretty: global.pretty)
        }
    }

    // MARK: - ids beta-group

    struct BetaGroup: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "beta-group",
            abstract: "Resolve a Beta Group ID by app id and group name."
        )

        @Option(name: .customLong("app-id"), help: "App resource ID.")
        var appId: String

        @Option(help: "Beta group name.")
        var name: String

        @OptionGroup
        var spec: OpenAPICommand.SpecOptions

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "ids.beta-group"
            let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

            _ = specURL // reserved for future meta output if needed
            let id = try await IDsLookup.betaGroupID(appId: appId, name: name, spec: parsed, global: global)

            try Output.envelopeOK(command: command, data: ["id": id], pretty: global.pretty)
        }
    }

    // MARK: - ids tester

    struct Tester: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "tester",
            abstract: "Resolve a Beta Tester ID by email."
        )

        @Option(help: "Tester email address.")
        var email: String

        @OptionGroup
        var spec: OpenAPICommand.SpecOptions

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "ids.tester"
            let (specURL, parsed) = try OpenAPICommand.loadSpec(spec)

            _ = specURL // reserved for future meta output if needed
            let id = try await IDsLookup.testerID(email: email, spec: parsed, global: global)

            try Output.envelopeOK(command: command, data: ["id": id], pretty: global.pretty)
        }
    }
}

// Internal so `ascctlTests` can validate request formation via a mocked URLSession/URLProtocol.
enum IDsLookup {
    static func appID(bundleId: String, spec: OpenAPISpec, global: GlobalOptions) async throws -> String {
        try await CommandContext.withClient(global: global) { settings, client in
            try await appID(bundleId: bundleId, spec: spec, settings: settings, client: client)
        }
    }

    static func appID(bundleId: String, spec: OpenAPISpec, settings: ResolvedSettings, client: ASCClient) async throws -> String {
        try await lookupFirstID(
            spec: spec,
            method: "GET",
            path: "/v1/apps",
            pathParams: [:],
            queryItems: [
                URLQueryItem(name: "filter[bundleId]", value: bundleId),
                URLQueryItem(name: "limit", value: "1"),
            ],
            settings: settings,
            client: client
        )
    }

    static func bundleID(identifier: String, spec: OpenAPISpec, global: GlobalOptions) async throws -> String {
        try await CommandContext.withClient(global: global) { settings, client in
            try await bundleID(identifier: identifier, spec: spec, settings: settings, client: client)
        }
    }

    static func bundleID(identifier: String, spec: OpenAPISpec, settings: ResolvedSettings, client: ASCClient) async throws -> String {
        try await lookupFirstID(
            spec: spec,
            method: "GET",
            path: "/v1/bundleIds",
            pathParams: [:],
            queryItems: [
                URLQueryItem(name: "filter[identifier]", value: identifier),
                URLQueryItem(name: "limit", value: "1"),
            ],
            settings: settings,
            client: client
        )
    }

    static func versionID(appId: String, platform: String, versionString: String, spec: OpenAPISpec, global: GlobalOptions) async throws -> String {
        try await CommandContext.withClient(global: global) { settings, client in
            try await versionID(appId: appId, platform: platform, versionString: versionString, spec: spec, settings: settings, client: client)
        }
    }

    static func versionID(appId: String, platform: String, versionString: String, spec: OpenAPISpec, settings: ResolvedSettings, client: ASCClient) async throws -> String {
        try await lookupFirstID(
            spec: spec,
            method: "GET",
            path: "/v1/apps/{id}/appStoreVersions",
            pathParams: ["id": appId],
            queryItems: [
                URLQueryItem(name: "filter[platform]", value: platform),
                URLQueryItem(name: "filter[versionString]", value: versionString),
                URLQueryItem(name: "limit", value: "1"),
            ],
            settings: settings,
            client: client
        )
    }

    static func latestBuildID(appId: String, spec: OpenAPISpec, global: GlobalOptions) async throws -> String {
        try await CommandContext.withClient(global: global) { settings, client in
            try await latestBuildID(appId: appId, spec: spec, settings: settings, client: client)
        }
    }

    static func latestBuildID(appId: String, spec: OpenAPISpec, settings: ResolvedSettings, client: ASCClient) async throws -> String {
        try await lookupFirstID(
            spec: spec,
            method: "GET",
            path: "/v1/builds",
            pathParams: [:],
            queryItems: [
                URLQueryItem(name: "filter[app]", value: appId),
                URLQueryItem(name: "sort", value: "-uploadedDate"),
                URLQueryItem(name: "limit", value: "1"),
            ],
            settings: settings,
            client: client
        )
    }

    static func betaGroupID(appId: String, name: String, spec: OpenAPISpec, global: GlobalOptions) async throws -> String {
        try await CommandContext.withClient(global: global) { settings, client in
            try await betaGroupID(appId: appId, name: name, spec: spec, settings: settings, client: client)
        }
    }

    static func betaGroupID(appId: String, name: String, spec: OpenAPISpec, settings: ResolvedSettings, client: ASCClient) async throws -> String {
        try await lookupFirstID(
            spec: spec,
            method: "GET",
            path: "/v1/betaGroups",
            pathParams: [:],
            queryItems: [
                URLQueryItem(name: "filter[app]", value: appId),
                URLQueryItem(name: "filter[name]", value: name),
                URLQueryItem(name: "limit", value: "1"),
            ],
            settings: settings,
            client: client
        )
    }

    static func testerID(email: String, spec: OpenAPISpec, global: GlobalOptions) async throws -> String {
        try await CommandContext.withClient(global: global) { settings, client in
            try await testerID(email: email, spec: spec, settings: settings, client: client)
        }
    }

    static func testerID(email: String, spec: OpenAPISpec, settings: ResolvedSettings, client: ASCClient) async throws -> String {
        try await lookupFirstID(
            spec: spec,
            method: "GET",
            path: "/v1/betaTesters",
            pathParams: [:],
            queryItems: [
                URLQueryItem(name: "filter[email]", value: email),
                URLQueryItem(name: "limit", value: "1"),
            ],
            settings: settings,
            client: client
        )
    }

    static func lookupFirstID(
        spec: OpenAPISpec,
        method: String,
        path: String,
        pathParams: [String: String],
        queryItems: [URLQueryItem],
        settings: ResolvedSettings,
        client: ASCClient
    ) async throws -> String {
        guard let op = spec.lookup(method: method, path: path) else {
            throw CLIError.internalError("OpenAPI operation not found in spec: \(method.uppercased()) \(path)")
        }
        let plan = spec.plan(for: op)

        let apiRoot = settings.baseURL.deletingLastPathComponent()
        let performer = ASCClientPerformer(client: client)

        let raw = try await OpenAPIRunner.execute(
            plan: plan,
            apiRoot: apiRoot,
            pathParams: pathParams,
            queryItems: queryItems,
            extraHeaders: [:],
            body: nil,
            acceptOverride: nil,
            contentTypeOverride: nil,
            noJSONHeaders: false,
            performer: performer
        )

        guard (200..<300).contains(raw.statusCode) else {
            throw CLIError.apiError(
                status: raw.statusCode,
                message: "API request failed with status \(raw.statusCode).",
                details: apiErrorDetails(from: raw.body)
            )
        }

        let any = try JSONSerialization.jsonObject(with: raw.body, options: [])
        let selected = try JSONPointer.select(any, pointer: "/data/0/id")
        guard let id = selected as? String, !id.isEmpty else {
            throw CLIError.selectNotFound(pointer: "/data/0/id")
        }
        return id
    }

    private static func apiErrorDetails(from body: Data) -> [String: Any] {
        if let any = try? JSONSerialization.jsonObject(with: body, options: []),
           JSONSerialization.isValidJSONObject(any)
        {
            return ["body": any]
        }
        return ["body": String(data: body, encoding: .utf8) ?? ""]
    }
}
