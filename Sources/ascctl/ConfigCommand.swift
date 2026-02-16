import ArgumentParser
import Foundation

struct ConfigCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage ascctl configuration.",
        subcommands: [
            Init.self,
            Show.self,
        ]
    )

    struct Init: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "init",
            abstract: "Create a skeleton config file."
        )

        @Flag(help: "Overwrite existing config file.")
        var force: Bool = false

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "config.init"
            let configURL: URL = {
                if let path = global.config?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    return URL(fileURLWithPath: PathUtils.expandTilde(path))
                }
                return SettingsResolver.defaultConfigURL()
            }()

            let fm = FileManager.default
            let dir = configURL.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

            if fm.fileExists(atPath: configURL.path), !force {
                Output.warn("Config already exists. Use --force to overwrite.")
                try Output.envelopeOK(
                    command: command,
                    data: [
                        "configPath": configURL.path,
                        "exists": true,
                        "written": false,
                    ],
                    pretty: global.pretty
                )
                return
            }

            let profile = ASCCTLProfile(
                issuerId: "YOUR_ISSUER_ID",
                keyId: "YOUR_KEY_ID",
                privateKeyPath: "/abs/path/AuthKey_<KEY_ID>.p8",
                baseURL: "https://api.appstoreconnect.apple.com/v1/",
                timeoutSeconds: 60,
                retry: ASCCTLRetry(count: 3, baseDelaySeconds: 1.0)
            )
            let file = ASCCTLConfigFile(
                defaultProfile: "default",
                profiles: ["default": profile]
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: configURL, options: [.atomic])

            try Output.envelopeOK(
                command: command,
                data: [
                    "configPath": configURL.path,
                    "exists": true,
                    "written": true,
                ],
                pretty: global.pretty
            )
        }
    }

    struct Show: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show effective configuration (redacted)."
        )

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "config.show"
            let (settings, configURL, configFile) = try SettingsResolver.resolve(global: global, requireAuth: false)
            let exists = FileManager.default.fileExists(atPath: configURL.path)

            var json = settings.redactedJSON()
            json["configPath"] = configURL.path
            json["configExists"] = exists
            json["configHasProfile"] = configFile?.profiles[settings.profileName] != nil
            try Output.envelopeOK(command: command, data: json, pretty: global.pretty)
        }
    }
}
