#if DEBUG
import Foundation
import DevinKit

/// Playbooks for the New Session picker and its body preview. The third entry advertises an
/// `access_type` outside the spec's enum so the unknown-value path is exercised in the Simulator.
extension MockAPI {
    static let playbooks: [Playbook] = [
        Playbook(
            playbookID: "playbook-mock-fixci",
            title: "Fix CI",
            body: """
            # Fix CI

            Investigate the failing job on the default branch and open a PR that turns it green.

            ## Procedure

            1. Reproduce the failure locally with `swift test`.
            2. Identify whether the cause is **flaky** or a real regression.
            3. Fix the root cause — never skip or disable a test.
            4. Open a PR with a one-paragraph summary.

            > Stop and ask if the fix would need a new dependency.

            ```sh
            cd DevinKit && swift test
            ```
            """,
            macro: "!fixci",
            accessType: .org,
            updatedAt: Date(timeIntervalSince1970: 1_756_850_000)
        ),
        Playbook(
            playbookID: "playbook-mock-release",
            title: "Prepare release notes",
            body: """
            Collect every merged PR since the last tag and draft `CHANGELOG.md` entries grouped by
            *Added*, *Changed* and *Fixed*. Link each entry to its PR.
            """,
            macro: nil,
            accessType: .enterprise,
            updatedAt: Date(timeIntervalSince1970: 1_756_700_000)
        ),
        Playbook(playbookID: "playbook-mock-empty", title: "Empty template", body: "", macro: "!empty"),
    ]

    static func playbooksJSON() -> Data {
        let items = playbooks.map(playbookJSON)
        return Data(#"{"items":[\#(items.joined(separator: ","))],"end_cursor":null,"has_next_page":false}"#.utf8)
    }

    static func playbookJSON(id: String) -> Data? {
        playbooks.first { $0.playbookID == id }.map { Data(playbookJSON($0).utf8) }
    }

    private static func playbookJSON(_ playbook: Playbook) -> String {
        let accessType = playbook.accessType?.rawValue ?? "team"
        let body = (try? JSONSerialization.data(withJSONObject: [playbook.body])).flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
        let macro = playbook.macro.map { "\"\($0)\"" } ?? "null"
        let updated = Int(playbook.updatedAt?.timeIntervalSince1970 ?? 1_756_000_000)
        return #"{"playbook_id":"\#(playbook.playbookID)","title":"\#(playbook.title)","body":\#(body),"macro":\#(macro),"created_by":"user-mock","updated_by":"user-mock","created_at":1756000000,"updated_at":\#(updated),"access_type":"\#(accessType)","org_id":"org-mock","structured_output_schema":null}"#
    }
}
#endif
