import AppKit
import SwiftUI

/// Generic Liquid Glass segmented control (2–3 options).
///
/// On macOS 26+: one static `.regular` glass capsule track with a gray
/// thumb sliding between segments via matchedGeometry. The thumb is
/// deliberately NOT glass: two overlapping glass shapes in one container
/// merge into a blob at rest. Below 26: a native NSSegmentedControl with
/// the selection bezel pinned to the same unemphasized gray.
struct GlassSegmentedControl<Selection: Hashable>: View {
    let labels: [String]
    let values: [Selection]
    @Binding var selection: Selection
    var help: String = ""

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassSegmentedTrack(labels: labels, values: values, selection: $selection, help: help)
        } else {
            GraySegmentedBacking(labels: labels, values: values, selection: $selection, help: help)
        }
    }
}

@available(macOS 26.0, *)
private struct GlassSegmentCell: View {
    let title: String
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(selected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                            .matchedGeometryEffect(id: "thumb", in: namespace)
                    }
                }
                // Transparent padding must still hit: default hit-test is
                // text glyphs only.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Equal-width cells: without this each Button hugs its label and
        // the row's trailing area is dead. Outer contentShape makes the
        // full cell rect click. NOTE: maxWidth only — maxHeight:.infinity
        // stretches the thumb capsule into a giant blob.
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

@available(macOS 26.0, *)
private struct GlassSegmentedTrack<Selection: Hashable>: View {
    let labels: [String]
    let values: [Selection]
    @Binding var selection: Selection
    var help: String = ""
    @Namespace private var thumbNS

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(values.indices, id: \.self) { i in
                    GlassSegmentCell(title: labels[i], selected: values[i] == selection,
                                     namespace: thumbNS) {
                        withAnimation(.snappy(duration: 0.25)) { selection = values[i] }
                    }
                }
            }
            .padding(3)
            .glassEffect(.regular, in: .capsule)
        }
        .help(help)
    }
}

/// Pre-26 backing: native segmented control, gray selection bezel.
/// Index-mapped so enum bindings work without Int tags.
private struct GraySegmentedBacking<Selection: Hashable>: NSViewRepresentable {
    let labels: [String]
    let values: [Selection]
    @Binding var selection: Selection
    var help: String = ""

    func makeNSView(context: Context) -> NSSegmentedControl {
        let count = min(labels.count, values.count)
        let c = NSSegmentedControl(
            labels: Array(labels.prefix(count)), trackingMode: .selectOne, target: nil, action: nil)
        c.segmentDistribution = .fillEqually
        c.selectedSegmentBezelColor = .unemphasizedSelectedContentBackgroundColor
        c.target = context.coordinator
        c.action = #selector(Coordinator.changed(_:))
        return c
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        let index = values.firstIndex(of: selection) ?? 0
        if nsView.selectedSegment != index {
            nsView.selectedSegment = index
        }
        nsView.toolTip = help
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(values: values, selection: $selection)
    }

    final class Coordinator: NSObject {
        let values: [Selection]
        var selection: Binding<Selection>
        init(values: [Selection], selection: Binding<Selection>) {
            self.values = values
            self.selection = selection
        }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard values.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = values[sender.selectedSegment]
        }
    }
}
