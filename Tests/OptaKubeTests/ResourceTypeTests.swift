import XCTest
@testable import OptaKube

final class ResourceTypeTests: XCTestCase {

    func testCoreResourcesHaveEmptyAPIGroupName() {
        // Anything served from /api/v1 is the core group, expressed as "" to the
        // authorization API.
        XCTAssertEqual(ResourceType.pods.apiGroupName, "")
        XCTAssertEqual(ResourceType.services.apiGroupName, "")
        XCTAssertEqual(ResourceType.configMaps.apiGroupName, "")
        XCTAssertEqual(ResourceType.nodes.apiGroupName, "")
        XCTAssertEqual(ResourceType.namespaces.apiGroupName, "")
    }

    func testNamedAPIGroupsExtractGroupWithoutVersion() {
        XCTAssertEqual(ResourceType.deployments.apiGroupName, "apps")
        XCTAssertEqual(ResourceType.statefulSets.apiGroupName, "apps")
        XCTAssertEqual(ResourceType.jobs.apiGroupName, "batch")
        XCTAssertEqual(ResourceType.cronJobs.apiGroupName, "batch")
        XCTAssertEqual(ResourceType.ingresses.apiGroupName, "networking.k8s.io")
        XCTAssertEqual(ResourceType.networkPolicies.apiGroupName, "networking.k8s.io")
        XCTAssertEqual(ResourceType.horizontalPodAutoscalers.apiGroupName, "autoscaling")
    }

    func testEveryResourceTypeHasConsistentAPIGroupName() {
        // apiGroupName must be derivable for every case (no crashes, and it must match
        // the prefix in the full apiGroup path).
        for type in ResourceType.allCases {
            let name = type.apiGroupName
            if type.apiGroup.hasPrefix("/api/v1") {
                XCTAssertEqual(name, "", "\(type) is core but got group '\(name)'")
            } else {
                XCTAssertFalse(name.isEmpty, "\(type) should have a non-empty group")
                XCTAssertTrue(type.apiGroup.contains("/\(name)/"), "\(type) apiGroup \(type.apiGroup) should contain group \(name)")
            }
        }
    }

    func testListURLConstructionNamespaced() {
        let url = ResourceType.pods.listURL(server: "https://k8s.example:6443", namespace: "kube-system")
        XCTAssertEqual(url?.absoluteString, "https://k8s.example:6443/api/v1/namespaces/kube-system/pods")
    }

    func testListURLConstructionClusterScoped() {
        let url = ResourceType.nodes.listURL(server: "https://k8s.example:6443", namespace: "ignored")
        // Nodes are cluster-scoped, so the namespace segment must be omitted.
        XCTAssertEqual(url?.absoluteString, "https://k8s.example:6443/api/v1/nodes")
    }

    func testListURLConstructionAppsGroup() {
        let url = ResourceType.deployments.listURL(server: "https://k8s.example:6443", namespace: "default")
        XCTAssertEqual(url?.absoluteString, "https://k8s.example:6443/apis/apps/v1/namespaces/default/deployments")
    }
}
