import Foundation

public final class TrackingFileSystem {
  private let fileManager: FileManager
  public let rootUrl: URL
  public let rootTrackedUrl: TrackedURL
  private var observers: [WeakTrackingFileSystemObserver] = []

  /**
   Initialize a `TrackingFileSystem` which tracks items under the given `URL`.

   - Throws: `TrackingFileSystemError.initError` when the initialization failed.
   - Parameter rootUrl: Items under this `URL` are tracked by the returned `TrackingFileSystem`.
   This `URL` must be a file `URL` to an existing directory.
   - Parameter fileManager: A `FileManager` used by the returned `TrackingFileSystem`.
   - Returns: A new `TrackingFileSystem` instance.
   */
  public init(
    tracking rootUrl: URL,
    fileManager: FileManager = FileManager()
  ) throws {
    self.fileManager = fileManager
    var isDirectory = ObjCBool(false)
    guard rootUrl.isFileURL,
          fileManager.fileExists(atPath: rootUrl.path, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
      throw TrackingFileSystemError.initError(reason: "rootUrl \"\(rootUrl)\" must be a file URL for an existing directory.")
    }
    self.rootUrl = rootUrl
    rootTrackedUrl = .init(location: .root(rootUrl))
  }

  /**
   Get a `TrackedURL` located at the given `URL` if it exists.

   - Important: The given `URL` must be a descendant of `rootUrl` and to an existing item, otherwise this method return `nil`.
   - Parameter url: A `TrackedURL` at this `URL` is returned.
   - Returns: A `TrackedURL` at `URL` if it exists.
   */
  public func getTrackedUrl(at url: URL) -> TrackedURL? {
    guard rootUrl.isAncestorFileUrl(of: url),
          fileManager.fileExists(atPath: url.path)
    else {
      return nil
    }

    return getOrCreateTrackedUrl(at: url.pathComponents(relativeTo: rootUrl))
  }

  /**
   Perform a shallow search of the given `TrackedURL` and return `TrackedURL`s for the contained items.

   - Parameter trackedUrl: The `TrackedURL` to perform the shallow search in.
    This must be a `TrackedURL` to a directory, otherwise an error is thrown.
   - Parameter keys: Please refer to the `keys` parameter in [`FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`](https://developer.apple.com/documentation/foundation/filemanager/1413768-contentsofdirectory).
   - Parameter mask: Please refer to the `mask` parameter in [`FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`](https://developer.apple.com/documentation/foundation/filemanager/1413768-contentsofdirectory).
   */
  public func contentsOfDirectory(
    at trackedUrl: TrackedURL,
    includingPropertiesForKeys keys: [URLResourceKey]?,
    options mask: FileManager.DirectoryEnumerationOptions = []
  ) throws -> [TrackedURL] {
    let url = try trackedUrl.getCurrentUrl()
    guard owns(trackedUrl: trackedUrl) else {
      throw TrackingFileSystemError.badTrackedURL(
        reason: "\(trackedUrl) is not tracked by this file system."
      )
    }

    let contents = try fileManager.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: keys,
      options: mask
    ).map { url in
      getOrCreateTrackedUrl(on: trackedUrl, at: url.lastPathComponent)
    }

    // Remove any child TrackedURLs which don't exist.
    // This typically happens when items are moved or removed externally.
    trackedUrl.childSet
      .subtracting(contents)
      .forEach { child in
        do {
          let url = try child.getCurrentUrl()
          if !fileManager.fileExists(atPath: url.path) {
            child.dangerouslyRemoveSelf()
          }
        } catch {
          fatalError("\(child), which is a child of \(trackedUrl), is in a bad state.")
        }
      }

