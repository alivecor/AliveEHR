import CryptoKit
import Foundation

enum FHIRParser {
    private typealias JSON = [String: Any]

    struct Context: Sendable {
        let provenance: DataProvenance
        let sourceName: String
        let version: String
        var category: ClinicalCategory? = nil
        var fallbackDate = ClinicalItem.unknownDate
        var recordID: String? = nil
    }

    enum ParseError: LocalizedError {
        case malformedResource

        var errorDescription: String? { "The server returned an invalid FHIR resource." }
    }

    static func parse(_ data: Data, context: Context) throws -> [ClinicalItem] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? JSON,
              let type = root["resourceType"] as? String else { throw ParseError.malformedResource }
        if type == "Bundle" {
            return (root["entry"] as? [JSON] ?? []).compactMap { entry in
                let mode = (entry["search"] as? JSON)?["mode"] as? String
                guard mode != "include", mode != "outcome",
                      let resource = entry["resource"] as? JSON else { return nil }
                return map(resource, context: context)
            }
        }
        return map(root, context: context).map { [$0] } ?? []
    }

    static func prettyPrint(_ data: Data) throws -> String {
        try formattedJSON(JSONSerialization.jsonObject(with: data))
    }

    private static func formattedJSON(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    private static func map(_ resource: JSON, context: Context) -> ClinicalItem? {
        guard let type = resource["resourceType"] as? String,
              let rawJSON = try? formattedJSON(resource) else { return nil }
        let category: ClinicalCategory
        let title: String?
        let subtitle: String?
        let eventDate: Date?
        var referenceRange: String?
        var isAbnormal = false

        switch type {
        case "MedicationRequest", "MedicationOrder", "MedicationStatement":
            category = .medications
            title = concept(resource["medicationCodeableConcept"]) ?? reference(resource["medicationReference"], in: resource)
            let instructions = resource["dosageInstruction"] as? [JSON] ?? resource["dosage"] as? [JSON] ?? []
            let doses = instructions.compactMap { instruction in
                let doses = instruction["doseAndRate"] as? [JSON] ?? []
                return instruction["text"] as? String ?? quantity(doses.first?["doseQuantity"])
                    ?? quantity(instruction["doseQuantity"]) ?? concept(instruction["additionalInstructions"])
            }
            subtitle = doses.isEmpty ? status(resource["status"]) : doses.joined(separator: " · ")
            eventDate = date(resource, keys: ["authoredOn", "dateWritten", "effectiveDateTime", "effectivePeriod", "dateAsserted"])
        case "Observation":
            category = context.category ?? observationCategory(resource)
            title = concept(resource["code"])
            let components = resource["component"] as? [JSON] ?? []
            let componentValues = components.compactMap { component -> String? in
                guard let value = observationValue(component) else { return nil }
                return concept(component["code"]).map { "\($0) \(value)" } ?? value
            }
            subtitle = observationValue(resource) ?? (componentValues.isEmpty ? status(resource["status"]) : componentValues.joined(separator: " · "))
            let ranges = referenceRanges(resource) + components.flatMap { component in
                referenceRanges(component).map { range in
                    concept(component["code"]).map { "\($0): \(range)" } ?? range
                }
            }
            referenceRange = ranges.isEmpty ? nil : ranges.joined(separator: " · ")
            isAbnormal = abnormal(resource) || components.contains(where: abnormal)
            eventDate = date(resource, keys: ["effectiveDateTime", "effectiveInstant", "effectivePeriod", "issued"])
        case "Condition":
            category = .conditions
            title = concept(resource["code"])
            subtitle = status(resource["clinicalStatus"]) ?? status(resource["verificationStatus"])
            eventDate = date(resource, keys: ["onsetDateTime", "onsetPeriod", "recordedDate", "dateRecorded", "assertedDate"])
        case "AllergyIntolerance":
            category = .allergies
            title = concept(resource["code"]) ?? concept(resource["substance"])
            let reactions = (resource["reaction"] as? [JSON] ?? []).flatMap { reaction in
                (reaction["manifestation"] as? [JSON] ?? []).compactMap { concept($0) }
            }
            let clinicalStatus = status(resource["clinicalStatus"] ?? resource["status"])
            let details = [clinicalStatus, resource["criticality"] as? String].compactMap { $0 } + reactions
            subtitle = details.isEmpty ? nil : details.joined(separator: " · ")
            eventDate = date(resource, keys: ["onsetDateTime", "onsetPeriod", "recordedDate", "recordedDateTime", "recorded", "lastOccurrence"])
        case "Immunization":
            category = .immunizations
            title = concept(resource["vaccineCode"])
            subtitle = [status(resource["status"]), quantity(resource["doseQuantity"])].compactMap { $0 }.joined(separator: " · ")
            eventDate = date(resource, keys: ["occurrenceDateTime", "occurrenceString", "date", "recorded"])
        default:
            return nil
        }

        let resourceID = resource["id"] as? String
            ?? SHA256.hash(data: Data(rawJSON.utf8)).map { String(format: "%02x", $0) }.joined()
        let id = context.recordID ?? "\(context.sourceName)|\(type)/\(resourceID)"
        let facility = (resource["performer"] as? [JSON] ?? []).compactMap { entry in
            reference(entry["actor"] ?? entry, in: resource, resourceType: "Organization")
        }.first ?? reference(resource["location"], in: resource, resourceType: "Location")

        return ClinicalItem(
            id: "\(context.provenance.rawValue)|\(id)",
            title: title ?? type,
            subtitle: subtitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Not recorded",
            referenceRange: referenceRange,
            isAbnormal: isAbnormal,
            date: eventDate ?? date(resource["meta"] as? JSON ?? [:], keys: ["lastUpdated"]) ?? context.fallbackDate,
            sourceName: context.provenance == .appleHealth ? context.sourceName : facility ?? context.sourceName,
            category: category,
            provenance: context.provenance,
            fhirVersion: context.version,
            rawJSON: rawJSON
        )
    }

    private static func observationCategory(_ resource: JSON) -> ClinicalCategory {
        let concept = resource["category"]
        let categories = concept as? [JSON] ?? (concept as? JSON).map { [$0] } ?? []
        let codes = categories.flatMap { $0["coding"] as? [JSON] ?? [] }.compactMap { $0["code"] as? String }
        return codes.contains("vital-signs") ? .vitals : .labResults
    }

    private static func concept(_ value: Any?) -> String? {
        guard let object = value as? JSON else { return nil }
        let coding = object["coding"] as? [JSON] ?? []
        return object["text"] as? String
            ?? coding.compactMap { $0["display"] as? String }.first
            ?? coding.compactMap { $0["code"] as? String }.first
    }

    private static func reference(_ value: Any?, in resource: JSON, resourceType: String? = nil) -> String? {
        guard let object = value as? JSON else { return nil }
        let target = object["reference"] as? String ?? ""
        let contained = (resource["contained"] as? [JSON] ?? []).first { "#\($0["id"] as? String ?? "")" == target }
        if let resourceType,
           object["type"] as? String != resourceType,
           !target.contains("\(resourceType)/"),
           contained?["resourceType"] as? String != resourceType {
            return nil
        }
        return object["display"] as? String ?? contained?["name"] as? String ?? concept(contained?["code"])
    }

    private static func status(_ value: Any?) -> String? {
        (value as? String ?? concept(value))?.replacingOccurrences(of: "-", with: " ")
    }

    private static func quantity(_ value: Any?) -> String? {
        guard let object = value as? JSON, let number = object["value"] as? NSNumber else { return nil }
        let comparator = object["comparator"] as? String ?? ""
        let unit = object["unit"] as? String ?? object["code"] as? String
        return ([comparator + number.stringValue] + [unit].compactMap { $0 }).joined(separator: " ")
    }

    private static func observationValue(_ object: JSON) -> String? {
        if let value = quantity(object["valueQuantity"]) ?? concept(object["valueCodeableConcept"]) ?? object["valueString"] as? String {
            return value
        }
        if let value = object["valueBoolean"] as? Bool { return value ? "Yes" : "No" }
        if let value = object["valueInteger"] as? Int { return String(value) }
        if let ratio = object["valueRatio"] as? JSON,
           let numerator = quantity(ratio["numerator"]), let denominator = quantity(ratio["denominator"]) {
            return "\(numerator) / \(denominator)"
        }
        if let range = object["valueRange"] as? JSON { return bounds(range) }
        return object["valueDateTime"] as? String ?? object["valueTime"] as? String ?? concept(object["dataAbsentReason"])
    }

    private static func bounds(_ object: JSON) -> String? {
        switch (quantity(object["low"]), quantity(object["high"])) {
        case let (low?, high?): "\(low) – \(high)"
        case let (low?, nil): "≥ \(low)"
        case let (nil, high?): "≤ \(high)"
        case (nil, nil): nil
        }
    }

    private static func referenceRanges(_ object: JSON) -> [String] {
        (object["referenceRange"] as? [JSON] ?? []).compactMap { range in
            range["text"] as? String ?? bounds(range)
        }
    }

    private static func abnormal(_ object: JSON) -> Bool {
        let codes: Set<String> = ["A", "AA", "H", "HH", "HU", "L", "LL", "LU", "<", ">", "ABNORMAL"]
        let interpretation = object["interpretation"]
        let entries = interpretation as? [JSON] ?? (interpretation as? JSON).map { [$0] } ?? []
        return entries.contains { entry in
            if let text = entry["text"] as? String, codes.contains(text.uppercased()) { return true }
            return (entry["coding"] as? [JSON] ?? []).contains { coding in
                guard let code = coding["code"] as? String else { return false }
                return codes.contains(code.uppercased())
            }
        }
    }

    private static func date(_ object: JSON, keys: [String]) -> Date? {
        let formatter = ISO8601DateFormatter()
        for key in keys {
            let period = object[key] as? JSON
            guard let value = object[key] as? String ?? period?["start"] as? String ?? period?["end"] as? String else { continue }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            let fullDate: String
            switch value.count {
            case 4: fullDate = value + "-01-01"
            case 7: fullDate = value + "-01"
            case 10: fullDate = value
            default: continue
            }
            let dateOnly = DateFormatter()
            dateOnly.calendar = Calendar(identifier: .gregorian)
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let date = dateOnly.date(from: fullDate) { return date }
        }
        return nil
    }
}
