import Foundation

public protocol TrackingFileSystemObserver: AnyObject {
  /**
   Called when a `TrackingFileSystem` started tracking a new `TrackedURL`.

   - Parameter fileSystem: The `TrackingFileSystem` which started tracking a new `TrackedURL`.
   - Parameter trackedUrl: The `TrackedURL` which the `TrackingFileSystem` started tracking.
   */
  func trackingFileSystem(_ fileSystem: TrackingFileSystem, didStartTracking trackedUrl: TrackedURL)

  /**
   Called when a `TrackingFileSystem` is about to move a `TrackedURL` to a new location.

   This method is called only once for the `TrackedURL` started being moved.
   - Important: When this method is called, the actual item tracked by the `TrackedURL` has already been moved from `srcUrl` to `dstUrl`.
   - Parameter fileSystem: The `TrackingFileSystem` which is about to move a `TrackedURL`.
   - Parameter trackedUrl: The `TrackedURL` to move.
   - Parameter srcUrl: The `URL` where  the`TrackedURL` is currently located.
   - Parameter dstUrl: The `URL` the `TrackedURL` is moving to.
   */
  func trackingFileSystem(_ fileSystem: TrackingFileSystem, willMove trackedUrl: TrackedURL, from srcUrl: URL, to dstUrl: URL)

  /**
   Called when a `TrackingFileSystem` is about to remove a `TrackedURL`.

   - Important: When this method is called, the actual item tracked by the `TrackedURL` has already removed.
   - Parameter fileSystem: The `TrackingFileSystem` which is about to remove a `TrackedURL`.
   - Parameter trackedUrl: The `TrackedURL` to remove.
   */
  func trackingFileSystem(_ fileSystem: TrackingFileSystem, willRemove trackedUrl: TrackedURL)
}
