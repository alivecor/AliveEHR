import Foundation

enum DataProvenance: String, Hashable, Sendable {
    case appleHealth
    case directFHIR

    var label: String {
        switch self {
        case .appleHealth: "via Apple Health"
        case .directFHIR: "via Direct FHIR API"
        }
    }
}

enum ClinicalCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case medications = "Medications"
    case labResults = "Lab Results"
    case conditions = "Conditions"
    case allergies = "Allergies"
    case vitals = "Vitals"
    case immunizations = "Immunizations"

    var id: Self { self }
}

struct ClinicalItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let referenceRange: String?
    let isAbnormal: Bool
    let date: Date
    let sourceName: String
    let category: ClinicalCategory
    let provenance: DataProvenance
    let fhirVersion: String
    let rawJSON: String

    static let unknownDate = Date.distantPast
}
