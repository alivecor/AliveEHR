import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import UIKit

@MainActor
@Observable
final class DirectFHIRService: NSObject, ASWebAuthenticationPresentationContextProviding {
    var clientID = FHIRSandboxEnvironment.smartHealthIT.defaultClientID
    var requestWriteAccess = false
    private(set) var environment = FHIRSandboxEnvironment.smartHealthIT
    private(set) var isSigningIn = false
    private(set) var isLoading = false
    private(set) var isPosting = false
    private(set) var records: [ClinicalItem] = []
    private(set) var measurement: HTTPMeasurement?
    private(set) var errorMessage: String?

    private var credentials: SMARTCredentials?
    @ObservationIgnored private let client = SMARTClient()
    @ObservationIgnored private var browserSession: ASWebAuthenticationSession?
    @ObservationIgnored private var anchor: ASPresentationAnchor?
    @ObservationIgnored private var sessionGeneration = UUID()

    private static let callbackScheme = "ehr-demo"
    private static let callbackHost = "oauth-callback"
    private static let redirectURI = callbackScheme + "://" + callbackHost
    private static let contextScopes = "launch/patient openid fhirUser"
    private static let resourceTypes = ["MedicationRequest", "Observation", "Condition", "AllergyIntolerance", "Immunization"]

    var isSignedIn: Bool { credentials != nil }
    var patientID: String? { credentials?.patientID }
    var expiration: Date? { credentials?.expiration }
    var scopes: String? { credentials?.scopes }

    var canPostObservation: Bool {
        guard let scopes else { return false }
        return scopes.split(whereSeparator: \.isWhitespace).contains { scope in
            let parts = scope.split(separator: ".", maxSplits: 1)
            guard parts.count == 2,
                  ["patient/Observation", "patient/*", "user/Observation", "user/*"].contains(parts[0]) else { return false }
            let permissions = parts[1]
            return permissions == "write" || (!permissions.isEmpty &&
                permissions.allSatisfy { "cruds".contains($0) } && permissions.contains("c"))
        }
    }

    func restoreSession() {
        guard credentials == nil, !isSigningIn else { return }
        do {
            if let saved = try KeychainHelper.read(SMARTCredentials.self) {
                credentials = saved
                environment = saved.environment
                clientID = saved.clientID
                requestWriteAccess = canPostObservation
            }
        } catch {
            errorMessage = "The saved EHR session could not be restored. You can sign in again."
        }
    }

    func selectEnvironment(_ selection: FHIRSandboxEnvironment) {
        guard !isSigningIn, !isSignedIn, selection != environment else { return }
        environment = selection
        clientID = selection.defaultClientID
        errorMessage = nil
    }

    func discoverSmartConfiguration(baseURL: URL) async throws -> SmartConfiguration {
        var request = URLRequest(url: baseURL.appending(path: ".well-known/smart-configuration"))
        request.setValue("application/json, application/fhir+json", forHTTPHeaderField: "Accept")
        let configuration: SmartConfiguration
        do {
            let response = try await client.send(request)
            configuration = try JSONDecoder().decode(SmartConfiguration.self, from: response.data)
        } catch is DecodingError {
            throw SMARTError.discovery
        }

        guard SMARTClient.isHTTPS(configuration.authorizationEndpoint), SMARTClient.isHTTPS(configuration.tokenEndpoint) else {
            throw SMARTError.insecureEndpoint
        }
        if let methods = configuration.codeChallengeMethodsSupported, !methods.contains("S256") {
            throw SMARTError.unsupportedPKCE
        }
        return configuration
    }

    func signIn(environment: FHIRSandboxEnvironment) async {
        guard !isSigningIn, !isSignedIn, self.environment == environment else { return }
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            errorMessage = SMARTError.missingClientID.localizedDescription
            return
        }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        let requestWrite = requestWriteAccess && environment.supportsWriteRequest

