import Foundation

/// Response of `GET /v3/self`. The shape varies by principal type (PAT, service user, ...);
/// only the fields the app needs are decoded.
public struct Principal: Codable, Hashable, Sendable {
    public let principalType: String
    public let orgID: String?
    public let userID: String?
    public let userName: String?
    public let serviceUserName: String?

    enum CodingKeys: String, CodingKey {
        case principalType = "principal_type"
        case orgID = "org_id"
        case userID = "user_id"
        case userName = "user_name"
        case serviceUserName = "service_user_name"
    }

    public init(principalType: String, orgID: String?, userID: String? = nil, userName: String? = nil, serviceUserName: String? = nil) {
        self.principalType = principalType
        self.orgID = orgID
        self.userID = userID
        self.userName = userName
        self.serviceUserName = serviceUserName
    }

    public var displayName: String {
        userName ?? serviceUserName ?? userID ?? principalType
    }
}
