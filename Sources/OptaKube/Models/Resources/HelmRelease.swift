import Foundation
import Compression

/// A Helm v3 release revision, decoded from its backing `helm.sh/release.v1` Secret.
///
/// Helm stores each revision as a Secret whose `data.release` value is, once the
/// Kubernetes base64 layer is stripped, *another* base64 string wrapping a gzip stream
/// of the release JSON. So decoding is: k8s-base64 → base64 → gunzip → JSON.
struct HelmRelease: Identifiable, Sendable {
    let name: String
    let namespace: String
    let revision: Int
    let status: String
    let chart: String
    let chartVersion: String
    let appVersion: String
    let updated: String
    let description: String
    /// Rendered manifest (multi-doc YAML) for this revision.
    let manifest: String
    /// User-supplied values as pretty JSON (Helm stores them as an object).
    let valuesJSON: String

    var id: String { "\(namespace)/\(name)/\(revision)" }

    var chartDisplay: String { chartVersion.isEmpty ? chart : "\(chart)-\(chartVersion)" }

    // MARK: - Decoding

    /// Decode a single release Secret's `data.release` (the value is still
    /// Kubernetes-base64-encoded at this point).
    static func decode(fromSecretReleaseB64 b64: String, namespace: String) -> HelmRelease? {
        // Layer 1: Kubernetes base64 → Helm's stored payload (itself base64 of gzip).
        guard let layer1 = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        // Layer 2: that payload is ascii base64 of the gzip bytes.
        let inner = String(decoding: layer1, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gz = Data(base64Encoded: inner) else { return nil }
        guard let jsonData = gunzip(gz) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
        return from(json: obj, fallbackNamespace: namespace)
    }

    private static func from(json: [String: Any], fallbackNamespace: String) -> HelmRelease? {
        guard let name = json["name"] as? String else { return nil }
        let info = json["info"] as? [String: Any]
        let chart = json["chart"] as? [String: Any]
        let chartMeta = chart?["metadata"] as? [String: Any]
        let config = json["config"] as? [String: Any] ?? [:]

        let valuesJSON: String = {
            guard !config.isEmpty,
                  let d = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]),
                  let s = String(data: d, encoding: .utf8) else { return "{}" }
            return s
        }()

        return HelmRelease(
            name: name,
            namespace: json["namespace"] as? String ?? fallbackNamespace,
            revision: json["version"] as? Int ?? 0,
            status: (info?["status"] as? String) ?? "unknown",
            chart: (chartMeta?["name"] as? String) ?? "",
            chartVersion: (chartMeta?["version"] as? String) ?? "",
            appVersion: (chartMeta?["appVersion"] as? String) ?? "",
            updated: (info?["last_deployed"] as? String) ?? "",
            description: (info?["description"] as? String) ?? "",
            manifest: (json["manifest"] as? String) ?? "",
            valuesJSON: valuesJSON
        )
    }

    /// Decode the *full* release JSON (not the lossy model) — needed by rollback, which
    /// must rebuild a complete release object for the new revision.
    static func decodeFullJSON(fromSecretReleaseB64 b64: String) -> [String: Any]? {
        guard let layer1 = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let inner = String(decoding: layer1, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gz = Data(base64Encoded: inner), let jsonData = gunzip(gz) else { return nil }
        return try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    }

    /// Encode a release JSON back into the value to store in a Secret's `data.release`:
    /// gzip → base64 (Helm's layer) → base64 (the Kubernetes Secret `data` layer).
    static func encodeForSecretData(json: [String: Any]) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json),
              let gz = gzip(jsonData) else { return nil }
        let helmLayer = gz.base64EncodedString()
        return Data(helmLayer.utf8).base64EncodedString()
    }

    /// Compress to a gzip stream: 10-byte header + raw DEFLATE (Compression's
    /// `COMPRESSION_ZLIB` is RFC-1951 raw deflate, despite the name) + CRC32 + ISIZE.
    static func gzip(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let cap = data.count + 64 * 1024 + 128
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let deflated = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(dst, cap, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard deflated > 0 else { return nil }
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])  // header (OS=unknown)
        out.append(dst, count: deflated)
        var crc = crc32(data).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        var isize = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &isize) { out.append(contentsOf: $0) }
        return out
    }

    /// Standard CRC-32 (polynomial 0xEDB88320), bit-by-bit — release payloads are small
    /// so a table isn't worth it.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Inflate a gzip stream using the Compression framework. The framework's zlib
    /// codec wants a raw deflate body, so we strip gzip's 10-byte header and 8-byte
    /// trailer (Helm's Go gzip writer emits no optional header fields) and read the
    /// uncompressed size from the trailer's ISIZE.
    static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else { return nil }
        let body = data.subdata(in: (data.startIndex + 10)..<(data.endIndex - 8))

        // ISIZE: last 4 bytes, little-endian, = original size mod 2^32.
        let isizeBytes = data.suffix(4)
        var isize = 0
        for (i, b) in isizeBytes.enumerated() { isize |= Int(b) << (8 * i) }
        // Guard against a bogus/zero ISIZE; fall back to a generous buffer.
        //
        // ISIZE comes from cluster data — a Helm release Secret — so it must be bounded.
        // A truncated or corrupt Secret can declare up to 0xFFFFFFFF, and
        // UnsafeMutablePointer.allocate traps rather than returning nil on failure, so a
        // single damaged release would crash the app just by opening the Helm view.
        // 64 MiB is far above any real rendered manifest.
        let maxCapacity = 64 << 20
        let declared = isize > 0 ? isize : max(body.count * 8, 65_536)
        let capacity = min(max(declared, 65_536), maxCapacity)

        return body.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            guard let srcPtr = src.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { dst.deallocate() }
            let written = compression_decode_buffer(dst, capacity, srcPtr, body.count, nil, COMPRESSION_ZLIB)
            guard written > 0 else { return nil }
            return Data(bytes: dst, count: written)
        }
    }
}