        do {
            let configuration = try await discoverSmartConfiguration(baseURL: environment.baseURL)
            let verifier = try Self.randomValue()
            let state = try Self.randomValue()
            let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
            let advertisedScopes = configuration.scopesSupported ?? []
            let writeScope = advertisedScopes.contains("patient/Observation.c")
                ? "patient/Observation.c" : "patient/Observation.write"
            let reads = Self.resourceTypes.map { "patient/\($0).read" }
            let useIndividualScopes = environment == .oracle &&
                !advertisedScopes.contains("patient/*.read") && reads.allSatisfy(advertisedScopes.contains)
            let readScope = useIndividualScopes ? reads.joined(separator: " ") : "patient/*.read"
            let scope = Self.contextScopes + " " + readScope + (requestWrite ? " " + writeScope : "")
            // SMART Launcher v2 uses an encoded array to select its patient standalone simulation.
            let launch: String? = if environment == .smartHealthIT {
                Self.base64URL(try JSONSerialization.data(withJSONObject: [
                    3, "", "", "AUTO", 0, 0, 0, "", Self.redirectURI, clientID,
                    "", "", "", "", 0, 2, ""
                ] as [Any], options: [.withoutEscapingSlashes]))
            } else {
                nil
            }
            let authorizationURL = try Self.authorizeURL(
                configuration.authorizationEndpoint, clientID: clientID, audience: environment.baseURL,
                challenge: challenge, state: state, scope: scope, launch: launch
            )
            let callback = try await authenticate(at: authorizationURL)
            let code = try Self.authorizationCode(from: callback, state: state)
            let token = try await client.token(at: configuration.tokenEndpoint, fields: [
                .init(name: "grant_type", value: "authorization_code"),
                .init(name: "code", value: code),
                .init(name: "redirect_uri", value: Self.redirectURI),
                .init(name: "client_id", value: clientID),
                .init(name: "code_verifier", value: verifier)
            ])
            try Task.checkCancellation()
            let saved = try Self.makeCredentials(
                from: token, environment: environment, clientID: clientID,
                endpoint: configuration.tokenEndpoint, scope: scope
            )
            try KeychainHelper.save(saved)
            credentials = saved
            sessionGeneration = UUID()
            self.clientID = clientID
        } catch is CancellationError {
            return
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch let error as SMARTError {
            if case .http = error {
                errorMessage = error.localizedDescription + " Check the sandbox client ID, callback registration, and scopes."
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = "The EHR portal sign-in could not be completed."
        }
    }

    private static func authorizeURL(
        _ endpoint: URL, clientID: String, audience: URL, challenge: String, state: String, scope: String, launch: String?
    ) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SMARTError.insecureEndpoint
        }
        var parameters: [URLQueryItem] = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "aud", value: audience.absoluteString),
            .init(name: "scope", value: scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        if let launch { parameters.append(.init(name: "launch", value: launch)) }
        let names = Set(parameters.map(\.name))
        components.queryItems = (components.queryItems ?? []).filter { !names.contains($0.name) } + parameters
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw SMARTError.insecureEndpoint }
        return url
    }

    private func authenticate(at url: URL) async throws -> URL {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive && $0.keyWindow != nil })?.keyWindow
        else { throw SMARTError.noWindow }
        anchor = window
        defer {
            browserSession = nil
            anchor = nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: SMARTError.invalidCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            browserSession = session
            if !session.start() { continuation.resume(throwing: SMARTError.browserStart) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }

    private static func authorizationCode(from callback: URL, state: String) throws -> String {
        guard let url = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              url.scheme?.lowercased() == callbackScheme, url.host?.lowercased() == callbackHost,
              url.path.isEmpty, url.port == nil, url.fragment == nil, url.user == nil, url.password == nil else {
            throw SMARTError.invalidCallback
        }
        let items = url.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, states[0].value == state else { throw SMARTError.invalidCallback }
        if items.contains(where: { $0.name == "error" }) { throw SMARTError.portalDenied }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes[0].value, !code.isEmpty else { throw SMARTError.invalidCallback }
        return code
    }

    private static func randomValue() throws -> String {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw SMARTError.randomFailure }
        return base64URL(bytes)
    }

    private static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func makeCredentials(
        from token: SMARTTokenResponse, environment: FHIRSandboxEnvironment, clientID: String,
        endpoint: URL, scope: String, previous: SMARTCredentials? = nil
    ) throws -> SMARTCredentials {
        guard token.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              !token.accessToken.isEmpty, token.expiresIn.isFinite, token.expiresIn > 0 else {
            throw SMARTError.invalidToken
        }
        guard let patient = token.patient ?? previous?.patientID,
              patient.range(of: #"^[A-Za-z0-9.-]{1,64}$"#, options: .regularExpression) != nil,
              previous == nil || previous?.patientID == patient else { throw SMARTError.missingPatient }
        return SMARTCredentials(
            environment: environment, clientID: clientID, tokenEndpoint: endpoint,
            accessToken: token.accessToken, refreshToken: token.refreshToken ?? previous?.refreshToken,
            patientID: patient, expiration: .now.addingTimeInterval(token.expiresIn), scopes: token.scope ?? scope
        )
    }

    private func currentCredentials(generation: UUID) async throws -> SMARTCredentials {
        guard let current = credentials else { throw SMARTError.signedOut }
        if current.expiration.timeIntervalSinceNow > 30 { return current }
        guard let refresh = current.refreshToken, !refresh.isEmpty else {
            if current.expiration > .now { return current }
            throw SMARTError.expired
        }
        let token: SMARTTokenResponse
        do {
            token = try await client.token(at: current.tokenEndpoint, fields: [
                .init(name: "grant_type", value: "refresh_token"),
                .init(name: "refresh_token", value: refresh),
                .init(name: "client_id", value: current.clientID)
            ])
        } catch SMARTError.http(let response) where [400, 401, 403].contains(response.status) {
            throw SMARTError.expired
        }
        guard sessionGeneration == generation else { throw CancellationError() }
        let updated = try Self.makeCredentials(
            from: token, environment: current.environment, clientID: current.clientID,
            endpoint: current.tokenEndpoint, scope: current.scopes, previous: current
        )
        try KeychainHelper.save(updated)
        credentials = updated
        return updated
    }

    func fetchPatientResources() async {
        guard isSignedIn, !isLoading, !isPosting else { return }
        let generation = sessionGeneration
        isLoading = true
        errorMessage = nil
        measurement = nil
        defer { if sessionGeneration == generation { isLoading = false } }

        do {
            let session = try await currentCredentials(generation: generation)
            let client = self.client
            let batch = await withTaskGroup(of: SearchResult.self) { group in
                for type in Self.resourceTypes {
                    group.addTask { await Self.search(type: type, credentials: session, client: client) }
                }
                var results: [SearchResult] = []
                for await result in group { results.append(result) }
                return results
            }
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            let successes = batch.filter { $0.failure == nil }
            let failedTypes = batch.filter { $0.failure != nil }.map(\.type).sorted()
            measurement = batch.last(where: { $0.failure != nil && $0.measurement != nil })?.measurement
                ?? successes.last?.measurement
            if !successes.isEmpty {
                let merged = successes.flatMap(\.records)
                let unique = Dictionary(merged.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                records = unique.values.sorted { $0.date > $1.date }
            }
            if !failedTypes.isEmpty {
                let list = failedTypes.joined(separator: ", ")
                if successes.isEmpty, let detail = batch.first?.failure {
                    errorMessage = "Could not load Direct EHR records. " + detail
                } else {
                    errorMessage = "Could not fully load " + list + "."
                }
            }
        } catch is CancellationError {
            return
        } catch {
            if sessionGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    private struct SearchResult: Sendable {
        let type: String
        let records: [ClinicalItem]
        let measurement: HTTPMeasurement?
        let failure: String?
    }

    private nonisolated static func search(type: String, credentials: SMARTCredentials, client: SMARTClient) async -> SearchResult {
        let base = credentials.environment.baseURL
        var components = URLComponents(url: base.appending(path: type), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "patient", value: credentials.patientID)]
        var url = components?.url
        var visited: Set<URL> = []
        var records: [ClinicalItem] = []
        var measurement: HTTPMeasurement?
        let context = FHIRParser.Context(provenance: .directFHIR, sourceName: credentials.environment.rawValue, version: "R4")

        do {
            while let page = url {
                try Task.checkCancellation()
                guard SMARTClient.isFHIRPage(page, within: base), visited.insert(page).inserted, visited.count <= 100 else {
                    throw SMARTError.invalidPage
                }
                let response = try await client.send(SMARTClient.fhirRequest(page, token: credentials.accessToken))
                measurement = response.measurement
                guard let bundle = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                      bundle["resourceType"] as? String == "Bundle" else { throw SMARTError.invalidResponse }
                records += try FHIRParser.parse(response.data, context: context)
                let links = bundle["link"] as? [[String: Any]] ?? []
                if let next = links.first(where: { $0["relation"] as? String == "next" }) {
                    guard let value = next["url"] as? String, let nextURL = URL(string: value, relativeTo: page)?.absoluteURL else {
                        throw SMARTError.invalidPage
                    }
                    url = nextURL
                } else {
                    url = nil
                }
            }
            return SearchResult(type: type, records: records, measurement: measurement, failure: nil)
        } catch {
            if case SMARTError.http(let response) = error { measurement = response }
            return SearchResult(type: type, records: [], measurement: measurement, failure: error.localizedDescription)
        }
    }

    func postSampleVitalObservation(systolic: Int, diastolic: Int) async throws {
        guard isSignedIn else { throw SMARTError.signedOut }
        guard !isLoading, !isPosting else { throw SMARTError.busy }
        guard canPostObservation else { throw SMARTError.writeScope }
        let generation = sessionGeneration
        isPosting = true
        defer { if sessionGeneration == generation { isPosting = false } }

        let session = try await currentCredentials(generation: generation)
        guard canPostObservation else { throw SMARTError.writeScope }
        let url = session.environment.baseURL.appending(path: "Observation")
        var request = SMARTClient.fhirRequest(url, token: session.accessToken)
        request.httpMethod = "POST"
        request.setValue("application/fhir+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try BloodPressureObservation.encode(
            patientID: session.patientID, systolic: systolic, diastolic: diastolic
        )
        do {
            let response = try await client.send(request)
            guard sessionGeneration == generation else { throw CancellationError() }
            measurement = response.measurement
        } catch SMARTError.http(let response) {
            if sessionGeneration == generation { measurement = response }
            if response.status >= 500 { throw SMARTError.uncertainWrite }
            throw SMARTError.http(response)
        } catch SMARTError.transport {
            throw SMARTError.uncertainWrite
        } catch is CancellationError {
            throw SMARTError.uncertainWrite
        }
    }

    func disconnect() {
        do {
            try KeychainHelper.delete()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        sessionGeneration = UUID()
        credentials = nil
        records = []
        measurement = nil
        errorMessage = nil
        isLoading = false
        isPosting = false
    }
}
