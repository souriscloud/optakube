import Foundation

/// Resolves a manifest's (apiVersion, kind) to the REST path of a single object.
/// Shared by "create from YAML" and Helm uninstall (which deletes each object in a
/// release's rendered manifest). Built-in types resolve from `ResourceType`; everything
/// else from the cluster's discovered CRDs.
enum ManifestRouting {
    struct GVR { let apiPath: String; let plural: String; let namespaced: Bool }

    static func resolve(apiVersion: String, kind: String, crds: [CRDDefinition]) -> GVR? {
        let apiPath = apiVersion.contains("/") ? "/apis/\(apiVersion)" : "/api/\(apiVersion)"
        if let rt = ResourceType.allCases.first(where: { $0.kind == kind }) {
            return GVR(apiPath: apiPath, plural: rt.resource, namespaced: rt.isNamespaced)
        }
        let group = apiVersion.contains("/") ? String(apiVersion.split(separator: "/").first ?? "") : ""
        if let crd = crds.first(where: { $0.kind == kind && $0.group == group }) {
            return GVR(apiPath: apiPath, plural: crd.plural, namespaced: crd.isNamespaced)
        }
        return nil
    }

    /// Server-relative path to one object, e.g. `/apis/apps/v1/namespaces/web/deployments/api`.
    static func resourcePath(apiVersion: String, kind: String, name: String,
                             namespace: String?, crds: [CRDDefinition], fallbackNamespace: String?) -> String? {
        guard let gvr = resolve(apiVersion: apiVersion, kind: kind, crds: crds) else { return nil }
        if gvr.namespaced {
            let ns = namespace ?? fallbackNamespace ?? "default"
            return "\(gvr.apiPath)/namespaces/\(ns)/\(gvr.plural)/\(name)"
        }
        return "\(gvr.apiPath)/\(gvr.plural)/\(name)"
    }
}
