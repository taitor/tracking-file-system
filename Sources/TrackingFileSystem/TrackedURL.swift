import Foundation

public final class TrackedURL {
  enum Location {
    case root(URL)
    case intermediate(parent: WeakTrackedURL, pathComponent: String)
  }

  private(set) var location: Location
  private(set) var childSet: Set<TrackedURL>

  init(location: Location) {
    self.location = location
    childSet = .init()
  }

  var root: TrackedURL? {
    switch location {
    case .root:
      return self
    case let .intermediate(parent, _):
      return parent.value?.root
    }
  }

  /**
   The last path component of this `TrackedURL`.
   */
  public var lastPathComponent: String {
    switch location {
    case let .root(url):
      return url.lastPathComponent
    case let .intermediate(_, pathComponent):
      return pathComponent
    }
  }

  /**
   Get the current `URL` of this `TrackedURL`.

   - Throws: `TrackingFileSystemError.badTrackedURL` when this `TrackedURL` has been already detached from the `TrackingFileSystem`.
   - Returns: The current `URL` of this `TrackedURL`.
   */
  public func getCurrentUrl() throws -> URL {
    switch location {
    case let .root(url):
      return url
    case let .intermediate(parent, pathComponent):
      guard let trackedUrl = parent.value else {
        throw TrackingFileSystemError.badTrackedURL(reason: "This TrackedURL has no parents.")
      }
      return try trackedUrl.getCurrentUrl()
        .appendingPathComponent(pathComponent)
    }
  }

  func getOrCreateChild(
    withPathComponent pathComponent: String,
    created: inout Bool
  ) -> TrackedURL {
    let existing = childSet.first { child in
      guard case let .intermediate(_, pc) = child.location else {
        return false
      }
      return pc == pathComponent
    }
    if let existing = existing {
      created = false

      return existing
    } else {
      let child = TrackedURL(location: .intermediate(
        parent: .init(value: self),
        pathComponent: pathComponent
      ))
      childSet.insert(child)

      created = true

      return child
    }
  }

  func dangerouslyAddChild(
    _ newChild: TrackedURL,
    withPathComponent newPathComponent: String
  ) {
    guard
      case let .intermediate(parent, _) = newChild.location,
      parent.value == nil
    else {
      fatalError("The new child \(newChild) has already had another parent.")
    }
    newChild.location = .intermediate(
      parent: .init(value: self),
      pathComponent: newPathComponent
    )
    childSet.insert(newChild)
  }

  func dangerouslyRemoveSelf() {
    switch location {
    case .root:
      fatalError("The root cannot be removed.")
    case let .intermediate(parent, pathComponent):
      location = .intermediate(parent: .init(value: nil), pathComponent: pathComponent)
      guard let parent = parent.value else {
        return
      }
      parent.childSet = parent.childSet.filter { $0 !== self }
    }
  }
}

extension TrackedURL: CustomStringConvertible {
  public var description: String {
    "TrackedURL location=\(locationDescription)"
  }

  private var locationDescription: String {
    switch location {
    case let .root(url):
      return url.description
    case let .intermediate(parent, pathComponent):
      guard let parent = parent.value else {
        return "<No parent>/\(pathComponent)"
      }
      return "\(parent.locationDescription)/\(pathComponent)"
    }
  }
}

extension TrackedURL: Equatable {
  public static func == (lhs: TrackedURL, rhs: TrackedURL) -> Bool {
    lhs === rhs
  }
}

extension TrackedURL: Hashable {
  public func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }
}

struct WeakTrackedURL {
  weak var value: TrackedURL?
}
