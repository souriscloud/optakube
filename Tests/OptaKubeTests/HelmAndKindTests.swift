import XCTest
@testable import OptaKube

final class HelmAndKindTests: XCTestCase {

    // MARK: - Helm gunzip

    func testGunzipInflatesGzipStream() {
        // `printf 'hello helm release manifest' | gzip | base64`
        let b64 = "H4sIABomG2oAA8tIzcnJV8hIzclVKErNSU0sTlXITczLTEstLgEAzmK4yxsAAAA="
        let gz = Data(base64Encoded: b64)!
        let out = HelmRelease.gunzip(gz)
        XCTAssertNotNil(out)
        XCTAssertEqual(out.flatMap { String(data: $0, encoding: .utf8) }, "hello helm release manifest")
    }

    func testGunzipRejectsNonGzip() {
        XCTAssertNil(HelmRelease.gunzip(Data([0x00, 0x01, 0x02, 0x03])))
        XCTAssertNil(HelmRelease.gunzip(Data()))
    }

    func testHelmReleaseDecodeRejectsGarbage() {
        // Not valid base64-of-base64-of-gzip → nil, no crash.
        XCTAssertNil(HelmRelease.decode(fromSecretReleaseB64: "not-real-data", namespace: "default"))
    }

    // MARK: - Helm gzip encoder (rollback path)

    func testCRC32KnownVector() {
        // Standard CRC-32 check value for "123456789".
        XCTAssertEqual(HelmRelease.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testGzipRoundTripsThroughOwnGunzip() {
        let original = Data("""
        {"name":"demo","version":3,"info":{"status":"deployed"},"manifest":"apiVersion: v1\\nkind: ConfigMap"}
        """.utf8)
        let gz = HelmRelease.gzip(original)
        XCTAssertNotNil(gz)
        // Must carry the gzip magic.
        XCTAssertEqual(gz?[gz!.startIndex], 0x1f)
        XCTAssertEqual(gz?[gz!.startIndex + 1], 0x8b)
        let back = gz.flatMap { HelmRelease.gunzip($0) }
        XCTAssertEqual(back, original)
    }

    func testEncodeForSecretDataIsDecodableAgain() {
        // Round-trip the full secret payload: encode → decode full JSON.
        let json: [String: Any] = ["name": "demo", "version": 2, "info": ["status": "deployed"]]
        guard let b64 = HelmRelease.encodeForSecretData(json: json) else { return XCTFail("encode failed") }
        let decoded = HelmRelease.decodeFullJSON(fromSecretReleaseB64: b64)
        XCTAssertEqual(decoded?["name"] as? String, "demo")
        XCTAssertEqual(decoded?["version"] as? Int, 2)
        XCTAssertEqual((decoded?["info"] as? [String: Any])?["status"] as? String, "deployed")
    }

    // MARK: - Manifest doc splitting (uninstall/rollback)

    func testManifestDocsSplitsMultiDoc() {
        let manifest = """
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: a
        ---
        apiVersion: v1
        kind: Service
        metadata:
          name: b
        """
        let docs = AppViewModel.manifestDocs(manifest)
        XCTAssertEqual(docs.count, 2)
        XCTAssertTrue(docs[0].contains("ConfigMap"))
        XCTAssertTrue(docs[1].contains("Service"))
    }

    // MARK: - ResourceType.kind (used by create/apply routing)

    func testEveryResourceTypeHasNonEmptyKind() {
        for type in ResourceType.allCases {
            XCTAssertFalse(type.kind.isEmpty, "\(type) has empty kind")
        }
    }

    func testKindMapsBackToResourceType() {
        // The create/apply resolver looks up a manifest's `kind` against allCases.
        XCTAssertEqual(ResourceType.allCases.first { $0.kind == "Deployment" }, .deployments)
        XCTAssertEqual(ResourceType.allCases.first { $0.kind == "ConfigMap" }, .configMaps)
        XCTAssertEqual(ResourceType.allCases.first { $0.kind == "ClusterRoleBinding" }, .clusterRoleBindings)
        XCTAssertEqual(ResourceType.allCases.first { $0.kind == "StorageClass" }, .storageClasses)
        XCTAssertEqual(ResourceType.allCases.first { $0.kind == "PodDisruptionBudget" }, .podDisruptionBudgets)
    }

    func testKindsAreUnique() {
        let kinds = ResourceType.allCases.map(\.kind)
        XCTAssertEqual(Set(kinds).count, kinds.count, "ResourceType kinds must be unique for manifest routing")
    }

    // MARK: - New resource types wiring

    func testNewTypesHaveCorrectGroupsAndScope() {
        XCTAssertEqual(ResourceType.roles.apiGroupName, "rbac.authorization.k8s.io")
        XCTAssertTrue(ResourceType.roles.isNamespaced)
        XCTAssertEqual(ResourceType.clusterRoles.apiGroupName, "rbac.authorization.k8s.io")
        XCTAssertFalse(ResourceType.clusterRoles.isNamespaced)
        XCTAssertEqual(ResourceType.storageClasses.apiGroupName, "storage.k8s.io")
        XCTAssertFalse(ResourceType.storageClasses.isNamespaced)
        XCTAssertEqual(ResourceType.podDisruptionBudgets.apiGroupName, "policy")
        XCTAssertTrue(ResourceType.podDisruptionBudgets.isNamespaced)
        XCTAssertEqual(ResourceType.resourceQuotas.apiGroupName, "")  // core
    }
}
