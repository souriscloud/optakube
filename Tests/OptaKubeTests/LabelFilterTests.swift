import XCTest
@testable import OptaKube

final class LabelFilterTests: XCTestCase {

    // MARK: - Parsing

    func testEmptySelectorMatchesEverything() {
        let f = LabelFilter("")
        XCTAssertTrue(f.isValid)
        XCTAssertTrue(f.requirements.isEmpty)
        XCTAssertTrue(f.matches(["app": "web"]))
        XCTAssertTrue(f.matches(nil))
    }

    func testWhitespaceOnlySelectorMatchesEverything() {
        XCTAssertTrue(LabelFilter("   ").matches(nil))
    }

    func testEqualityParsing() {
        let f = LabelFilter("app=web")
        XCTAssertEqual(f.requirements, [.equals(key: "app", value: "web")])
        XCTAssertTrue(f.isValid)
    }

    func testDoubleEqualsTreatedAsEquality() {
        let f = LabelFilter("app==web")
        XCTAssertEqual(f.requirements, [.equals(key: "app", value: "web")])
    }

    func testInequalityParsing() {
        let f = LabelFilter("tier!=db")
        XCTAssertEqual(f.requirements, [.notEquals(key: "tier", value: "db")])
    }

    func testExistenceAndNonExistence() {
        XCTAssertEqual(LabelFilter("release").requirements, [.exists(key: "release")])
        XCTAssertEqual(LabelFilter("!canary").requirements, [.notExists(key: "canary")])
    }

    func testSetMembershipParsing() {
        let f = LabelFilter("env in (prod, stage)")
        XCTAssertEqual(f.requirements, [.inSet(key: "env", values: ["prod", "stage"])])
    }

    func testNotInSetParsing() {
        let f = LabelFilter("env notin (dev,test)")
        XCTAssertEqual(f.requirements, [.notInSet(key: "env", values: ["dev", "test"])])
    }

    func testMultipleRequirementsAreAnded() {
        let f = LabelFilter("app=web,tier!=db,env in (prod,stage)")
        XCTAssertEqual(f.requirements.count, 3)
        XCTAssertTrue(f.isValid)
    }

    func testCommaInsideParenthesesNotSplit() {
        // The comma inside (prod,stage) must not create a third clause.
        let f = LabelFilter("env in (prod,stage),app=web")
        XCTAssertEqual(f.requirements.count, 2)
    }

    func testMalformedClauseMarksInvalidButKeepsValidOnes() {
        let f = LabelFilter("app=web,=,tier=db")
        XCTAssertFalse(f.isValid)            // the "=" clause has an empty key
        XCTAssertEqual(f.requirements.count, 2)  // but the two good ones survive
    }

    // MARK: - Matching

    func testEqualityMatching() {
        let f = LabelFilter("app=web")
        XCTAssertTrue(f.matches(["app": "web", "tier": "frontend"]))
        XCTAssertFalse(f.matches(["app": "api"]))
        XCTAssertFalse(f.matches(nil))
    }

    func testInequalityMatchesWhenKeyAbsent() {
        // kubectl semantics: key!=value is satisfied when the key is missing entirely.
        let f = LabelFilter("tier!=db")
        XCTAssertTrue(f.matches(["app": "web"]))      // no tier at all → ok
        XCTAssertTrue(f.matches(["tier": "frontend"]))
        XCTAssertFalse(f.matches(["tier": "db"]))
    }

    func testExistenceMatching() {
        let f = LabelFilter("release")
        XCTAssertTrue(f.matches(["release": "stable"]))
        XCTAssertTrue(f.matches(["release": ""]))     // present, even if empty
        XCTAssertFalse(f.matches(["app": "web"]))
    }

    func testNonExistenceMatching() {
        let f = LabelFilter("!canary")
        XCTAssertTrue(f.matches(["app": "web"]))
        XCTAssertFalse(f.matches(["canary": "true"]))
    }

    func testSetMembershipMatching() {
        let f = LabelFilter("env in (prod,stage)")
        XCTAssertTrue(f.matches(["env": "prod"]))
        XCTAssertTrue(f.matches(["env": "stage"]))
        XCTAssertFalse(f.matches(["env": "dev"]))
        XCTAssertFalse(f.matches(nil))
    }

    func testNotInSetMatching() {
        let f = LabelFilter("env notin (dev,test)")
        XCTAssertTrue(f.matches(["env": "prod"]))
        XCTAssertTrue(f.matches(nil))                 // absent key satisfies notin
        XCTAssertFalse(f.matches(["env": "dev"]))
    }

    func testCombinedRequirementsAllMustHold() {
        let f = LabelFilter("app=web,tier!=db")
        XCTAssertTrue(f.matches(["app": "web", "tier": "frontend"]))
        XCTAssertFalse(f.matches(["app": "web", "tier": "db"]))   // fails second clause
        XCTAssertFalse(f.matches(["app": "api", "tier": "frontend"])) // fails first
    }
}
