# Tracking File System

This package enables to track the identities of file system items when they are moved around the file system.

## Usage

```swift
import Foundation
import TrackingFileSystem

let rootUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Demo")

/**
 * Assuming Demo directory has the following structure:
 * /
 * - foo/
 *  - bar.txt
 * - baz/
 */
let fileSystem = try TrackingFileSystem(tracking: rootUrl)
let fileTrackedUrl = fileSystem.getTrackedUrl(at: rootUrl.appendingPathComponent("foo/bar.txt"))!

print(try fileTrackedUrl.getCurrentUrl()) // /foo/bar.txt

try fileSystem.moveItem(
  at: fileTrackedUrl,
  to: rootUrl.appendingPathComponent("baz/qux.txt")
)

print(try fileTrackedUrl.getCurrentUrl()) // /baz/qux.txt

let dstTrackedUrl = fileSystem.getTrackedUrl(at: rootUrl.appendingPathComponent("foo/bar.txt"))!
print(fileTrackedUrl === dstTrackedUrl) // true
```
