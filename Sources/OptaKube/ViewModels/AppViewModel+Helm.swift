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

        // Resolve every document to an API path BEFORE deleting anything. A document
        // whose path can't be resolved used to `continue` silently without being recorded,
        // and the release history Secrets were then deleted regardless — orphaning live
        // objects and leaving the release untrackable by the helm CLI, under a green
        // "Uninstalled X." message. The usual cause is a custom resource missing from
        // `discoveredCRDs`, which is itself populated with `try?`, so any user without
        // cluster-wide CRD list permission hit exactly this.
        var plan: [(path: String, label: String)] = []
        var unresolved: [String] = []
        for doc in Self.manifestDocs(manifest).reversed() {
            guard let parsed = try? Yams.load(yaml: doc) as? [String: Any],
                  let apiVersion = parsed["apiVersion"] as? String,
                  let kind = parsed["kind"] as? String,
                  let meta = parsed["metadata"] as? [String: Any],
                  let name = meta["name"] as? String else { continue }
            let docNS = meta["namespace"] as? String
            guard let path = ManifestRouting.resourcePath(apiVersion: apiVersion, kind: kind, name: name,
                                                          namespace: docNS, crds: crds, fallbackNamespace: namespace) else {
                unresolved.append("\(kind)/\(name)")
                continue
            }
            plan.append((path, "\(kind)/\(name)"))
        }

        if !unresolved.isEmpty {
            return .init(ok: false, message: "Not uninstalled. \(unresolved.count) object(s) in this "
                         + "release couldn't be resolved to an API path, so deleting the release "
                         + "history would orphan them: \(unresolved.joined(separator: ", ")). "
                         + "This usually means a CustomResourceDefinition wasn't discoverable — "
                         + "check that you can list CRDs on this cluster.")
        }

        for item in plan {
            do { try await client.deleteByPath(item.path) }
            catch K8sError.requestFailed(404, _) { /* already gone */ }
            catch { failures.append("\(item.label): \(error.localizedDescription)") }
        }

        // Only remove the release history once its objects are actually gone. Deleting it
        // while objects remain is the one irreversible step here — helm can no longer see
        // the release, so there is nothing left to retry against.
        if !failures.isEmpty {
            await loadHelmReleases()
            return .init(ok: false, message: "Release history kept: \(failures.count) object(s) "
                         + "could not be deleted, so \(release) is still tracked and you can retry.\n\n"
                         + failures.prefix(10).joined(separator: "\n"))
        }

        do {
            let secrets = try await client.listHelmReleaseSecrets(release: release, namespace: namespace)
            for s in secrets {
                do {
                    try await client.deleteByPath("/api/v1/namespaces/\(namespace)/secrets/\(s.secretName)")
                } catch K8sError.requestFailed(404, _) {
                    // already gone
                } catch {
                    failures.append("revision \(s.revision) secret: \(error.localizedDescription)")
                }
            }
        } catch {
            failures.append("release secrets: \(error.localizedDescription)")
        }

        await loadHelmReleases()
        if failures.isEmpty {
            return .init(ok: true, message: "Uninstalled \(release).")
        }
        return .init(ok: false, message: "Deleted \(release)'s objects, but its release history "
                     + "was not fully removed, so helm may still list it:\n\n"
                     + failures.joined(separator: "\n"))
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

            // Resolve and apply the manifest BEFORE recording the new revision, and report
            // per-object failures. This used to record the revision first and then apply
            // each document with `try?`, returning an unconditional "Rolled back X to
            // revision N" — so an RBAC denial or a rejecting webhook produced a green
            // success banner over a release whose history now claimed a revision that had
            // never been applied. A false success on a destructive operation is worse than
            // silence.
            let manifest = targetJSON["manifest"] as? String ?? ""
            let crds = discoveredCRDs
            var plan: [(path: String, doc: String, label: String)] = []
            var unresolved: [String] = []
            for doc in Self.manifestDocs(manifest) {
                guard let parsed = try? Yams.load(yaml: doc) as? [String: Any],
                      let apiVersion = parsed["apiVersion"] as? String,
                      let kind = parsed["kind"] as? String,
                      let meta = parsed["metadata"] as? [String: Any],
                      let name = meta["name"] as? String else { continue }
                let docNS = meta["namespace"] as? String
                guard let path = ManifestRouting.resourcePath(apiVersion: apiVersion, kind: kind, name: name,
                                                             namespace: docNS, crds: crds, fallbackNamespace: namespace) else {
                    unresolved.append("\(kind)/\(name)")
                    continue
                }
                plan.append((path, doc, "\(kind)/\(name)"))
            }

            if !unresolved.isEmpty {
                return .init(ok: false, message: "Rollback not attempted: \(unresolved.count) "
                             + "object(s) in revision \(toRevision) couldn't be resolved to an API "
                             + "path: \(unresolved.joined(separator: ", ")). Nothing was changed.")
            }

            var applyFailures: [String] = []
            for item in plan {
                do { try await client.serverSideApply(path: item.path, yaml: item.doc) }
                catch { applyFailures.append("\(item.label): \(error.localizedDescription)") }
            }

            if !applyFailures.isEmpty {
                await loadHelmReleases()
                return .init(ok: false, message: "Rollback incomplete — \(plan.count - applyFailures.count) "
                             + "of \(plan.count) object(s) applied, and the release history was not "
                             + "updated, so it still reflects revision \(maxRev).\n\n"
                             + applyFailures.prefix(10).joined(separator: "\n"))
            }

            try await client.createHelmReleaseSecret(release: release, namespace: namespace,
                                                     revision: newRev, status: "deployed", dataReleaseB64: newData)

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
