import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> ProcessResult {
        let resolved = try resolveExecutable(executable, environment: environment)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func resolveExecutable(_ name: String, environment: [String: String]?) throws -> String {
        if name.contains("/") {
            return name
        }

        let env = environment ?? ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        for dir in path.split(separator: ":") {
            let candidate = String(dir) + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw CLIError.missingRequiredOption("Executable '\(name)' was not found in PATH.")
    }
}
