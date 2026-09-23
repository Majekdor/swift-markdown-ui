import Foundation
import XCTest

@testable import MarkdownUI

final class FlatListRowTests: XCTestCase {
  private func paragraph(_ text: String) -> BlockNode {
    .paragraph(content: [.text(text)])
  }

  private func item(_ children: BlockNode...) -> RawListItem {
    RawListItem(children: children)
  }

  func testFlatList() {
    // given
    let list = BlockNode.bulletedList(
      isTight: true,
      items: [item(paragraph("One")), item(paragraph("Two"))]
    )

    // when
    let rows = FlatListRow.rows(for: list, level: 1)

    // then
    XCTAssertEqual(rows.map(\.blocks), [[paragraph("One")], [paragraph("Two")]])
    XCTAssertEqual(rows.map(\.marker.number), [1, 2])
    XCTAssertEqual(rows.map(\.marker.level), [1, 1])
    XCTAssertTrue(rows.allSatisfy { $0.ancestors.isEmpty && !$0.isContinuation })
  }

  func testNestedListsBecomeRowsInReadingOrder() {
    // given
    let list = BlockNode.bulletedList(
      isTight: true,
      items: [
        item(
          paragraph("Parent"),
          .numberedList(
            isTight: true,
            start: 3,
            items: [
              item(
                paragraph("Child"),
                .bulletedList(isTight: true, items: [item(paragraph("Grandchild"))])
              )
            ]
          )
        ),
        item(paragraph("Sibling")),
      ]
    )

    // when
    let rows = FlatListRow.rows(for: list, level: 1)

    // then
    XCTAssertEqual(
      rows.map(\.blocks),
      [[paragraph("Parent")], [paragraph("Child")], [paragraph("Grandchild")], [paragraph("Sibling")]]
    )
    XCTAssertEqual(rows.map(\.marker.level), [1, 2, 3, 1])
    XCTAssertEqual(rows.map(\.marker.isNumbered), [false, true, false, false])
    XCTAssertEqual(rows.map(\.marker.number), [1, 3, 1, 2])
    XCTAssertEqual(rows.map(\.ancestors.count), [0, 1, 2, 0])
    XCTAssertEqual(rows[2].ancestors, [rows[0].marker, rows[1].marker])
  }

  func testEachNestedListGetsItsOwnID() {
    // given
    let list = BlockNode.numberedList(
      isTight: true,
      start: 1,
      items: [
        item(paragraph("A"), .numberedList(isTight: true, start: 1, items: [item(paragraph("A1"))])),
        item(paragraph("B"), .numberedList(isTight: true, start: 1, items: [item(paragraph("B1"))])),
      ]
    )

    // when
    let rows = FlatListRow.rows(for: list, level: 1)

    // then
    // Sibling sublists must not share a marker-width column with each other or their parent.
    XCTAssertEqual(Set(rows.map(\.marker.listID)).count, 3)
    XCTAssertNotEqual(rows[1].marker.listID, rows[3].marker.listID)
  }

  func testContentAfterNestedListContinuesTheItem() {
    // given
    let list = BlockNode.bulletedList(
      isTight: true,
      items: [
        item(
          paragraph("Before"),
          .bulletedList(isTight: true, items: [item(paragraph("Nested"))]),
          paragraph("After")
        )
      ]
    )

    // when
    let rows = FlatListRow.rows(for: list, level: 1)

    // then
    XCTAssertEqual(rows.map(\.blocks), [[paragraph("Before")], [paragraph("Nested")], [paragraph("After")]])
    XCTAssertEqual(rows.map(\.isContinuation), [false, false, true])
    XCTAssertEqual(rows[2].marker, rows[0].marker)
  }

  func testItemThatOpensWithANestedListStillGetsItsOwnRow() {
    // given
    let list = BlockNode.bulletedList(
      isTight: true,
      items: [item(.bulletedList(isTight: true, items: [item(paragraph("Nested"))]))]
    )

    // when
    let rows = FlatListRow.rows(for: list, level: 1)

    // then
    XCTAssertEqual(rows.map(\.blocks), [[], [paragraph("Nested")]])
    XCTAssertEqual(rows.map(\.marker.level), [1, 2])
  }

  func testDeepNestingIsOneRowPerItem() {
    // given
    var list = BlockNode.bulletedList(isTight: true, items: [item(paragraph("Leaf"))])
    for depth in (0..<10).reversed() {
      list = .bulletedList(isTight: true, items: [item(paragraph("Level \(depth)"), list)])
    }

    // when
    let rows = FlatListRow.rows(for: list, level: 1)

    // then
    XCTAssertEqual(rows.count, 11)
    XCTAssertEqual(rows.last?.marker.level, 11)
    XCTAssertEqual(rows.last?.ancestors.count, 10)
  }
}
