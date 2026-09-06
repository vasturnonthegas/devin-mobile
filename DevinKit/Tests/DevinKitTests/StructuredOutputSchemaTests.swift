import XCTest
@testable import DevinKit

final class StructuredOutputSchemaTests: XCTestCase {
    func testParsesObjectSchema() throws {
        let value = try StructuredOutputSchema.parse("""
        {
          "$schema": "http://json-schema.org/draft-07/schema#",
          "type": "object",
          "properties": { "summary": { "type": "string" }, "items": { "$ref": "#/definitions/items" } },
          "definitions": { "items": { "type": "array", "items": { "type": "string" } } }
        }
        """)
        XCTAssertEqual(value["type"], .string("object"))
        XCTAssertEqual(value["properties"]?["items"]?["$ref"], .string("#/definitions/items"), "local refs are allowed")
    }

    func testRejectsMalformedJSON() {
        for text in [#"{"type": "object""#, #"{"type": }"#, "not json", #"{"a":1} trailing"#] {
            XCTAssertThrowsError(try StructuredOutputSchema.parse(text), text) { error in
                guard case StructuredOutputSchema.ValidationError.notJSON = error else {
                    return XCTFail("expected notJSON for \(text), got \(error)")
                }
                XCTAssertTrue(error.localizedDescription.hasPrefix("Schema is not valid JSON"))
            }
        }
    }

    func testRejectsNonObjectRoots() {
        XCTAssertThrowsError(try StructuredOutputSchema.parse(#"["type"]"#)) { error in
            XCTAssertEqual(error as? StructuredOutputSchema.ValidationError, .notObject)
        }
        XCTAssertThrowsError(try StructuredOutputSchema.parse(#""object""#)) { error in
            XCTAssertEqual(error as? StructuredOutputSchema.ValidationError, .notObject)
        }
        XCTAssertThrowsError(try StructuredOutputSchema.parse("42")) { error in
            XCTAssertEqual(error as? StructuredOutputSchema.ValidationError, .notObject)
        }
    }

    func testRejectsExternalReferencesAnywhereInTree() {
        let text = #"{"type":"object","properties":{"a":{"anyOf":[{"type":"null"},{"$ref":"https://example.com/a.json"}]}}}"#
        XCTAssertThrowsError(try StructuredOutputSchema.parse(text)) { error in
            XCTAssertEqual(error as? StructuredOutputSchema.ValidationError, .externalReference("https://example.com/a.json"))
            XCTAssertEqual(error.localizedDescription, "Schema must be self-contained; external $ref \"https://example.com/a.json\" is not allowed.")
        }
    }

    func testRejectsSchemasOver64KB() {
        let padding = String(repeating: "x", count: StructuredOutputSchema.maxBytes)
        XCTAssertThrowsError(try StructuredOutputSchema.parse(#"{"description":"\#(padding)"}"#)) { error in
            guard case StructuredOutputSchema.ValidationError.tooLarge(let bytes)? = error as? StructuredOutputSchema.ValidationError else {
                return XCTFail("expected tooLarge, got \(error)")
            }
            XCTAssertGreaterThan(bytes, StructuredOutputSchema.maxBytes)
        }
    }
}
