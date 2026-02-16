// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AppStoreConnectCLI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ascctl", targets: ["ascctl"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "AppStoreConnectAPI",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .executableTarget(
            name: "ascctl",
            dependencies: [
                "AppStoreConnectAPI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            sources: [
                "AgentContract.swift",
                "AscctlMain.swift",
                "ASCCTLConfig.swift",
                "AuthCommand.swift",
                "CLIError.swift",
                "CommandContext.swift",
                "ConfigCommand.swift",
                "ConfirmGuard.swift",
                "GlobalOptions.swift",
                "JSONInput.swift",
                "KeyValueInput.swift",
                "OpenAPICallPlan.swift",
                "OpenAPICommand.swift",
                "OpenAPIRunner.swift",
                "OpenAPISpec.swift",
                "Output.swift",
                "PathUtils.swift",
                "ProcessRunner.swift",
                "QueryInput.swift",
                "SettingsResolver.swift",
                "SHA256.swift",
                // New agent-first commands/helpers
                "IDsCommand.swift",
                "JSONPointer.swift",
                "OpenAPISchemaResolver.swift",
            ]
        ),
        .testTarget(
            name: "AppStoreConnectAPITests",
            dependencies: [
                "AppStoreConnectAPI",
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "ascctlTests",
            dependencies: [
                "ascctl",
                "AppStoreConnectAPI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            sources: [
                "AgentExitTests.swift",
                "IDsCommandTests.swift",
                "JSONPointerTests.swift",
                "MockURLProtocol.swift",
                "OpenAPISpecAndPlanTests.swift",
                "OpenAPIRunnerValidationTests.swift",
            ]
        )
    ]
)
