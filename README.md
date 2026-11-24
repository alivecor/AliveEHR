# EHR Demo

A native SwiftUI demo for iOS 17 and later. It compares clinical records from the Apple Health local store with patient-scoped records fetched from a SMART on FHIR R4 sandbox.

## Run in Xcode

1. Open `EHRDemo.xcodeproj`, select the **EHRDemo** scheme, and run on an iOS 17 or later Simulator. The Xcode project is included and has no package dependencies. To regenerate it after adding Swift files, run `xcodegen generate`.
2. For an iPhone or iPad, select your development team in **Signing & Capabilities** and use a bundle identifier provisioned for that team. Enable **HealthKit** and check **Clinical Health Records**. The target already declares `com.apple.developer.healthkit = true` and `com.apple.developer.healthkit.access = [health-records]`.
3. In **Connections**, tap **Connect Apple Health Records**. For a quick offline demo, turn on **Load Simulator Sample Records** and switch to **Apple Health**. To exercise a real Simulator query, add a sample account in the Health app, turn off the app's fixture toggle, and re-query. [Apple Simulator instructions](https://developer.apple.com/documentation/healthkit/accessing-sample-data-in-the-simulator)

### Target configuration

| Info.plist key | Value |
| --- | --- |
| `NSHealthClinicalHealthRecordsShareUsageDescription` | Read your clinical records from Apple Health so you can view and compare them on this device. |
| `NSHealthShareUsageDescription` | Read records you choose to share from Apple Health and display them in the Apple Health tab. |
| `CFBundleURLTypes` | One entry with `CFBundleTypeRole = Editor`, `CFBundleURLName = $(PRODUCT_BUNDLE_IDENTIFIER).oauth`, and `CFBundleURLSchemes = [ehr-demo]`. |

The redirect URI is `ehr-demo://oauth-callback`. iOS registers the scheme from the plist. The app validates the host, path, state, and authorization code after the browser redirects.

### Direct EHR

| Preset | FHIR base URL | Client setup |
| --- | --- | --- |
| SMART Health IT | `https://launch.smarthealthit.org/v/r4/fhir` | The editor starts with `ehr-demo`. The sandbox launch preset opens a simulated patient portal. |
| Epic Sandbox | `https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4` | Enter your public, non-production client ID. Register the exact callback and enable the desired FHIR APIs. [Epic app registration](https://fhir.epic.com/Documentation?docId=patientfacingfhirapps) |
| Oracle Health Sandbox | `https://fhir-myrecord.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d` | Enter your public patient-facing sandbox client ID registered for the exact callback. The endpoint advertises individual patient read scopes. [Oracle sandbox registration](https://docs.oracle.com/en/industries/health/millennium-platform-apis/build-smart-on-fhir-apps/) |

1. Select the sandbox in **Connections**, then tap **Sign in with EHR Portal** and choose a test patient. **Direct EHR** loads the patient's records on first visit. Pull down to refresh.
2. Tap any record to see its **Clinical Summary** or **Raw FHIR JSON**. Both tabs use the same filter chips, cards, and inspector.
3. To demo writes, turn on **Enable sample vital writes** before sign-in on a sandbox that supports Observation creation. If the session grants create permission, open **Direct EHR → + Post Vital** and submit a sample blood pressure. The sheet shows the server's response and refreshes the list when closed. Support depends on the sandbox and the APIs enabled for your client.

## Data flow

- **Apple Health** requests read access with an empty share set and queries all six clinical record types concurrently. An empty result can mean there are no available records or that read access was declined. Simulator fixtures are bundled, explicitly labeled, and separate from the system store.
- **Direct EHR** discovers the authorization and token endpoints, signs in using an ephemeral system browser and S256 PKCE, and fetches the five FHIR resource types. The status and latency are from an individual HTTP round trip. Credentials and patient context are stored in a device-only Keychain item. If the server returns a refresh token, the app uses it shortly before expiration. **Disconnect** removes the stored session and clears its records.
- Both services map into `ClinicalItem` via `FHIRParser`. The direct path uses the sandbox name when the resource does not identify a facility. The abnormal indicator reflects the FHIR interpretation codes. The raw JSON inspector copies locally with a two-minute pasteboard expiration.
