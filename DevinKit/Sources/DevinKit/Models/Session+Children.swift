import Foundation

public extension Session {
    var childCount: Int { childSessionIDs?.count ?? 0 }

    var hasChildren: Bool { childCount > 0 }
}
