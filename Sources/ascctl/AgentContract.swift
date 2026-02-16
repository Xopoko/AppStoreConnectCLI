import ArgumentParser
import AppStoreConnectAPI
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

protocol AgentRenderableError: Error {
    var agentErrorCode: String { get }
    var agentMessage: String { get }
    var agentHTTPStatus: Int? { get }
    var agentDetails: [String: Any] { get }
    var agentExitCode: Int32 { get }
}

enum AgentContract {
    private static func terminate(_ code: Int32) -> Never {
        #if canImport(Darwin)
        Darwin.exit(code)
        #else
        Glibc.exit(code)
        #endif
    }

    static func exitHelp(argv: [String] = CommandLine.arguments) -> Never {
        let pretty = prettyFromArgv(argv)
        let command = commandFromArgv(argv)
        let includeHidden = argv.contains("--experimental-dump-help")

        let target = AgentHelp.targetType(for: command)
        let help = Ascctl.helpMessage(for: target, includeHidden: includeHidden, columns: nil)
        writeJSONToStdout(
            ["ok": true, "command": command, "data": ["help": help], "meta": [:]],
            pretty: pretty
        )
        terminate(0)
    }

    static func prettyFromArgv(_ argv: [String]) -> Bool {
        argv.contains("--pretty")
    }

    static func commandFromArgv(_ argv: [String]) -> String {
        // argv[0] is the program name.
        // Build a stable dot-separated command path from non-flag tokens.
        // Example: ["ascctl","openapi","op","run","--method","GET"] -> "openapi.op.run"
        var parts: [String] = []
        for arg in argv.dropFirst() {
            if arg.hasPrefix("-") { break }
            parts.append(arg)
        }
        if parts.isEmpty { return "ascctl" }
        return parts.joined(separator: ".")
    }

    static func writeJSONToStdout(_ object: Any, pretty: Bool) {
        do {
            try Output.printJSON(object, pretty: pretty)
        } catch {
            // Last resort: emit a minimal JSON error.
            let fallback = #"{"ok":false,"command":"ascctl","error":{"code":"internal_error","message":"failed to encode JSON output"}}"# + "\n"
            FileHandle.standardOutput.write(Data(fallback.utf8))
        }
    }

    static func exit(with error: Error, argv: [String] = CommandLine.arguments) -> Never {
        let pretty = prettyFromArgv(argv)
        let command = commandFromArgv(argv)

        // Help / clean exits.
        if let clean = error as? CleanExit {
            let desc = String(describing: clean)
            if desc == "--help" || desc == "--experimental-dump-help" {
                let includeHidden = (desc == "--experimental-dump-help")
                let target = AgentHelp.targetType(for: command)
                let help = Ascctl.helpMessage(for: target, includeHidden: includeHidden, columns: nil)
                writeJSONToStdout(
                    ["ok": true, "command": command, "data": ["help": help], "meta": [:]],
                    pretty: pretty
                )
                terminate(0)
            }

            writeJSONToStdout(
                ["ok": true, "command": command, "data": ["message": desc], "meta": [:]],
                pretty: pretty
            )
            terminate(0)
        }

        // Structured errors.
        if let err = error as? AgentRenderableError {
            writeJSONToStdout(
                [
                    "ok": false,
                    "command": command,
                    "error": [
                        "code": err.agentErrorCode,
                        "message": err.agentMessage,
                        "status": err.agentHTTPStatus as Any,
                        "details": err.agentDetails,
                    ],
                    "meta": [:],
                ],
                pretty: pretty
            )
            terminate(err.agentExitCode)
        }

        if let asc = error as? ASCError {
            let mapped = AgentASCError.map(asc)
            writeJSONToStdout(
                [
                    "ok": false,
                    "command": command,
                    "error": [
                        "code": mapped.code,
                        "message": mapped.message,
                        "status": mapped.status as Any,
                        "details": mapped.details,
                    ],
                    "meta": [:],
                ],
                pretty: pretty
            )
            terminate(mapped.exitCode)
        }

        // ArgumentParser parse/validation errors land here.
        let message: String = {
            if let localized = error as? LocalizedError, let desc = localized.errorDescription {
                return desc
            }
            return String(describing: error)
        }()
        writeJSONToStdout(
            [
                "ok": false,
                "command": command,
                "error": [
                    "code": "usage_error",
                    "message": message,
                    "status": NSNull(),
                    "details": [:],
                ],
                "meta": [:],
            ],
            pretty: pretty
        )
        terminate(2)
    }
}

private enum AgentHelp {
    static func targetType(for command: String) -> ParsableCommand.Type {
        // Keep this map small and explicit: the CLI surface is intentionally tiny.
        switch command {
        case "ascctl":
            return Ascctl.self
        case "config":
            return ConfigCommand.self
        case "config.init":
            return ConfigCommand.Init.self
        case "config.show":
            return ConfigCommand.Show.self
        case "auth":
            return AuthCommand.self
        case "auth.validate":
            return AuthCommand.Validate.self
        case "openapi":
            return OpenAPICommand.self
        case "openapi.spec":
            return OpenAPICommand.Spec.self
        case "openapi.spec.update":
            return OpenAPICommand.Spec.Update.self
        case "openapi.ops":
            return OpenAPICommand.Ops.self
        case "openapi.ops.list":
            return OpenAPICommand.Ops.List.self
        case "openapi.op":
            return OpenAPICommand.Op.self
        case "openapi.op.show":
            return OpenAPICommand.Op.Show.self
        case "openapi.op.run":
            return OpenAPICommand.Op.Run.self
        case "openapi.op.template":
            return OpenAPICommand.Op.Template.self
        case "openapi.schemas":
            return OpenAPICommand.Schemas.self
        case "openapi.schemas.list":
            return OpenAPICommand.Schemas.List.self
        case "openapi.schemas.show":
            return OpenAPICommand.Schemas.Show.self
        case "ids":
            return IDsCommand.self
        case "ids.app":
            return IDsCommand.App.self
        case "ids.bundle-id":
            return IDsCommand.BundleID.self
        case "ids.version":
            return IDsCommand.Version.self
        case "ids.build":
            return IDsCommand.Build.self
        case "ids.beta-group":
            return IDsCommand.BetaGroup.self
        case "ids.tester":
            return IDsCommand.Tester.self
        default:
            return Ascctl.self
        }
    }
}

private enum AgentASCError {
    static func map(_ error: ASCError) -> (code: String, message: String, status: Int?, details: [String: Any], exitCode: Int32) {
        switch error {
        case .missingPrivateKey, .invalidPrivateKey, .cryptoUnavailable, .signingFailed:
            return ("auth_error", error.localizedDescription, nil, [:], 3)
        case .transport:
            return ("network_error", error.localizedDescription, nil, [:], 4)
        case .apiErrors(let statusCode, let errors):
            let details: [String: Any] = [
                "errors": errors.map { e in
                    [
                        "status": e.status as Any,
                        "code": e.code as Any,
                        "title": e.title as Any,
                        "detail": e.detail as Any,
                    ]
                }
            ]
            return ("api_error", error.localizedDescription, statusCode, details, 5)
        case .invalidStatusCode(let code, let body):
            return ("api_error", error.localizedDescription, code, ["body": body], 5)
        case .invalidURL:
            return ("usage_error", error.localizedDescription, nil, [:], 2)
        case .invalidResponse:
            return ("api_error", error.localizedDescription, nil, [:], 5)
        }
    }
}
