import XCTest
@testable import OptaKube

/// Guards the YAML→JSON conversion on the manifest apply path. Every case here is a
/// value a user can legitimately type into the editor that YAML 1.1 would resolve
/// differently from Kubernetes.
final class ManifestYAMLTests: XCTestCase {

    private func object(_ yaml: String) throws -> [String: Any] {
        let data = try ManifestYAML.jsonData(from: yaml)
        let decoded = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(decoded as? [String: Any])
    }

    // MARK: - Timestamps

    func testBareDateStaysAStringInsteadOfCrashing() throws {
        // Yams' default resolver turns this into a Foundation.Date, which
        // JSONSerialization rejects by raising an ObjC exception that no Swift `catch`
        // can intercept — the process aborted and the user's edits were lost.
        let result = try object("""
        data:
          release-date: 2026-01-01
        """)
        let data = try XCTUnwrap(result["data"] as? [String: Any])
        XCTAssertEqual(data["release-date"] as? String, "2026-01-01")
    }

    func testRFC3339TimestampStaysAString() throws {
        let result = try object("""
        metadata:
          annotations:
            restartedAt: 2025-07-29T10:30:45Z
        """)
        let metadata = try XCTUnwrap(result["metadata"] as? [String: Any])
        let annotations = try XCTUnwrap(metadata["annotations"] as? [String: Any])
        XCTAssertEqual(annotations["restartedAt"] as? String, "2025-07-29T10:30:45Z")
    }

    func testQuotedTimestampIsUnchanged() throws {
        let result = try object("""
        data:
          when: "2026-01-01"
        """)
        let data = try XCTUnwrap(result["data"] as? [String: Any])
        XCTAssertEqual(data["when"] as? String, "2026-01-01")
    }

    // MARK: - Booleans

    func testYamlOneOneBooleanWordsStayStrings() throws {
        // Kubernetes treats these as strings; YAML 1.1 resolves them to booleans, which
        // silently rewrote values the user typed as text.
        let result = try object("""
        data:
          a: yes
          b: no
          c: on
          d: off
          e: Yes
          f: OFF
        """)
        let data = try XCTUnwrap(result["data"] as? [String: Any])
        XCTAssertEqual(data["a"] as? String, "yes")
        XCTAssertEqual(data["b"] as? String, "no")
        XCTAssertEqual(data["c"] as? String, "on")
        XCTAssertEqual(data["d"] as? String, "off")
        XCTAssertEqual(data["e"] as? String, "Yes")
        XCTAssertEqual(data["f"] as? String, "OFF")
    }

    func testRealBooleansStillDecodeAsBooleans() throws {
        // These must keep working: `suspend: true` on a CronJob is a genuine boolean.
        let result = try object("""
        spec:
          suspend: true
          paused: false
          upper: TRUE
        """)
        let spec = try XCTUnwrap(result["spec"] as? [String: Any])
        XCTAssertEqual(spec["suspend"] as? Bool, true)
        XCTAssertEqual(spec["paused"] as? Bool, false)
        XCTAssertEqual(spec["upper"] as? Bool, true)
    }

    // MARK: - Numbers (deliberately left matching kubectl)

    func testIntegersAndFloatsStillDecodeAsNumbers() throws {
        let result = try object("""
        spec:
          replicas: 3
          ratio: 0.5
        """)
        let spec = try XCTUnwrap(result["spec"] as? [String: Any])
        XCTAssertEqual(spec["replicas"] as? Int, 3)
        XCTAssertEqual(spec["ratio"] as? Double, 0.5)
    }

    // MARK: - Structure

    func testNestedStructuresAndListsSurvive() throws {
        let result = try object("""
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: web
        spec:
          replicas: 2
          template:
            spec:
              containers:
                - name: app
                  image: nginx:1.25
                  ports:
                    - containerPort: 8080
        """)
        XCTAssertEqual(result["kind"] as? String, "Deployment")
        let spec = try XCTUnwrap(result["spec"] as? [String: Any])
        let template = try XCTUnwrap(spec["template"] as? [String: Any])
        let innerSpec = try XCTUnwrap(template["spec"] as? [String: Any])
        let containers = try XCTUnwrap(innerSpec["containers"] as? [[String: Any]])
        XCTAssertEqual(containers.count, 1)
        XCTAssertEqual(containers[0]["image"] as? String, "nginx:1.25")
        let ports = try XCTUnwrap(containers[0]["ports"] as? [[String: Any]])
        XCTAssertEqual(ports[0]["containerPort"] as? Int, 8080)
    }

    func testEmptyManifestThrowsInsteadOfProducingGarbage() {
        XCTAssertThrowsError(try ManifestYAML.jsonData(from: "   \n"))
    }

    func testNullValuesAreRepresentable() throws {
        // An explicit null is legal in a manifest and must not trip the JSON guard.
        let result = try object("""
        spec:
          selector: null
        """)
        let spec = try XCTUnwrap(result["spec"] as? [String: Any])
        XCTAssertTrue(spec["selector"] is NSNull)
    }
}
