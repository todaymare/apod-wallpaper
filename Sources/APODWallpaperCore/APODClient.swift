import Foundation

public protocol APODFetching: Sendable {
    func fetchLatest() async throws -> APOD
    func fetch(date: String) async throws -> APOD
    func fetchRandom(count: Int) async throws -> [APOD]
}

public enum APODClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse
    case invalidRequest
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "NASA returned an invalid response."
        case .invalidRequest:
            return "The NASA request could not be created."
        case let .httpStatus(statusCode):
            return "NASA returned HTTP status \(statusCode)."
        }
    }
}

public final class NASAAPODClient: APODFetching, @unchecked Sendable {
    public static let endpoint = URL(string: "https://api.nasa.gov/planetary/apod")!

    private let apiKey: String
    private let session: URLSession
    private let endpoint: URL

    public init(
        apiKey: String = "DEMO_KEY",
        session: URLSession = .shared,
        endpoint: URL = NASAAPODClient.endpoint
    ) {
        self.apiKey = apiKey
        self.session = session
        self.endpoint = endpoint
    }

    public func fetchLatest() async throws -> APOD {
        try await fetch(parameters: [])
    }

    public func fetch(date: String) async throws -> APOD {
        try await fetch(parameters: [URLQueryItem(name: "date", value: date)])
    }

    public func fetchRandom(count: Int = 20) async throws -> [APOD] {
        guard (1...100).contains(count) else {
            throw APODClientError.invalidRequest
        }
        let data = try await requestData(
            parameters: [URLQueryItem(name: "count", value: String(count))]
        )

        if let APODs = try? JSONDecoder().decode([APOD].self, from: data) {
            return APODs
        }
        return [try JSONDecoder().decode(APOD.self, from: data)]
    }

    private func fetch(parameters: [URLQueryItem]) async throws -> APOD {
        let data = try await requestData(parameters: parameters)
        return try JSONDecoder().decode(APOD.self, from: data)
    }

    private func requestData(parameters: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw APODClientError.invalidRequest
        }

        components.queryItems = parameters + [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "thumbs", value: "true")
        ]

        guard let requestURL = components.url else {
            throw APODClientError.invalidRequest
        }

        var request = URLRequest(url: requestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APODClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APODClientError.httpStatus(httpResponse.statusCode)
        }
        return data
    }
}
