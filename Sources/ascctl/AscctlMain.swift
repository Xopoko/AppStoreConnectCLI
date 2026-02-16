import ArgumentParser
import Foundation

@main
struct Ascctl: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ascctl",
        abstract: "App Store Connect CLI (agent-first).",
        subcommands: [
            ConfigCommand.self,
            AuthCommand.self,
            OpenAPICommand.self,
            IDsCommand.self,
        ]
    )

    static func main() async {
        // Intercept help early so ArgumentParser never prints to stdout/stderr.
        let argv = CommandLine.arguments
        if argv.dropFirst().first == "help" {
            let adjusted = [argv[0]] + Array(argv.dropFirst(2))
            AgentContract.exitHelp(argv: adjusted)
        }
        if argv.contains("--help") || argv.contains("-h") || argv.contains("--experimental-dump-help") {
            AgentContract.exitHelp(argv: argv)
        }

        do {
            var command = try parseAsRoot(nil)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            AgentContract.exit(with: error)
        }
    }
}
