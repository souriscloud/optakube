import XCTest
@testable import OptaKube

/// Covers the two pure helpers the watch loop's correctness now depends on.
final class WatchEngineTests: XCTestCase {

    // MARK: - Expired-resourceVersion detection

    /// This is how kube-apiserver actually reports an expired resourceVersion on a watch:
    /// HTTP 200, then an in-stream ERROR event wrapping a Status. It used to be discarded,
    /// after which the stream finished *cleanly* — so the caller reconnected immediately
    /// with the same dead resourceVersion and never received another event.
    func testInStreamErrorStatusIsRecognisedAsExpired() throws {
        let line = Data("""
        {"type":"ERROR","object":{"kind":"Status","apiVersion":"v1","metadata":{},\
        "status":"Failure","message":"too old resource version: 1 (2)",\
        "reason":"Expired","code":410}}
        """.utf8)
        XCTAssertTrue(K8sAPIClient.isExpiredStatusLine(line))
    }

    func testBareStatusObjectIsRecognisedAsExpired() {
        let line = Data("""
        {"kind":"Status","apiVersion":"v1","status":"Failure","reason":"Expired","code":410}
        """.utf8)
        XCTAssertTrue(K8sAPIClient.isExpiredStatusLine(line))
    }

    func testGoneCodeWithoutExpiredReasonIsRecognised() {
        let line = Data(#"{"kind":"Status","code":410}"#.utf8)
        XCTAssertTrue(K8sAPIClient.isExpiredStatusLine(line))
    }

    func testOrdinaryWatchEventsAreNotMistakenForExpiry() {
        let line = Data("""
        {"type":"MODIFIED","object":{"kind":"Pod","metadata":{"name":"web-0",\
        "resourceVersion":"12345"}}}
        """.utf8)
        XCTAssertFalse(K8sAPIClient.isExpiredStatusLine(line))
    }

    func testUnrelatedStatusIsNotTreatedAsExpiry() {
        // A Forbidden status must not be mistaken for an expiry, or the loop would relist
        // in a tight cycle against a resource it isn't allowed to read.
        let line = Data("""
        {"kind":"Status","status":"Failure","reason":"Forbidden","code":403}
        """.utf8)
        XCTAssertFalse(K8sAPIClient.isExpiredStatusLine(line))
    }

    func testGarbageLineIsNotExpiry() {
        XCTAssertFalse(K8sAPIClient.isExpiredStatusLine(Data("not json".utf8)))
        XCTAssertFalse(K8sAPIClient.isExpiredStatusLine(Data()))
    }

    // MARK: - resourceVersion monotonicity

    func testResourceVersionOnlyMovesForward() {
        XCTAssertTrue(AppViewModel.resourceVersionIsNewer("200", than: "100"))
        XCTAssertFalse(AppViewModel.resourceVersionIsNewer("100", than: "200"))
        XCTAssertFalse(AppViewModel.resourceVersionIsNewer("100", than: "100"))
    }

    func testResourceVersionComparesNumericallyNotLexicographically() {
        // "9" > "100" as strings, which would rewind the watch and leave it resuming from
        // a version the server has already compacted away.
        XCTAssertTrue(AppViewModel.resourceVersionIsNewer("100", than: "9"))
        XCTAssertFalse(AppViewModel.resourceVersionIsNewer("9", than: "100"))
    }

    func testAnyVersionIsNewerThanNoneOrEmpty() {
        XCTAssertTrue(AppViewModel.resourceVersionIsNewer("1", than: nil))
        XCTAssertTrue(AppViewModel.resourceVersionIsNewer("1", than: ""))
    }

    func testNonNumericVersionsAreAccepted() {
        // resourceVersions are opaque by contract. If either side doesn't parse, prefer
        // moving on to getting stuck on a value we can't reason about.
        XCTAssertTrue(AppViewModel.resourceVersionIsNewer("abc", than: "100"))
        XCTAssertTrue(AppViewModel.resourceVersionIsNewer("200", than: "xyz"))
    }
}
