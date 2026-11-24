enum SimulatorClinicalSamples {
    static let bundle = """
    {
      "resourceType": "Bundle", "type": "collection",
      "entry": [
        {"resource": {
          "resourceType": "MedicationRequest", "id": "demo-metformin",
          "status": "active", "intent": "order", "subject": {"reference": "Patient/demo"},
          "medicationCodeableConcept": {"text": "Metformin 500 mg tablet"},
          "authoredOn": "2025-02-10",
          "dosageInstruction": [{"text": "500 mg by mouth twice daily with meals"}]
        }},
        {"resource": {
          "resourceType": "Observation", "id": "demo-a1c", "status": "final",
          "subject": {"reference": "Patient/demo"},
          "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "laboratory"}]}],
          "code": {"coding": [{"system": "http://loinc.org", "code": "4548-4", "display": "Hemoglobin A1c"}]},
          "effectiveDateTime": "2025-02-08T09:30:00-08:00",
          "valueQuantity": {"value": 7.1, "unit": "%", "system": "http://unitsofmeasure.org", "code": "%"},
          "interpretation": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation", "code": "H"}]}],
          "referenceRange": [{"low": {"value": 4, "unit": "%"}, "high": {"value": 5.6, "unit": "%"}}]
        }},
        {"resource": {
          "resourceType": "Condition", "id": "demo-diabetes",
          "clinicalStatus": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/condition-clinical", "code": "active"}]},
          "code": {"coding": [{"system": "http://snomed.info/sct", "code": "44054006", "display": "Type 2 diabetes mellitus"}]},
          "subject": {"reference": "Patient/demo"}, "recordedDate": "2025-02-10"
        }},
        {"resource": {
          "resourceType": "AllergyIntolerance", "id": "demo-penicillin",
          "clinicalStatus": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical", "code": "active"}]},
          "patient": {"reference": "Patient/demo"}, "recordedDate": "2024-09-05",
          "code": {"text": "Penicillin"}, "criticality": "high",
          "reaction": [{"manifestation": [{"text": "Hives"}]}]
        }},
        {"resource": {
          "resourceType": "Observation", "id": "demo-bp", "status": "final",
          "subject": {"reference": "Patient/demo"},
          "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "vital-signs"}]}],
          "code": {"coding": [{"system": "http://loinc.org", "code": "85354-9", "display": "Blood pressure"}]},
          "effectiveDateTime": "2025-02-10T10:15:00-08:00",
          "component": [
            {"code": {"coding": [{"system": "http://loinc.org", "code": "8480-6", "display": "Systolic"}]},
             "valueQuantity": {"value": 122, "unit": "mmHg", "system": "http://unitsofmeasure.org", "code": "mm[Hg]"}},
            {"code": {"coding": [{"system": "http://loinc.org", "code": "8462-4", "display": "Diastolic"}]},
             "valueQuantity": {"value": 76, "unit": "mmHg", "system": "http://unitsofmeasure.org", "code": "mm[Hg]"}}
          ]
        }},
        {"resource": {
          "resourceType": "Immunization", "id": "demo-flu", "status": "completed",
          "vaccineCode": {"text": "Seasonal influenza vaccine"}, "patient": {"reference": "Patient/demo"},
          "occurrenceDateTime": "2024-10-15", "doseQuantity": {"value": 0.5, "unit": "mL"}
        }}
      ]
    }
    """
}
