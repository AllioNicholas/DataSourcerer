import DataSourcerer
import Foundation

enum APIError : IdiomaticStateError, Codable {
    case unknown(StateErrorMessage)
    case unreachable
    case notConnectedToInternet
    case deserializationFailed(path: String?, debugDescription: String?, responseSize: Int)
    case requestTagsChanged
    case notAuthenticated
    case cacheCouldNotLoad(StateErrorMessage)

    var errorMessage: StateErrorMessage {
        let defaultMessage = StateErrorMessage.message(
            NSLocalizedString("An error occurred while loading.\nPlease try again!", comment: "")
        )

        switch self {
        case let .unknown(message):
            return message
        case .unreachable:
            return defaultMessage
        case .deserializationFailed:
            return .message(NSLocalizedString("""
            An error occurred while deserialization.
            Please contact us!
            """, comment: ""))
        case .requestTagsChanged:
            return .message(NSLocalizedString("No data could be loaded for your user.", comment: ""))
        case .notAuthenticated:
            return .message(NSLocalizedString("Please log in.", comment: ""))
        case .notConnectedToInternet:
            return .message(NSLocalizedString("Please connect to the internet.", comment: ""))
        case let .cacheCouldNotLoad(errorMessage):
            return errorMessage
        }
    }

    init(message: StateErrorMessage) {
        self = .unknown(message)
    }
}

extension APIError {

    enum CodingKeys: String, CodingKey {
        case enumCaseKey = "type"
        case deserializationFailed
        case deserializationFailedPath
        case deserializationFailedDebugDescription
        case deserializationFailedResponseSize
        case unknown
        case unknownDescription
        case requestTagsChanged
        case unreachable
        case notAuthenticated
        case notConnectedToInternet
        case cacheCouldNotLoad
        case cacheCouldNotLoadType
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let enumCaseString = try container.decode(String.self, forKey: .enumCaseKey)
        guard let enumCase = CodingKeys(rawValue: enumCaseString) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unknown enum case '\(enumCaseString)'")
            )
        }

        switch enumCase {
        case .deserializationFailed:
            let path = try? container.decode(String.self, forKey: .deserializationFailedPath)
            let debugDescription = try? container.decode(String.self,
                                                         forKey: .deserializationFailedDebugDescription)
            let responseSize = try? container.decode(Int.self, forKey: .deserializationFailedResponseSize)
            self = .deserializationFailed(path: (path ?? "no path available"),
                                          debugDescription: debugDescription,
                                          responseSize: responseSize ?? 0)
        case .unknown:
            let unknownDecription = try? container.decode(String.self, forKey: .unknownDescription)
            self = .unknown(unknownDecription.map { StateErrorMessage.message($0) } ?? .default)
        case .notAuthenticated:
            self = .notAuthenticated
        case .requestTagsChanged:
            self = .requestTagsChanged
        case .unreachable:
            self = .unreachable
        case .notConnectedToInternet:
            self = .notConnectedToInternet
        case .cacheCouldNotLoad:
            let type = try? container.decode(StateErrorMessage.self, forKey: .cacheCouldNotLoadType)
            self = .cacheCouldNotLoad(type ?? .default)
        default: throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case '\(enumCase)'")
            )
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .deserializationFailed(path, debugDescription, responseSize):
            try container.encode(CodingKeys.deserializationFailed.rawValue, forKey: .enumCaseKey)
            if let path = path {
                try container.encode(path, forKey: .deserializationFailedPath)
            }
            if let debugDescription = debugDescription {
                try container.encode(debugDescription, forKey: .deserializationFailedDebugDescription)
            }
            try container.encode(responseSize, forKey: .deserializationFailedResponseSize)
        case let .unknown(description):
            try container.encode(CodingKeys.unknown.rawValue, forKey: .enumCaseKey)
            try container.encode(description, forKey: .unknownDescription)
        case .requestTagsChanged:
            try container.encode(CodingKeys.requestTagsChanged.rawValue, forKey: .enumCaseKey)
        case .unreachable:
            try container.encode(CodingKeys.unreachable.rawValue, forKey: .enumCaseKey)
        case .notAuthenticated:
            try container.encode(CodingKeys.notAuthenticated.rawValue, forKey: .enumCaseKey)
        case .notConnectedToInternet:
            try container.encode(CodingKeys.notConnectedToInternet.rawValue, forKey: .enumCaseKey)
        case let .cacheCouldNotLoad(type):
            try container.encode(CodingKeys.cacheCouldNotLoad.rawValue, forKey: .enumCaseKey)
            try container.encode(type, forKey: .cacheCouldNotLoadType)
        }
    }

}
