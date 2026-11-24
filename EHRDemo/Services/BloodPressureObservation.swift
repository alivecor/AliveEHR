import Foundation

enum BloodPressureObservation {
    private struct Coding: Encodable {
        let system: String
        let code: String
        let display: String
    }

    private struct Concept: Encodable {
        let coding: [Coding]

        static func loinc(_ code: String, _ display: String) -> Self {
            Self(coding: [Coding(system: "http://loinc.org", code: code, display: display)])
        }
    }

    private struct Quantity: Encodable {
        let value: Int
        let unit = "mmHg"
        let system = "http://unitsofmeasure.org"
        let code = "mm[Hg]"
    }

    private struct Component: Encodable {
        let code: Concept
        let valueQuantity: Quantity
    }

    private struct Subject: Encodable {
        let reference: String
    }

    private struct Meta: Encodable {
        let profile = ["http://hl7.org/fhir/StructureDefinition/bp"]
    }

    private struct Observation: Encodable {
        let resourceType = "Observation"
        let meta = Meta()
        let status = "final"
        let category = [Concept(coding: [
            Coding(system: "http://terminology.hl7.org/CodeSystem/observation-category", code: "vital-signs", display: "Vital Signs")
        ])]
        let code = Concept.loinc("85354-9", "Blood pressure panel with all children optional")
        let subject: Subject
        let effectiveDateTime: Date
        let component: [Component]
    }

    static func isValid(systolic: Int, diastolic: Int) -> Bool {
        diastolic > 0 && systolic > diastolic
    }

    static func encode(patientID: String, systolic: Int, diastolic: Int) throws -> Data {
        guard isValid(systolic: systolic, diastolic: diastolic) else { throw SMARTError.invalidBloodPressure }
        let observation = Observation(
            subject: Subject(reference: "Patient/\(patientID)"),
            effectiveDateTime: .now,
            component: [
                Component(code: .loinc("8480-6", "Systolic blood pressure"), valueQuantity: Quantity(value: systolic)),
                Component(code: .loinc("8462-4", "Diastolic blood pressure"), valueQuantity: Quantity(value: diastolic))
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(observation)
    }
}
