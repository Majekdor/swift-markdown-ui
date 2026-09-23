import SwiftUI

struct BulletedListView: View {
  @Environment(\.theme.list) private var list
  @Environment(\.listLevel) private var listLevel

  private let isTight: Bool
  private let items: [RawListItem]

  init(isTight: Bool, items: [RawListItem]) {
    self.isTight = isTight
    self.items = items
  }

  var body: some View {
    self.list.makeBody(
      configuration: .init(
        label: .init(self.label),
        content: .init(block: .bulletedList(isTight: self.isTight, items: self.items))
      )
    )
  }

  private var label: some View {
    FlatListView(
      list: .bulletedList(isTight: self.isTight, items: self.items),
      level: self.listLevel + 1
    )
    .environment(\.tightSpacingEnabled, self.isTight)
  }
}
