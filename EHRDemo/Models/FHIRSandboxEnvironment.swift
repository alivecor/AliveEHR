import Foundation

enum FHIRSandboxEnvironment: String, CaseIterable, Identifiable, Codable, Sendable {
    case smartHealthIT = "SMART Health IT"
    case epic = "Epic Sandbox"
    case oracle = "Oracle Health Sandbox"

    var id: Self { self }

    var baseURL: URL {
        switch self {
        case .smartHealthIT: URL(string: "https://launch.smarthealthit.org/v/r4/fhir")!
        case .epic: URL(string: "https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4")!
        case .oracle: URL(string: "https://fhir-myrecord.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d")!
        }
    }

    var supportsWriteRequest: Bool { self != .oracle }

    var defaultClientID: String {
        self == .smartHealthIT ? "ehr-demo" : ""
    }
}
