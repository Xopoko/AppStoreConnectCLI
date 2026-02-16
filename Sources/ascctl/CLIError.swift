import Foundation

enum CLIError: Error, LocalizedError, AgentRenderableError {
    case missingRequiredOption(String)
    case invalidArgument(String)

    case confirmRequired(String)
    case validationFailed(message: String, details: [String: Any])
    case selectNotFound(pointer: String)
    case nonJSONRequiresOut(contentType: String?)

    case auth(String)
    case network(String)
    case apiError(status: Int, message: String, details: [String: Any])
    case internalError(String)

    // MARK: AgentRenderableError

    var agentErrorCode: String {
        switch self {
        case .missingRequiredOption:
            return "missing_required_option"
        case .invalidArgument:
            return "invalid_argument"
        case .confirmRequired:
            return "confirm_required"
        case .validationFailed:
            return "validation_failed"
        case .selectNotFound:
            return "select_not_found"
        case .nonJSONRequiresOut:
            return "non_json_requires_out"
        case .auth:
            return "auth_error"
        case .network:
            return "network_error"
        case .apiError:
            return "api_error"
        case .internalError:
            return "internal_error"
        }
    }

    var agentMessage: String {
        switch self {
        case .missingRequiredOption(let message),
             .invalidArgument(let message),
             .confirmRequired(let message),
             .auth(let message),
             .network(let message),
             .internalError(let message):
            return message
        case .validationFailed(let message, _):
            return message
        case .selectNotFound(let pointer):
            return "JSON pointer not found: \(pointer)"
        case .nonJSONRequiresOut(let contentType):
            if let contentType, !contentType.isEmpty {
                return "Response is not JSON (Content-Type: \(contentType)). Use --out to write bytes to a file."
            }
            return "Response is not JSON. Use --out to write bytes to a file."
        case .apiError(_, let message, _):
            return message
        }
    }

    var agentHTTPStatus: Int? {
        switch self {
        case .apiError(let status, _, _):
            return status
        default:
            return nil
        }
    }

    var agentDetails: [String: Any] {
        switch self {
        case .validationFailed(_, let details):
            return details
        case .selectNotFound(let pointer):
            return ["pointer": pointer]
        case .nonJSONRequiresOut(let contentType):
            return ["contentType": contentType as Any]
        case .apiError(_, _, let details):
            return details
        default:
            return [:]
        }
    }

    var agentExitCode: Int32 {
        switch self {
        case .missingRequiredOption,
             .invalidArgument,
             .confirmRequired,
             .validationFailed,
             .selectNotFound,
             .nonJSONRequiresOut:
            return 2
        case .auth:
            return 3
        case .network:
            return 4
        case .apiError:
            return 5
        case .internalError:
            return 6
        }
    }

    // MARK: LocalizedError

    var errorDescription: String? {
        agentMessage
    }
}
