import Foundation
import Yams

// MARK: - Helm uninstall / rollback
//
// These manipulate Helm's release storage directly (the `helm.sh/release.v1` Secrets),
// mirroring what the helm CLI does:
//   • uninstall — delete every object in the current revision's rendered manifest, then
//     delete all of the release's history Secrets.
//   • rollback  — re-apply a previous revision's manifest, write a NEW history Secret
//     (revision = max+1, status deployed) cloned from the target, and mark the prior
//     current revision superseded.

extension AppViewModel {

    struct HelmActionResult: Sendable {
        let ok: Bool
        let message: String
    }

    /// Uninstall a release: delete its manifest's objects, then its history Secrets.
    @MainActor
    func helmUninstall(release: String, namespace: String, manifest: String, clusterId: String) async -> HelmActionResult {
        guard let client = activeClients[clusterId] else { return .init(ok: false, message: "No connection.") }
        let crds = discoveredCRDs
        var failures: [String] = []

        // Delete manifest objects (reverse order, best-effort — GC handles dependents).
        for doc in Self.manifestDocs(manifest).reversed() {
            guard let parsed = try? Yams.load(yaml: doc) as? [String: Any],
                  let apiVersion = parsed["apiVersion"] as? String,
                  let kind = parsed["kind"] as? String,
                  let meta = parsed["metadata"] as? [String: Any],
                  let name = meta["name"] as? String else { continue }
            let docNS = meta["namespace"] as? String
            guard let path = ManifestRouting.resourcePath(apiVersion: apiVersion, kind: kind, name: name,
                                                          namespace: docNS, crds: crds, fallbackNamespace: namespace) else { continue }
            do { try await client.deleteByPath(path) }
            catch K8sError.requestFailed(404, _) { /* already gone */ }
            catch { failures.append("\(kind)/\(name)") }
        }

        // Delete the release history Secrets.
        do {
            let secrets = try await client.listHelmReleaseSecrets(release: release, namespace: namespace)
            for s in secrets {
                try? await client.deleteByPath("/api/v1/namespaces/\(namespace)/secrets/\(s.secretName)")
            }
        } catch {
            failures.append("release secrets")
        }

        await loadHelmReleases()
        if failures.isEmpty {
            return .init(ok: true, message: "Uninstalled \(release).")
        }
        return .init(ok: false, message: "Uninstalled \(release) with issues deleting: \(failures.joined(separator: ", ")).")
    }

    /// Roll back to `toRevision`: re-apply its manifest, write a new deployed revision,
    /// and supersede the prior current one.
    @MainActor
    func helmRollback(release: String, namespace: String, toRevision: Int, clusterId: String) async -> HelmActionResult {
        guard let client = activeClients[clusterId] else { return .init(ok: false, message: "No connection.") }
        do {
            let secrets = try await client.listHelmReleaseSecrets(release: release, namespace: namespace)
            guard let maxRev = secrets.map(\.revision).max() else {
                return .init(ok: false, message: "No release history found.")
            }
            guard let target = secrets.first(where: { $0.revision == toRevision }),
                  var targetJSON = HelmRelease.decodeFullJSON(fromSecretReleaseB64: target.releaseB64) else {
                return .init(ok: false, message: "Couldn't read revision \(toRevision).")
            }

            let newRev = maxRev + 1
            let now = ISO8601DateFormatter().string(from: Date())
            var info = targetJSON["info"] as? [String: Any] ?? [:]
            info["status"] = "deployed"
            info["last_deployed"] = now
            info["description"] = "Rollback to \(toRevision)"
            targetJSON["info"] = info
            targetJSON["version"] = newRev

            guard let newData = HelmRelease.encodeForSecretData(json: targetJSON) else {
                return .init(ok: false, message: "Couldn't encode the new revision.")
            }
            try await client.createHelmReleaseSecret(release: release, namespace: namespace,
                                                     revision: newRev, status: "deployed", dataReleaseB64: newData)

            // Re-apply the target revision's manifest.
            let manifest = targetJSON["manifest"] as? String ?? ""
            let crds = discoveredCRDs
            for doc in Self.manifestDocs(manifest) {
                guard let parsed = try? Yams.load(yaml: doc) as? [String: Any],
                      let apiVersion = parsed["apiVersion"] as? String,
                      let kind = parsed["kind"] as? String,
                      let meta = parsed["metadata"] as? [String: Any],
                      let name = meta["name"] as? String else { continue }
                let docNS = meta["namespace"] as? String
                guard let path = ManifestRouting.resourcePath(apiVersion: apiVersion, kind: kind, name: name,
                                                             namespace: docNS, crds: crds, fallbackNamespace: namespace) else { continue }
                try? await client.serverSideApply(path: path, yaml: doc)
            }

            // Mark the prior current revision superseded.
            if let current = secrets.first(where: { $0.revision == maxRev }),
               var curJSON = HelmRelease.decodeFullJSON(fromSecretReleaseB64: current.releaseB64) {
                var curInfo = curJSON["info"] as? [String: Any] ?? [:]
                curInfo["status"] = "superseded"
                curJSON["info"] = curInfo
                if let curData = HelmRelease.encodeForSecretData(json: curJSON) {
                    try? await client.patchHelmReleaseSecret(secretName: current.secretName, namespace: namespace,
                                                             status: "superseded", dataReleaseB64: curData)
                }
            }

            await loadHelmReleases()
            return .init(ok: true, message: "Rolled back \(release) to revision \(toRevision) (new revision \(newRev)).")
        } catch {
            return .init(ok: false, message: error.localizedDescription)
        }
    }

    /// Split a multi-document manifest into individual YAML documents.
    static func manifestDocs(_ manifest: String) -> [String] {
        manifest
            .components(separatedBy: "\n---")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "---" }
    }
}
