import Foundation

public enum APODMediaType: String, Codable, Sendable {
    case image
    case video
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = APODMediaType(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct APOD: Codable, Equatable, Sendable {
    public let date: String
    public let title: String
    public let explanation: String?
    public let mediaType: APODMediaType
    public let url: URL
    public let hdURL: URL?
    public let thumbnailURL: URL?
    public let copyright: String?
    public let serviceVersion: String?

    public init(
        date: String,
        title: String,
        explanation: String? = nil,
        mediaType: APODMediaType,
        url: URL,
        hdURL: URL? = nil,
        thumbnailURL: URL? = nil,
        copyright: String? = nil,
        serviceVersion: String? = nil
    ) {
        self.date = date
        self.title = title
        self.explanation = explanation
        self.mediaType = mediaType
        self.url = url
        self.hdURL = hdURL
        self.thumbnailURL = thumbnailURL
        self.copyright = copyright
        self.serviceVersion = serviceVersion
    }
    public var pageURL: URL {
        let compactDate = date.replacingOccurrences(of: "-", with: "")
        return URL(string: "https://apod.nasa.gov/apod/ap\(compactDate).html")!
    }


    private enum CodingKeys: String, CodingKey {
        case date
        case title
        case explanation
        case mediaType = "media_type"
        case url
        case hdURL = "hdurl"
        case thumbnailURL = "thumbnail_url"
        case copyright
        case serviceVersion = "service_version"
    }
}
