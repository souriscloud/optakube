import XCTest
@testable import OptaKube

final class PersistenceAndDiffTests: XCTestCase {

    // MARK: - SavedView codable round-trip

    func testSavedViewRoundTrips() throws {
        let view = SavedView(name: "prod · Pods", namespace: "prod", resourceType: "pods", labelFilter: "app=web")
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(SavedView.self, from: data)
        XCTAssertEqual(decoded.name, "prod · Pods")
        XCTAssertEqual(decoded.namespace, "prod")
        XCTAssertEqual(decoded.resourceType, "pods")
        XCTAssertEqual(decoded.labelFilter, "app=web")
        XCTAssertEqual(decoded.id, view.id)
    }

    func testSavedViewResolvesType() {
        XCTAssertEqual(SavedView(name: "x", namespace: nil, resourceType: "deployments").resolvedType, .deployments)
        XCTAssertNil(SavedView(name: "x", namespace: nil, resourceType: "not-a-type").resolvedType)
    }

    func testSavedViewArrayRoundTrips() throws {
        let views = [
            SavedView(name: "a", namespace: "ns1", resourceType: "pods"),
            SavedView(name: "b", namespace: nil, resourceType: "services", labelFilter: "tier=api"),
        ]
        let data = try JSONEncoder().encode(views)
        let decoded = try JSONDecoder().decode([SavedView].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[1].labelFilter, "tier=api")
        XCTAssertNil(decoded[1].namespace)
    }

    // MARK: - WindowState codable

    func testWindowStateRoundTrips() throws {
        let state = WindowState(namespace: "kube-system", resourceType: "pods", clusterIds: ["c1", "c2"])
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)
        XCTAssertEqual(decoded.namespace, "kube-system")
        XCTAssertEqual(decoded.resourceType, "pods")
        XCTAssertEqual(decoded.clusterIds, ["c1", "c2"])
    }

    // MARK: - YAML unified diff

    func testDiffDetectsNoChanges() {
        let yaml = "a: 1\nb: 2\n"
        let lines = YAMLDiffView.unifiedDiff(from: yaml, to: yaml)
        XCTAssertFalse(lines.contains { $0.kind == .added || $0.kind == .removed })
    }

    func testDiffDetectsChangedLine() {
        let before = "spec:\n  replicas: 3\n"
        let after = "spec:\n  replicas: 5\n"
        let lines = YAMLDiffView.unifiedDiff(from: before, to: after)
        let added = lines.filter { $0.kind == .added }
        let removed = lines.filter { $0.kind == .removed }
        XCTAssertEqual(removed.map(\.text), ["  replicas: 3"])
        XCTAssertEqual(added.map(\.text), ["  replicas: 5"])
        // The unchanged "spec:" line is preserved as context.
        XCTAssertTrue(lines.contains { $0.kind == .context && $0.text == "spec:" })
    }

    func testDiffDetectsPureAddition() {
        let before = "a: 1\n"
        let after = "a: 1\nb: 2\n"
        let lines = YAMLDiffView.unifiedDiff(from: before, to: after)
        XCTAssertEqual(lines.filter { $0.kind == .added }.map(\.text), ["b: 2"])
        XCTAssertTrue(lines.filter { $0.kind == .removed }.isEmpty)
    }

    func testDiffDetectsPureRemoval() {
        let before = "a: 1\nb: 2\n"
        let after = "a: 1\n"
        let lines = YAMLDiffView.unifiedDiff(from: before, to: after)
        XCTAssertEqual(lines.filter { $0.kind == .removed }.map(\.text), ["b: 2"])
        XCTAssertTrue(lines.filter { $0.kind == .added }.isEmpty)
    }
}
