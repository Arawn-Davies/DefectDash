import Foundation

public struct AsanaUserRef: Codable, Sendable, Equatable {
    public let gid: String
    public let name: String?
    public init(gid: String, name: String?) {
        self.gid = gid
        self.name = name
    }
}

public struct AsanaCustomField: Codable, Sendable {
    public let name: String
    public let displayValue: String?   // display_value
    public init(name: String, displayValue: String?) {
        self.name = name
        self.displayValue = displayValue
    }
}

public struct AsanaDependentRef: Codable, Sendable {
    public let gid: String
    public init(gid: String) { self.gid = gid }
}

public struct AsanaTask: Codable, Sendable, Identifiable {
    public let gid: String
    public var id: String { gid }
    public let name: String
    public let notes: String?
    public let assignee: AsanaUserRef?
    public let dueOn: String?          // due_on "yyyy-MM-dd"
    public let modifiedAt: Date
    public let permalinkUrl: String?
    public let customFields: [AsanaCustomField]
    public let dependents: [AsanaDependentRef]?

    public init(gid: String, name: String, notes: String?, assignee: AsanaUserRef?, dueOn: String?,
                modifiedAt: Date, permalinkUrl: String?, customFields: [AsanaCustomField],
                dependents: [AsanaDependentRef]?) {
        self.gid = gid
        self.name = name
        self.notes = notes
        self.assignee = assignee
        self.dueOn = dueOn
        self.modifiedAt = modifiedAt
        self.permalinkUrl = permalinkUrl
        self.customFields = customFields
        self.dependents = dependents
    }
}

public struct AsanaEnumRef: Codable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct AsanaCustomFieldRef: Codable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct AsanaStory: Codable, Sendable, Identifiable {
    public let gid: String
    public var id: String { gid }
    public let createdAt: Date
    public let createdBy: AsanaUserRef?
    public let type: String            // "comment" | "system"
    public let resourceSubtype: String // "comment_added", "enum_custom_field_changed", ...
    public let text: String?
    public let customField: AsanaCustomFieldRef?
    public let newEnumValue: AsanaEnumRef?
    public let oldEnumValue: AsanaEnumRef?

    public init(gid: String, createdAt: Date, createdBy: AsanaUserRef?, type: String, resourceSubtype: String,
                text: String?, customField: AsanaCustomFieldRef? = nil, newEnumValue: AsanaEnumRef? = nil,
                oldEnumValue: AsanaEnumRef? = nil) {
        self.gid = gid
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.type = type
        self.resourceSubtype = resourceSubtype
        self.text = text
        self.customField = customField
        self.newEnumValue = newEnumValue
        self.oldEnumValue = oldEnumValue
    }
}

public enum AsanaError: Error, Equatable {
    case unauthorized
    case rateLimited(retryAfter: Int)
    case http(Int, String)
    case transport(String)
}

// MARK: - Wire envelopes (internal)

struct AsanaNextPage: Decodable, Sendable {
    let offset: String
}

struct AsanaEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T
    let nextPage: AsanaNextPage?
}

struct AsanaErrorEnvelope: Decodable {
    struct Item: Decodable { let message: String? }
    let errors: [Item]
}

enum AsanaDecoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(string)")
        }
        return decoder
    }
}
