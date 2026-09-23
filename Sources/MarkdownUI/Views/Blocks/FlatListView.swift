import SwiftUI

/// Renders a bulleted or numbered list, including every list nested inside it, as a single flat
/// sequence of rows.
///
/// Upstream MarkdownUI renders a nested list inside the label of its parent item, so every level
/// adds another `BlockSequence`, another baseline-aligned `Label`, and another round of margin
/// preferences. Resolving an item's first baseline then has to lay out everything nested under it,
/// and the cost roughly doubles per level: six levels froze the main thread on iOS 26, and three
/// still took seconds.
///
/// Here each row only aligns against its own content, which never contains a list, so layout is
/// linear in the number of items however deep they are nested. The indentation of a nested row
/// comes from hidden copies of its ancestors' markers, so it matches the nested layout without any
/// measuring. Task lists are not flattened; a task list inside an item renders as ordinary content.
struct FlatListView: View {
  @Environment(\.theme.bulletedListMarker) private var bulletedListMarker
  @Environment(\.theme.numberedListMarker) private var numberedListMarker
  @Environment(\.theme.listItem) private var listItem

  @State private var markerWidths: [Int: CGFloat] = [:]

  private let rows: [FlatListRow]

  init(list: BlockNode, level: Int) {
    self.rows = FlatListRow.rows(for: list, level: level)
  }

  var body: some View {
    BlockSequence(self.rows) { _, row in
      self.listItem.makeBody(
        configuration: .init(
          label: .init(self.label(for: row)),
          content: .init(blocks: row.blocks)
        )
      )
    }
    .onColumnWidthChange { columnWidths in
      self.markerWidths = columnWidths
    }
  }

  private func label(for row: FlatListRow) -> some View {
    // Matches the iOS title-and-icon `Label` that upstream used: the marker is centered on the
    // first line of the item's text, 8pt from it. Resolving the first line only reaches into this
    // row's own blocks, which never contain a list, so it stays cheap.
    HStack(alignment: .centerOfFirstLine, spacing: 8) {
      ForEach(row.ancestors, id: \.self) { ancestor in
        self.marker(for: ancestor, measuresWidth: false)
          .hidden()
      }

      self.marker(for: row.marker, measuresWidth: true)
        .opacity(row.isContinuation ? 0 : 1)

      BlockSequence(row.blocks)
        .environment(\.listLevel, row.marker.level)
    }
  }

  @ViewBuilder
  private func marker(for marker: FlatListRow.Marker, measuresWidth: Bool) -> some View {
    let style = marker.isNumbered ? self.numberedListMarker : self.bulletedListMarker
    let markerView = style
      .makeBody(configuration: .init(listLevel: marker.level, itemNumber: marker.number))
      .textStyleFont()

    // Numbered markers share the width of the widest marker in their own list, as upstream does,
    // so the numbers stay right-aligned. Bullets keep their natural width.
    if marker.isNumbered {
      if measuresWidth {
        markerView
          .readWidth(column: marker.listID)
          .frame(width: self.markerWidths[marker.listID], alignment: .trailing)
      } else {
        markerView
          .frame(width: self.markerWidths[marker.listID], alignment: .trailing)
      }
    } else {
      markerView
    }
  }
}

extension VerticalAlignment {
  private enum CenterOfFirstLine: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
      let heightAfterFirstLine = context[.lastTextBaseline] - context[.firstTextBaseline]
      let heightOfFirstLine = context.height - heightAfterFirstLine
      return heightOfFirstLine / 2
    }
  }

  /// The vertical center of a view's first line of text.
  static let centerOfFirstLine = Self(CenterOfFirstLine.self)
}

/// One rendered line of a flattened list: an item, or the part of an item that follows a list
/// nested inside it.
struct FlatListRow: Hashable {
  struct Marker: Hashable {
    /// Identifies the list this marker belongs to, unique within one flattened list.
    let listID: Int
    let isNumbered: Bool
    /// The one-based list level, as ``ListMarkerConfiguration/listLevel`` expects.
    let level: Int
    let number: Int
  }

  /// The markers of every item this row is nested under, outermost first.
  let ancestors: [Marker]
  let marker: Marker
  /// Whether this row continues an item after a nested list, and so shows no marker of its own.
  let isContinuation: Bool
  /// The item's content, with any nested bulleted or numbered lists removed.
  let blocks: [BlockNode]

  /// Flattens a bulleted or numbered list into rows in reading order.
  ///
  /// - Parameters:
  ///   - list: The list to flatten. Any other block produces no rows.
  ///   - level: The one-based list level of the list's own items.
  static func rows(for list: BlockNode, level: Int) -> [FlatListRow] {
    var rows: [FlatListRow] = []
    var nextListID = 0
    self.append(list, level: level, ancestors: [], nextListID: &nextListID, to: &rows)
    return rows
  }

  private static func append(
    _ list: BlockNode,
    level: Int,
    ancestors: [Marker],
    nextListID: inout Int,
    to rows: inout [FlatListRow]
  ) {
    let isNumbered: Bool
    let start: Int
    let items: [RawListItem]

    switch list {
    case .bulletedList(_, let listItems):
      isNumbered = false
      start = 1
      items = listItems
    case .numberedList(_, let listStart, let listItems):
      isNumbered = true
      start = listStart
      items = listItems
    default:
      return
    }

    let listID = nextListID
    nextListID += 1

    for (index, item) in items.enumerated() {
      let marker = Marker(listID: listID, isNumbered: isNumbered, level: level, number: start + index)
      var pendingBlocks: [BlockNode] = []
      var emittedMarker = false

      func flush() {
        rows.append(
          FlatListRow(
            ancestors: ancestors,
            marker: marker,
            isContinuation: emittedMarker,
            blocks: pendingBlocks
          )
        )
        emittedMarker = true
        pendingBlocks = []
      }

      for child in item.children {
        switch child {
        case .bulletedList, .numberedList:
          // The item's own row always comes first, even when the item opens with a nested list.
          if !emittedMarker || !pendingBlocks.isEmpty {
            flush()
          }
          self.append(
            child,
            level: level + 1,
            ancestors: ancestors + [marker],
            nextListID: &nextListID,
            to: &rows
          )
        default:
          pendingBlocks.append(child)
        }
      }

      if !emittedMarker || !pendingBlocks.isEmpty {
        flush()
      }
    }
  }
}
