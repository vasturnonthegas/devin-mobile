import Foundation
import SwiftUI

/// Block-level structure of a markdown message, built from Foundation's CommonMark parser.
///
/// `Text(AttributedString)` flattens block structure (code blocks lose their layout, lists lose their
/// bullets), so the runs of a `.full`-syntax `AttributedString` are regrouped here by their
/// `presentationIntent` into a tree that `MarkdownView` lays out block by block. No third-party parser.
struct MarkdownDocument: Equatable, Sendable {
    let blocks: [MarkdownBlock]

    init(markdown: String) {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.allowsExtendedAttributes = true
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            blocks = [.paragraph(id: 0, AttributedString(markdown))]
            return
        }
        blocks = BlockTreeBuilder(parsed).blocks
    }

    /// Roughly one bubble-height's worth of body text; longer messages start collapsed.
    static func isLong(_ markdown: String) -> Bool {
        markdown.count > 1_200 || markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count > 14
    }
}

indirect enum MarkdownBlock: Identifiable, Equatable, Sendable {
    case paragraph(id: Int, AttributedString)
    case heading(id: Int, level: Int, AttributedString)
    case codeBlock(id: Int, language: String?, code: String)
    case list(id: Int, ordered: Bool, items: [MarkdownListItem])
    case blockQuote(id: Int, [MarkdownBlock])
    case table(id: Int, header: [AttributedString], rows: [[AttributedString]])
    case thematicBreak(id: Int)

    var id: Int {
        switch self {
        case .paragraph(let id, _), .heading(let id, _, _), .codeBlock(let id, _, _), .list(let id, _, _),
             .blockQuote(let id, _), .table(let id, _, _), .thematicBreak(let id):
            id
        }
    }
}

struct MarkdownListItem: Identifiable, Equatable, Sendable {
    let id: Int
    let ordinal: Int
    let blocks: [MarkdownBlock]
}

// MARK: - Run regrouping

// Explicit attribute keys: dynamic-member access forms non-Sendable key paths and warns under
// strict concurrency.
private typealias PresentationIntentKey = AttributeScopes.FoundationAttributes.PresentationIntentAttribute
private typealias InlineIntentKey = AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute
private typealias BackgroundColorKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

private final class IntentNode {
    let id: Int
    let kind: PresentationIntent.Kind?
    var text = AttributedString()
    var children: [IntentNode] = []

    init(id: Int, kind: PresentationIntent.Kind?) {
        self.id = id
        self.kind = kind
    }
}

private struct BlockTreeBuilder {
    let blocks: [MarkdownBlock]

    init(_ source: AttributedString) {
        let root = IntentNode(id: -1, kind: nil)
        var syntheticID = -2
        for run in source.runs {
            // Components are innermost-first; walk outermost-first so nesting mirrors the document.
            let components = (run[PresentationIntentKey.self]?.components ?? []).reversed()
            var node = root
            for component in components {
                if let last = node.children.last, last.id == component.identity {
                    node = last
                } else {
                    let child = IntentNode(id: component.identity, kind: component.kind)
                    node.children.append(child)
                    node = child
                }
            }
            if node === root {
                // Text outside any block (should not happen with `.full`) gets its own paragraph.
                if let last = root.children.last, last.kind == nil, last.id < -1 {
                    node = last
                } else {
                    let child = IntentNode(id: syntheticID, kind: nil)
                    syntheticID -= 1
                    root.children.append(child)
                    node = child
                }
            }
            node.text.append(Self.inline(source[run.range], run: run))
        }
        blocks = Self.convert(root.children)
    }

    /// Strips the block-level intent (SwiftUI would ignore it anyway) and turns soft breaks into
    /// real newlines, so a chat message written line-by-line keeps its line structure like the web app.
    private static func inline(_ slice: AttributedSubstring, run: AttributedString.Runs.Run) -> AttributedString {
        var piece = AttributedString(slice)
        piece[PresentationIntentKey.self] = nil
        if let intent = run[InlineIntentKey.self] {
            if intent.contains(.softBreak) || intent.contains(.lineBreak) {
                piece.characters.replaceSubrange(piece.startIndex..<piece.endIndex, with: "\n")
                piece[InlineIntentKey.self] = nil
            }
            if intent.contains(.code) {
                piece[BackgroundColorKey.self] = Color.primary.opacity(0.08)
            }
        }
        return piece
    }

    private static func convert(_ nodes: [IntentNode]) -> [MarkdownBlock] {
        nodes.compactMap { node -> MarkdownBlock? in
            switch node.kind {
            case .paragraph, nil:
                return .paragraph(id: node.id, node.text)
            case .header(let level):
                return .heading(id: node.id, level: level, node.text)
            case .codeBlock(let languageHint):
                var code = String(node.text.characters)
                while code.last?.isNewline == true { code.removeLast() }
                let language = languageHint?.trimmingCharacters(in: .whitespaces)
                return .codeBlock(id: node.id, language: language?.isEmpty == false ? language : nil, code: code)
            case .orderedList, .unorderedList:
                let items = node.children.map { item in
                    var ordinal = 0
                    if case .listItem(let n) = item.kind { ordinal = n }
                    return MarkdownListItem(id: item.id, ordinal: ordinal, blocks: convert(item.children))
                }
                return .list(id: node.id, ordered: node.kind == .orderedList, items: items)
            case .blockQuote:
                return .blockQuote(id: node.id, convert(node.children))
            case .table:
                var header: [AttributedString] = []
                var rows: [[AttributedString]] = []
                for row in node.children {
                    let cells = row.children.map(\.text)
                    if row.kind == .tableHeaderRow { header = cells } else { rows.append(cells) }
                }
                return .table(id: node.id, header: header, rows: rows)
            case .thematicBreak:
                return .thematicBreak(id: node.id)
            case .listItem, .tableHeaderRow, .tableRow, .tableCell:
                // Only reachable when the parent was not a list/table; flatten to keep the text visible.
                return .paragraph(id: node.id, flattened(node))
            @unknown default:
                return .paragraph(id: node.id, flattened(node))
            }
        }
    }

    private static func flattened(_ node: IntentNode) -> AttributedString {
        node.children.reduce(into: node.text) { result, child in
            if !result.characters.isEmpty { result.append(AttributedString("\n")) }
            result.append(flattened(child))
        }
    }
}
