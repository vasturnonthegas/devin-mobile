import SwiftUI

/// Renders a `MarkdownDocument` block by block. Inline styling (bold, italic, links, inline code)
/// comes from the `AttributedString` runs; this view only owns block layout.
struct MarkdownView: View {
    let document: MarkdownDocument

    var body: some View {
        MarkdownBlocksView(blocks: document.blocks, depth: 0)
            .textSelection(.enabled)
    }
}

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(_, let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(_, let level, let text):
            Text(text)
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 0)
        case .codeBlock(_, let language, let code):
            CodeBlockView(language: language, code: code)
        case .list(_, let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker(ordered: ordered, ordinal: item.ordinal))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        MarkdownBlocksView(blocks: item.blocks, depth: depth + 1)
                    }
                }
            }
        case .blockQuote(_, let inner):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.secondary)
                    .frame(width: 3)
                MarkdownBlocksView(blocks: inner, depth: depth + 1)
                    .foregroundStyle(.secondary)
            }
        case .table(_, let header, let rows):
            MarkdownTableView(header: header, rows: rows)
        case .thematicBreak:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.bold()
        }
    }

    private func marker(ordered: Bool, ordinal: Int) -> String {
        if ordered { return "\(ordinal)." }
        return depth % 2 == 0 ? "•" : "◦"
    }
}

/// Monospaced, horizontally scrollable code block with a language tag and copy button — the shape
/// Devin's web transcript uses for fenced blocks.
struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.callout.monospaced())
                    .lineSpacing(2)
                    .padding(10)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MarkdownTableView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                if !header.isEmpty {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.subheadline.bold())
                        }
                    }
                    Divider()
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.subheadline)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Bubble body: markdown plus a "Show more" fold for long messages so a wall of text or a big
/// diff does not dominate the transcript.
struct MarkdownMessageBody: View {
    let markdown: String
    /// The bubble background, used to fade out the clipped edge of a collapsed message.
    var fade: AnyShapeStyle = AnyShapeStyle(.background)

    @State private var expanded = false
    @ScaledMetric(relativeTo: .body) private var collapsedHeight: CGFloat = 240

    private var isCollapsible: Bool { MarkdownDocument.isLong(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MarkdownView(document: MarkdownDocumentCache.document(for: markdown))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: isCollapsible && !expanded ? collapsedHeight : nil, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    if isCollapsible && !expanded {
                        Rectangle()
                            .fill(fade)
                            .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                            .frame(height: 48)
                            .allowsHitTesting(false)
                    }
                }

            if isCollapsible {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Label(expanded ? "Show less" : "Show more", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    }
}

/// Parsing is cheap but bubbles re-render on every poll; memoise per message text.
private final class MarkdownDocumentCache: @unchecked Sendable {
    private static let shared = MarkdownDocumentCache()
    private let cache = NSCache<NSString, Entry>()

    private final class Entry {
        let document: MarkdownDocument
        init(_ document: MarkdownDocument) { self.document = document }
    }

    private init() { cache.countLimit = 500 }

    static func document(for markdown: String) -> MarkdownDocument {
        let key = markdown as NSString
        if let hit = shared.cache.object(forKey: key) { return hit.document }
        let document = MarkdownDocument(markdown: markdown)
        shared.cache.setObject(Entry(document), forKey: key)
        return document
    }
}
