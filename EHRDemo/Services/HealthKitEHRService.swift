import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthKitEHRService {
    private(set) var authorizationRequested = false
    private(set) var isLoading = false
    private(set) var lastSyncDate: Date?
    private(set) var records: [ClinicalItem] = []
    private(set) var errorMessage: String?
    private(set) var isUsingSampleData = false

    @ObservationIgnored private var automaticallyLoadSimulatorSamples = true
    private let healthStore = HKHealthStore()
    private static let clinicalTypes: [(HKClinicalTypeIdentifier, ClinicalCategory)] = [
        (.medicationRecord, .medications), (.labResultRecord, .labResults),
        (.conditionRecord, .conditions), (.allergyRecord, .allergies),
        (.vitalSignRecord, .vitals), (.immunizationRecord, .immunizations)
    ]

    static var supportsSimulatorSamples: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    func requestAuthorization() async {
        guard !isLoading else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Apple Health records are unavailable on this device."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let types = Self.clinicalTypes.compactMap { HKObjectType.clinicalType(forIdentifier: $0.0) }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Set(types))
            authorizationRequested = true
        } catch {
            errorMessage = "Apple Health could not complete the access request."
        }
    }

    func fetchAllClinicalRecords() async {
        guard !isLoading else { return }
        if isUsingSampleData {
            loadDemoSampleData()
            return
        }
        guard authorizationRequested else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let results = await withTaskGroup(of: QueryResult.self) { group in
            for (identifier, category) in Self.clinicalTypes {
                let store = healthStore
                group.addTask { await Self.query(identifier, category: category, store: store) }
            }
            var results: [QueryResult] = []
            for await result in group { results.append(result) }
            return results
        }
        guard !Task.isCancelled else { return }

        let successful = results.compactMap(\.records)
        let failures = results.filter(\.hadFailure).count
        if !successful.isEmpty {
            records = successful.flatMap { $0 }.sorted { $0.date > $1.date }
            lastSyncDate = .now
        }
        if failures > 0 {
            errorMessage = "Apple Health could not fully read \(failures) of \(results.count) record categories."
        } else if automaticallyLoadSimulatorSamples && records.isEmpty && Self.supportsSimulatorSamples {
            loadDemoSampleData()
        }
    }

    func setSimulatorSamples(_ enabled: Bool) async {
        guard Self.supportsSimulatorSamples, !isLoading else { return }
        if enabled {
            loadDemoSampleData()
        } else if isUsingSampleData {
            isUsingSampleData = false
            automaticallyLoadSimulatorSamples = false
            records = []
            lastSyncDate = nil
            errorMessage = nil
            await fetchAllClinicalRecords()
        }
    }

    func loadDemoSampleData() {
        guard Self.supportsSimulatorSamples else { return }
        do {
            let context = FHIRParser.Context(provenance: .appleHealth, sourceName: "Harborview Demo Clinic", version: "R4")
            records = try FHIRParser.parse(Data(SimulatorClinicalSamples.bundle.utf8), context: context).sorted { $0.date > $1.date }
            isUsingSampleData = true
            lastSyncDate = .now
            errorMessage = nil
        } catch {
            errorMessage = "The bundled Simulator samples could not be read."
        }
    }

    private struct QueryResult: Sendable {
        let records: [ClinicalItem]?
        let hadFailure: Bool
    }

    private nonisolated static func query(
        _ identifier: HKClinicalTypeIdentifier, category: ClinicalCategory, store: HKHealthStore
    ) async -> QueryResult {
        guard let type = HKObjectType.clinicalType(forIdentifier: identifier) else {
            return QueryResult(records: nil, hadFailure: true)
        }
        let descriptor = HKSampleQueryDescriptor(predicates: [.clinicalRecord(type: type)], sortDescriptors: [])
        do {
            let samples = try await descriptor.result(for: store)
            var hadFailure = false
            let items = samples.flatMap { sample -> [ClinicalItem] in
                guard let resource = sample.fhirResource else { return [] }
                let version = resource.fhirVersion
                let label: String
                switch version.fhirRelease {
                case .r4: label = "R4"
                case .dstu2: label = "DSTU2"
                default: label = version.stringRepresentation
                }
                let context = FHIRParser.Context(
                    provenance: .appleHealth, sourceName: sample.sourceRevision.source.name,
                    version: label, category: category, fallbackDate: sample.startDate,
                    recordID: sample.uuid.uuidString
                )
                do {
                    return try FHIRParser.parse(resource.data, context: context)
                } catch {
                    hadFailure = true
                    return []
                }
            }
            return QueryResult(records: items, hadFailure: hadFailure)
        } catch {
            return QueryResult(records: nil, hadFailure: true)
        }
    }
}
