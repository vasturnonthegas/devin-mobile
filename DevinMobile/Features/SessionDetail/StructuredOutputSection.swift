import SwiftUI
import UIKit
import DevinKit

/// Collapsible tree for `Session.structuredOutput`, shown in the detail header. Copy always
/// yields the whole pretty-printed document, regardless of which nodes are expanded.
struct StructuredOutputSection: View {
    let output: JSONValue

    @State private var isExpanded = false
    @State private var showRaw = false
    @State private var copied = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Picker("View", selection: $showRaw) {
                        Text("Tree").tag(false)
                        Text("JSON").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                    .accessibilityLabel("Structured output view")

                    Spacer()

                    Button {
                        UIPasteboard.general.string = output.prettyPrinted
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .sensoryFeedback(.success, trigger: copied) { _, new in new }
                    .accessibilityLabel("Copy JSON")
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .padding(.top, 6)

                Group {
                    if showRaw {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(output.prettyPrinted)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    } else {
                        JSONTreeNode(key: nil, value: output, depth: 0)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
        } label: {
            Label {
                HStack(spacing: 6) {
                    Text("Structured output")
                    Text(output.scalarDescription)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            } icon: {
                Image(systemName: "curlybraces")
            }
            .font(.subheadline)
        }
    }
}

/// One row of the tree. Containers render as their own disclosure; scalars as `key: value`.
/// Only the root and its direct children start expanded so a large document stays scannable.
private struct JSONTreeNode: View {
    let key: String?
    let value: JSONValue
    let depth: Int

    @State private var isExpanded: Bool

    init(key: String?, value: JSONValue, depth: Int) {
        self.key = key
        self.value = value
        self.depth = depth
        _isExpanded = State(initialValue: depth < 1)
    }

    var body: some View {
        switch value {
        case .object(let members):
            container(isEmpty: members.isEmpty) {
                ForEach(value.sortedMembers, id: \.key) { member in
                    JSONTreeNode(key: member.key, value: member.value, depth: depth + 1)
                }
            }
        case .array(let items):
            container(isEmpty: items.isEmpty) {
                ForEach(Array(items.enumerated()), id: \.offset) { item in
                    JSONTreeNode(key: "\(item.offset)", value: item.element, depth: depth + 1)
                }
            }
        default:
            scalarRow
        }
    }

    private func container<Content: View>(isEmpty: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                guard !isEmpty else { return }
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded && !isEmpty ? 90 : 0))
                        .foregroundStyle(isEmpty ? .quaternary : .tertiary)
                        .frame(width: 12)
                    if let key {
                        Text(key).foregroundStyle(.primary)
                        Text(":").foregroundStyle(.tertiary)
                    }
                    Text(value.scalarDescription).foregroundStyle(.secondary)
                }
                .font(.caption.monospaced())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(isEmpty ? "empty" : isExpanded ? "expanded" : "collapsed")

            if isExpanded && !isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    content()
                }
                .padding(.leading, 16)
            }
        }
    }

    private var scalarRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let key {
                Text(key).foregroundStyle(.primary)
                Text(":").foregroundStyle(.tertiary)
            }
            Text(scalarText)
                .foregroundStyle(scalarColor)
                .textSelection(.enabled)
        }
        .font(.caption.monospaced())
        .padding(.leading, 16)
        .accessibilityElement(children: .combine)
    }

    private var scalarText: String {
        if case .string(let string) = value { return "\"\(string)\"" }
        return value.scalarDescription
    }

    private var scalarColor: Color {
        switch value {
        case .string: .green
        case .number: .blue
        case .bool: .purple
        default: .secondary
        }
    }

    private var accessibilityTitle: String {
        let shape: String
        switch value {
        case .object(let members): shape = "object, \(members.count) keys"
        case .array(let items): shape = "array, \(items.count) items"
        default: shape = value.scalarDescription
        }
        return key.map { "\($0), \(shape)" } ?? shape
    }
}

#Preview {
    ScrollView {
        StructuredOutputSection(output: .object([
            "summary": .string("3 flaky tests found"),
            "confidence": .number(0.85),
            "total": .number(3),
            "has_blockers": .bool(false),
            "owner": .null,
            "issues": .array([
                .object(["file": .string("Tests/LoginTests.swift"), "line": .number(42)]),
            ]),
            "meta": .object([:]),
        ]))
        .padding()
    }
}
