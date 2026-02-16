enum ConfirmGuard {
    static func require(_ confirm: Bool, _ message: String) throws {
        guard confirm else {
            throw CLIError.missingRequiredOption(message)
        }
    }
}