    return contents
  }

  /**
   Create a directory with the given attributes at the given `URL`.

   - Important: The given `URL` must be a descendant of `rootUrl`, otherwise this method throws an error.
   - Throws: `TrackingFileSystemError.badURL` when `url` doesn't belong to this `TrackingFileSystem`.
   - Throws: When failed to create a directory at the given `URL`.
   - Parameter url: A file `URL` that specifies the directory to create.
   - Parameter createIntermediates: Please refer to the `createIntermediates` parameter in [`FileManager.createDirectory(at:withIntermediateDirectories:attributes:)`](https://developer.apple.com/documentation/foundation/filemanager/1415371-createdirectory).
   - Parameter attributes: Please refer to the `attributes` parameter in [`FileManager.createDirectory(at:withIntermediateDirectories:attributes:)`](https://developer.apple.com/documentation/foundation/filemanager/1415371-createdirectory).
   - Returns: A `TrackedURL` for the created directory.
   */
  public func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]? = nil
  ) throws -> TrackedURL {
    guard rootUrl.isAncestorFileUrl(of: url) else {
      throw TrackingFileSystemError.badURL(reason: "\(url) doesn't belong to this TrackingFileSystem.")
    }

    try fileManager.createDirectory(
      at: url,
      withIntermediateDirectories: createIntermediates,
      attributes: attributes
    )

    return getOrCreateTrackedUrl(at: url.pathComponents(relativeTo: rootUrl))
  }

  /**
   Move a file or directory at the given `TrackedURL` to a new location.

   - Throws: When either `srcTrackedUrl` or `dstUrl` is either not owned by this `TrackingFileSystem` or the root.
   - Throws: When failed to move the item.
   - Parameter srcTrackedUrl: A `TrackedURL` for the item to move
   - Parameter dstUrl: The new location of the item.
   */
  public func moveItem(at srcTrackedUrl: TrackedURL, to dstUrl: URL) throws {
    guard owns(trackedUrl: srcTrackedUrl) else {
      throw TrackingFileSystemError.badTrackedURL(reason: "\(srcTrackedUrl) doesn't belong to this TrackingFileSystem.")
    }
    guard srcTrackedUrl != rootTrackedUrl else {
      throw TrackingFileSystemError.badTrackedURL(reason: "\(srcTrackedUrl) cannot be moved because this is the root.")
    }
    guard rootUrl.isAncestorFileUrl(of: dstUrl) else {
      throw TrackingFileSystemError.badURL(reason: "\(dstUrl) doesn't belong to this TrackingFileSystem.")
    }

    let srcUrl = try srcTrackedUrl.getCurrentUrl()
    let srcPathComponents = srcUrl.pathComponents(relativeTo: rootUrl)
    let dstPathComponents = dstUrl.pathComponents(relativeTo: rootUrl)
    guard !srcPathComponents.isEmpty else {
      throw TrackingFileSystemError.badTrackedURL(reason: "\(srcTrackedUrl) cannot be moved because this is the root.")
    }

    guard let newPathComponent = dstPathComponents.last else {
      throw TrackingFileSystemError.badURL(reason: "Cannot move to \(dstUrl) because this is the root.")
    }

    try fileManager.moveItem(at: srcUrl, to: dstUrl)

    observers.forEach { $0.trackingFileSystem(self, willMove: srcTrackedUrl, from: srcUrl, to: dstUrl) }
    let dstParent = getOrCreateTrackedUrl(at: dstPathComponents.dropLast())
    srcTrackedUrl.dangerouslyRemoveSelf()
    dstParent.dangerouslyAddChild(srcTrackedUrl, withPathComponent: newPathComponent)
  }

  /**
   Copy a file or directory at the given `TrackedURL` to a new location synchronously.

   - Throws: `TrackingFileSystemError.badURL` when `dstUrl` is either not owned by this `TrackingFileSystem` or the root.
   - Throws: When failed to copy the item.
   - Parameter srcUrl: A `URL` for the item to copy.
   - Parameter dstUrl: A `URL` at which to place the copy.
   - Returns: A new `TrackedURL` for the placed copy.
   */
  public func copyItem(at srcUrl: URL, to dstUrl: URL) throws -> TrackedURL {
    guard rootUrl.isAncestorFileUrl(of: dstUrl) else {
      throw TrackingFileSystemError.badURL(reason: "dstUrl \(dstUrl) doesn't belong to this TrackingFileSystem.")
    }
    let dstPathComponents = dstUrl.pathComponents(relativeTo: rootUrl)
    guard !dstPathComponents.isEmpty else {
      throw TrackingFileSystemError.badURL(reason: "Cannot copy to \(dstUrl) because this is the root.")
    }

    try fileManager.copyItem(at: srcUrl, to: dstUrl)
    return getOrCreateTrackedUrl(at: dstPathComponents)
  }

  /**
   Remove a file or directory at the given `TrackedURL`.

   - Throws: `TrackingFileSystemError.badTrackedURL` when `trackedUrl` is either not owned by this `TrackingFileSystem` or the root.
   - Throws: When failed to remove the item.
   - Parameter trackedUrl: A `TrackedURL` for the item to remove.
   */
  public func removeItem(at trackedUrl: TrackedURL) throws {
    guard owns(trackedUrl: trackedUrl) else {
      throw TrackingFileSystemError.badTrackedURL(reason: "\(trackedUrl) doesn't belong to this TrackingFileSystem.")
    }
    guard trackedUrl != rootTrackedUrl else {
      throw TrackingFileSystemError.badTrackedURL(reason: "\(trackedUrl) cannot be removed because this is the root.")
    }

    try fileManager.removeItem(at: trackedUrl.getCurrentUrl())

    observers.forEach { $0.trackingFileSystem(self, willRemove: trackedUrl) }
    trackedUrl.dangerouslyRemoveSelf()
  }

  /**
   Tells if the given `TrackedURL` belongs to this `TrackingFileSystem`.

   - Parameter trackedUrl: A `TrackedURL` to check if it belongs to this `TrackingFileSystem` .
   - Returns: `true` if the `TrackedURL` belongs to this `TrackingFileSystem`, otherwise `false`.
   */
  public func owns(trackedUrl: TrackedURL) -> Bool {
    trackedUrl.root == rootTrackedUrl
  }

  /**
   Add a `TrackingFileSystemObserver` to this `TrackingFileSystem` if it's not been registered yet.

   Calling this method for the same `TrackingFileSystemObserver` multiple times has no effects.
   - Important: `TrackingFileSystem` doesn't retain `TrackingFileSystemObserver`'s references.
   You must retain them somewhere by yourself.
   - Parameter newObserver: A `TrackingFileSystemObserver` to register.
   */
  public func addObserver(_ newObserver: TrackingFileSystemObserver) {
    if observers.contains(where: { $0.value == nil }) {
      observers.sweep()
    }
    guard !observers.contains(where: { $0.value === newObserver }) else {
      return
    }
    observers.append(.init(value: newObserver))
  }

  /**
   Remove a `TrackingFileSystemObserver` from this `TrackingFileSystem` if it's currently registered.

   Calling this method for the same `TrackingFileSystemObserver` multiple times has no effects.
   - Parameter observer: A `TrackingFileSystemObserver` to remove.
   */
  public func removeObserver(_ observer: TrackingFileSystemObserver) {
    observers.removeAll(where: { $0.value == nil || $0.value === observer })
  }

  /**
   Remove all `TrackingFileSystemObserver`s from this `TrackingFileSystem`.
   */
  public func removeAllObservers() {
    observers.removeAll()
  }

  private func getOrCreateTrackedUrl(
    at relativePathComponents: [String]
  ) -> TrackedURL {
    var trackedUrl = rootTrackedUrl
    for pathComponent in relativePathComponents {
      trackedUrl = getOrCreateTrackedUrl(on: trackedUrl, at: pathComponent)
    }

    return trackedUrl
  }

  private func getOrCreateTrackedUrl(
    on trackedUrl: TrackedURL,
    at pathComponent: String
  ) -> TrackedURL {
    var created = false
    let result = trackedUrl.getOrCreateChild(withPathComponent: pathComponent, created: &created)

    if created {
      observers.forEach { $0.trackingFileSystem(self, didStartTracking: result) }
    }

    return result
  }
}

extension TrackingFileSystem: CustomStringConvertible {
  public var description: String {
    "TrackingFileSystem rootTrackedUrl=\(rootTrackedUrl)"
  }
}

private struct WeakTrackingFileSystemObserver {
  weak var value: TrackingFileSystemObserver?
}

private extension Array where Element == WeakTrackingFileSystemObserver {
  mutating func forEach(_ body: (TrackingFileSystemObserver) throws -> Void) rethrows {
    var shouldSweep = false
    for wrapped in self {
      if let observer = wrapped.value {
        try body(observer)
      } else {
        shouldSweep = true
      }
    }

    if shouldSweep {
      sweep()
    }
  }

  mutating func sweep() {
    removeAll(where: { $0.value == nil })
  }
}
