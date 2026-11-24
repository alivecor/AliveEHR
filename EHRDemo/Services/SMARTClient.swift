import Foundation

struct SmartConfiguration: Decodable, Sendable {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let codeChallengeMethodsSupported: [String]?
    let scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case scopesSupported = "scopes_supported"
    }
}

struct SMARTCredentials: Codable, Sendable {
    let environment: FHIRSandboxEnvironment
    let clientID: String
    let tokenEndpoint: URL
    let accessToken: String
    let refreshToken: String?
    let patientID: String
    let expiration: Date
    let scopes: String
}

struct SMARTTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let patient: String?
    let expiresIn: TimeInterval
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case patient
        case expiresIn = "expires_in"
        case scope
    }

    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try fields.decode(String.self, forKey: .accessToken)
        refreshToken = try fields.decodeIfPresent(String.self, forKey: .refreshToken)
        tokenType = try fields.decode(String.self, forKey: .tokenType)
        patient = try fields.decodeIfPresent(String.self, forKey: .patient)
        scope = try fields.decodeIfPresent(String.self, forKey: .scope)
        if let seconds = try? fields.decode(TimeInterval.self, forKey: .expiresIn) {
            expiresIn = seconds
        } else {
            expiresIn = TimeInterval(try fields.decode(String.self, forKey: .expiresIn)) ?? 0
        }
    }
}

struct HTTPMeasurement: Sendable {
    let status: Int
    let milliseconds: Int

    var label: String {
        switch status {
        case 200: "200 OK"
        case 201: "201 Created"
        default: "\(status) " + HTTPURLResponse.localizedString(forStatusCode: status)
        }
    }
}

enum SMARTError: LocalizedError {
    case missingClientID, insecureEndpoint, discovery, unsupportedPKCE, randomFailure
    case noWindow, browserStart, invalidCallback, portalDenied, invalidToken, missingPatient
    case signedOut, expired, busy, writeScope, invalidBloodPressure, invalidPage
    case http(HTTPMeasurement), transport, invalidResponse, uncertainWrite

    var errorDescription: String? {
        switch self {
        case .missingClientID: "Enter the client ID registered with this sandbox."
        case .insecureEndpoint: "The sandbox returned an invalid HTTPS endpoint."
        case .discovery: "SMART discovery failed. Check whether the sandbox is available."
        case .unsupportedPKCE: "The sandbox does not advertise support for S256 PKCE."
        case .randomFailure: "The app could not securely start authorization."
        case .noWindow: "Open Connections in an active app window and try again."
        case .browserStart: "The EHR portal could not open."
        case .invalidCallback: "The portal returned an invalid authorization callback."
        case .portalDenied: "The portal declined authorization. Check the client registration, callback URL, and scopes."
        case .invalidToken: "The sandbox returned an invalid access token or expiration."
        case .missingPatient: "The sandbox did not return a valid patient context."
        case .signedOut: "Sign in on the Connections tab."
        case .expired: "This session has expired. Disconnect and sign in again."
        case .busy: "Wait for the current request to finish."
        case .writeScope: "The sandbox session needs permission to create Observations. Reconnect with Enable sample vital writes turned on."
        case .invalidBloodPressure: "Enter positive whole numbers with systolic greater than diastolic."
        case .invalidPage: "The sandbox returned an unsafe or repeated FHIR page link."
        case .http(let measurement): "The sandbox returned HTTP \(measurement.status)."
        case .transport: "The sandbox could not be reached. Check your connection and try again."
        case .invalidResponse: "The sandbox returned an unexpected response."
        case .uncertainWrite: "The sandbox did not confirm the write. Refresh the vitals before submitting again."
        }
    }
}

final class SMARTClient: NSObject, URLSessionTaskDelegate, Sendable {
    private let session: URLSession

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration)
        super.init()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // OAuth endpoints come from discovery. Never forward credentials to a redirect.
        completionHandler(nil)
    }

    func send(_ request: URLRequest) async throws -> (data: Data, measurement: HTTPMeasurement) {
        guard Self.isHTTPS(request.url) else { throw SMARTError.insecureEndpoint }
        let start = ContinuousClock.now
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request, delegate: self)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SMARTError.transport
        }
        let duration = (ContinuousClock.now - start).components
        let milliseconds = Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
        guard let http = result.1 as? HTTPURLResponse else { throw SMARTError.invalidResponse }
        let measurement = HTTPMeasurement(status: http.statusCode, milliseconds: milliseconds)
        guard (200..<300).contains(http.statusCode) else { throw SMARTError.http(measurement) }
        return (result.0, measurement)
    }

    func token(at endpoint: URL, fields: [URLQueryItem]) async throws -> SMARTTokenResponse {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let form = fields.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
            return name + "=" + value
        }.joined(separator: "&")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(form.utf8)
        let response = try await send(request)
        do {
            return try JSONDecoder().decode(SMARTTokenResponse.self, from: response.data)
        } catch {
            throw SMARTError.invalidToken
        }
    }

    static func fhirRequest(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        return request
    }

    static func isHTTPS(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil &&
            url.password == nil && url.fragment == nil
    }

    static func isFHIRPage(_ url: URL, within base: URL) -> Bool {
        isHTTPS(url) && url.host?.lowercased() == base.host?.lowercased() &&
            (url.port ?? 443) == (base.port ?? 443) &&
            url.standardized.path.hasPrefix(base.standardized.path + "/")
    }
}
