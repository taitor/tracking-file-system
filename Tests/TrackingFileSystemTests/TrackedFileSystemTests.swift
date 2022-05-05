@testable import TrackingFileSystem
import XCTest

class TrackingFileSystemTests: XCTestCase {
  private let fileManager = FileManager.default
  private let testDirectoryUrl = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("TrackingFileSystemTests")

  override func setUp() {
    super.setUp()
    do {
      if fileManager.fileExists(atPath: testDirectoryUrl.path) {
        try fileManager.removeItem(at: testDirectoryUrl)
      }
      try fileManager.createDirectory(
        at: testDirectoryUrl,
        withIntermediateDirectories: false
      )
    } catch {
      XCTFail("Failed to set up.")
    }
  }

  override func tearDown() {
    do {
      try fileManager.removeItem(at: testDirectoryUrl)
    } catch {
      XCTFail("Failed to tear down.")
    }
    super.tearDown()
  }

  func testInit_failedWithHttpUrl() throws {
    try XCTAssertThrowsError(TrackingFileSystem(tracking: URL(string: "http://example.com")!))
  }

  func testContentsOfDirectory() throws {
    fileManager.createFile(
      atPath: testDirectoryUrl.appendingPathComponent("foo.data").path,
      contents: nil
    )

    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    let contents = try fileSystem.contentsOfDirectory(
      at: fileSystem.rootTrackedUrl,
      includingPropertiesForKeys: nil,
      options: .init()
    )
    XCTAssertEqual(contents.count, 1)
    try XCTAssertEqual(
      contents[0].getCurrentUrl().standardizedFileURL,
      testDirectoryUrl.appendingPathComponent("foo.data").standardizedFileURL
    )
    try XCTAssertEqual(
      fileSystem.contentsOfDirectory(
        at: fileSystem.rootTrackedUrl,
        includingPropertiesForKeys: nil
      ),
      contents
    )

    try fileManager.createDirectory(
      at: testDirectoryUrl.appendingPathComponent("bar"),
      withIntermediateDirectories: false
    )
    fileManager.createFile(
      atPath: testDirectoryUrl
        .appendingPathComponent("bar")
        .appendingPathComponent("baz.data")
        .path,
      contents: nil
    )
    let contents2 = try fileSystem.contentsOfDirectory(
      at: fileSystem.rootTrackedUrl,
      includingPropertiesForKeys: nil
    )
    XCTAssertEqual(contents2.count, 2)
    XCTAssertTrue(contents2.contains(contents[0]))
    for content in contents2 {
      if content == contents[0] {
        try XCTAssertThrowsError(fileSystem.contentsOfDirectory(
          at: content,
          includingPropertiesForKeys: nil
        ))
      } else {
        try XCTAssertEqual(
          content.getCurrentUrl().standardizedFileURL,
          testDirectoryUrl.appendingPathComponent("bar").standardizedFileURL
        )
        let contents3 = try fileSystem.contentsOfDirectory(
          at: content,
          includingPropertiesForKeys: nil
        )
        XCTAssertEqual(contents3.count, 1)
        try XCTAssertEqual(
          contents3[0].getCurrentUrl().standardizedFileURL,
          testDirectoryUrl.appendingPathComponent("bar")
            .appendingPathComponent("baz.data")
            .standardizedFileURL
        )
      }
    }

    XCTAssertEqual(observer.didStartTrackingArguments, [
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "foo.data")!),
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "bar")!),
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "bar/baz.data")!),
    ])
  }

  func testCreateDirectory() throws {
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    let shallowDirectory = testDirectoryUrl.appendingPathComponent("shallow")
    let shallowTrackedUrl = try fileSystem.createDirectory(
      at: shallowDirectory,
      withIntermediateDirectories: false
    )
    XCTAssertEqual(shallowTrackedUrl, fileSystem.getTrackedUrl(atPath: "shallow"))

    let deepDirectory = testDirectoryUrl.appendingPathComponent("this/is/deep")
    try XCTAssertThrowsError(fileSystem.createDirectory(
      at: deepDirectory,
      withIntermediateDirectories: false
    ))
    let deepTrackedUrl = try fileSystem.createDirectory(
      at: deepDirectory,
      withIntermediateDirectories: true
    )
    XCTAssertEqual(deepTrackedUrl, fileSystem.getTrackedUrl(atPath: "this/is/deep"))

    XCTAssertEqual(observer.didStartTrackingArguments, [
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "shallow")!),
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "this")!),
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "this/is")!),
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "this/is/deep")!),
    ])
  }

  /**
   * Create some directories and files in testDirectoryUrl for testing
   * /
   * - foo/
   *  - bar/
   *    - baz/
   *      - qux.data
   */
  private func prepareItems() throws {
    let srcUrl = testDirectoryUrl.appendingPathComponent("foo")
      .appendingPathComponent("bar")
      .appendingPathComponent("baz")
    try fileManager.createDirectory(
      at: srcUrl,
      withIntermediateDirectories: true
    )

    // Create a file at /foo/bar/baz/qux.data
    fileManager.createFile(
      atPath: srcUrl.appendingPathComponent("qux.data").path,
      contents: nil
    )
  }

  func testMoveItem_move() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    guard
      let srcTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz"),
      let dataTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz/qux.data")
    else {
      XCTFail()
      return
    }

    try fileSystem.moveItem(at: srcTrackedUrl, to: testDirectoryUrl.appendingPathComponent("quux"))

    XCTAssertFalse(fileManager.fileExists(atPath: "foo/bar/baz"))
    XCTAssertFalse(fileManager.fileExists(atPath: "foo/bar/baz/qux.data"))
    try XCTAssertEqual(
      srcTrackedUrl.getCurrentUrl().standardizedFileURL,
      testDirectoryUrl.appendingPathComponent("quux").standardizedFileURL
    )
    try XCTAssertEqual(
      dataTrackedUrl.getCurrentUrl().standardizedFileURL,
      testDirectoryUrl
        .appendingPathComponent("quux")
        .appendingPathComponent("qux.data")
        .standardizedFileURL
    )
    XCTAssertEqual(
      srcTrackedUrl,
      fileSystem.getTrackedUrl(atPath: "quux")
    )
    XCTAssertEqual(
      dataTrackedUrl,
      fileSystem.getTrackedUrl(atPath: "quux/qux.data")
    )

    XCTAssertEqual(observer.willMoveArguments, [
      .init(
        fileSystem: fileSystem,
        trackedUrl: srcTrackedUrl,
        srcUrl: testDirectoryUrl.appendingPathComponent("foo/bar/baz").path,
        dstUrl: testDirectoryUrl.appendingPathComponent("quux").path
      ),
    ])
  }

  func testMoveItem_rename() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    guard
      let srcTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz"),
      let dataTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz/qux.data")
    else {
      XCTFail()
      return
    }

    try fileSystem.moveItem(at: srcTrackedUrl, to: testDirectoryUrl.appendingPathComponent("foo/bar/quux"))

    XCTAssertFalse(fileManager.fileExists(atPath: "foo/bar/baz"))
    XCTAssertFalse(fileManager.fileExists(atPath: "foo/bar/baz/qux.data"))
    try XCTAssertEqual(
      srcTrackedUrl.getCurrentUrl().standardizedFileURL,
      testDirectoryUrl
        .appendingPathComponent("foo")
        .appendingPathComponent("bar")
        .appendingPathComponent("quux")
        .standardizedFileURL
    )
    try XCTAssertEqual(
      dataTrackedUrl.getCurrentUrl().standardizedFileURL,
      testDirectoryUrl
        .appendingPathComponent("foo")
        .appendingPathComponent("bar")
        .appendingPathComponent("quux")
        .appendingPathComponent("qux.data")
        .standardizedFileURL
    )
    XCTAssertEqual(
      srcTrackedUrl,
      fileSystem.getTrackedUrl(atPath: "foo/bar/quux")
    )
    XCTAssertEqual(
      dataTrackedUrl,
      fileSystem.getTrackedUrl(atPath: "foo/bar/quux/qux.data")
    )

    XCTAssertEqual(observer.willMoveArguments, [
      .init(
        fileSystem: fileSystem,
        trackedUrl: srcTrackedUrl,
        srcUrl: testDirectoryUrl.appendingPathComponent("foo/bar/baz").path,
        dstUrl: testDirectoryUrl.appendingPathComponent("foo/bar/quux").path
      ),
    ])
  }

  func testMoveItem_movingRootShouldFail() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    try XCTAssertThrowsError(fileSystem.moveItem(
      at: fileSystem.rootTrackedUrl,
      to: testDirectoryUrl.appendingPathComponent("quux")
    ))

    XCTAssertEqual(observer.willMoveArguments, [])
  }

  func testMoveItem_failBecauseSameNameExists() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    guard let srcTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz") else {
      XCTFail()
      return
    }

    let srcUrl = try srcTrackedUrl.getCurrentUrl()

    try XCTAssertThrowsError(fileSystem.moveItem(
      at: srcTrackedUrl,
      to: testDirectoryUrl.appendingPathComponent("foo")
    ))
    try XCTAssertEqual(
      srcTrackedUrl.getCurrentUrl().standardizedFileURL,
      srcUrl.standardizedFileURL
    )

    XCTAssertEqual(observer.willMoveArguments, [])
  }

  func testMoveItem_movingToSelfShouldFail() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    guard let srcTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz") else {
      XCTFail()
      return
    }

    let srcUrl = try srcTrackedUrl.getCurrentUrl()

    try XCTAssertThrowsError(fileSystem.moveItem(
      at: srcTrackedUrl,
      to: testDirectoryUrl.appendingPathComponent("foo")
        .appendingPathComponent("bar")
    ))
    try XCTAssertEqual(
      srcTrackedUrl.getCurrentUrl().standardizedFileURL,
      srcUrl.standardizedFileURL
    )

    XCTAssertEqual(observer.willMoveArguments, [])
  }

  func testMoveItem_failBecauseDestinationIsDescendant() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    guard let srcTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz") else {
      XCTFail()
      return
    }

    let srcUrl = try srcTrackedUrl.getCurrentUrl()

    try XCTAssertThrowsError(fileSystem.moveItem(
      at: srcTrackedUrl,
      to: srcUrl.appendingPathComponent("quux")
    ))
    try XCTAssertEqual(
      srcTrackedUrl.getCurrentUrl().standardizedFileURL,
      srcUrl.standardizedFileURL
    )

    XCTAssertEqual(observer.willMoveArguments, [])
  }

  func testCopyItem_copyFile() throws {
    try prepareItems()

    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    let copyTrackedUrl = try fileSystem.copyItem(
      at: fileSystem.rootUrl.appendingPathComponent("foo/bar/baz/qux.data"),
      to: fileSystem.rootUrl.appendingPathComponent("quux.data")
    )
    try XCTAssertEqual(copyTrackedUrl.getCurrentUrl(), testDirectoryUrl.appendingPathComponent("quux.data"))

    XCTAssertEqual(observer.didStartTrackingArguments, [
      .init(fileSystem: fileSystem, trackedUrl: copyTrackedUrl),
    ])
  }

  func testCopyItem_copyDirectory() throws {
    try prepareItems()

    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    let copyTrackedUrl = try fileSystem.copyItem(
      at: fileSystem.rootUrl.appendingPathComponent("foo"),
      to: fileSystem.rootUrl.appendingPathComponent("quux")
    )
    try XCTAssertEqual(copyTrackedUrl.getCurrentUrl(), testDirectoryUrl.appendingPathComponent("quux"))
    let dataTrackedUrl = fileSystem.getTrackedUrl(atPath: "quux/bar/baz/qux.data")

    XCTAssertEqual(observer.didStartTrackingArguments, [
      .init(fileSystem: fileSystem, trackedUrl: copyTrackedUrl),
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "quux/bar")!),
      .init(fileSystem: fileSystem, trackedUrl: fileSystem.getTrackedUrl(atPath: "quux/bar/baz")!),
      .init(fileSystem: fileSystem, trackedUrl: dataTrackedUrl!),
    ])
  }

  func testCopyItem_copyingToRootShouldFail() throws {
    try prepareItems()

    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    try XCTAssertThrowsError(fileSystem.copyItem(
      at: fileSystem.rootUrl.appendingPathComponent("foo/bar/baz/qux.data"),
      to: fileSystem.rootUrl
    ))

    XCTAssertEqual(observer.didStartTrackingArguments, [])
  }

  func testCopyItem_copyingToOutsideShouldFail() throws {
    try prepareItems()

    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    try XCTAssertThrowsError(fileSystem.copyItem(
      at: fileSystem.rootUrl.appendingPathComponent("foo/bar/baz/qux.data"),
      to: fileSystem.rootUrl.appendingPathComponent("..")
    ))

    XCTAssertEqual(observer.didStartTrackingArguments, [])
  }

  func testRemoveItem_removeDirectory() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    guard
      let srcTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz"),
      let dataTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz/qux.data")
    else {
      XCTFail()
      return
    }

    try fileSystem.removeItem(at: srcTrackedUrl)
    try XCTAssertThrowsError(srcTrackedUrl.getCurrentUrl())
    try XCTAssertThrowsError(dataTrackedUrl.getCurrentUrl())

    XCTAssertEqual(observer.willRemoveArguments, [
      .init(fileSystem: fileSystem, trackedUrl: srcTrackedUrl),
    ])
  }

  func testRemoveItem_removeFile() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    guard
      let srcTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz"),
      let dataTrackedUrl = fileSystem.getTrackedUrl(atPath: "foo/bar/baz/qux.data")
    else {
      XCTFail()
      return
    }

    try fileSystem.removeItem(at: dataTrackedUrl)
    try XCTAssertNoThrow(srcTrackedUrl.getCurrentUrl())
    try XCTAssertThrowsError(dataTrackedUrl.getCurrentUrl())

    XCTAssertEqual(observer.willRemoveArguments, [
      .init(fileSystem: fileSystem, trackedUrl: dataTrackedUrl),
    ])
  }

  func testMoveItem_removingRootShouldFail() throws {
    try prepareItems()
    let fileSystem = try TrackingFileSystem(tracking: testDirectoryUrl)
    let observer = Observer()
    fileSystem.addObserver(observer)

    try XCTAssertThrowsError(fileSystem.removeItem(
      at: fileSystem.rootTrackedUrl
    ))

    XCTAssertEqual(observer.willRemoveArguments, [])
  }

  func testOwns() throws {
    try prepareItems()
    let fileSystem1 = try TrackingFileSystem(tracking: testDirectoryUrl)
    let fileSystem2 = try TrackingFileSystem(tracking: testDirectoryUrl.appendingPathComponent("foo"))
    XCTAssertTrue(fileSystem1.owns(trackedUrl: fileSystem1.rootTrackedUrl))
    XCTAssertTrue(fileSystem1.owns(trackedUrl: fileSystem1.getTrackedUrl(atPath: "foo")!))
    XCTAssertFalse(fileSystem1.owns(trackedUrl: fileSystem2.rootTrackedUrl))
  }
}

extension TrackingFileSystem {
  func getTrackedUrl(atPath path: String) -> TrackedURL? {
    getTrackedUrl(at: rootUrl.appendingPathComponent(path))
  }
}

extension TrackingFileSystem: Equatable {
  public static func == (_ lhs: TrackingFileSystem, _ rhs: TrackingFileSystem) -> Bool {
    lhs === rhs
  }
}

class Observer: TrackingFileSystemObserver {
  struct DidStartTracking: Equatable {
    let fileSystem: TrackingFileSystem
    let trackedUrl: TrackedURL
  }

  var didStartTrackingArguments: [DidStartTracking] = []
  struct WillMove: Equatable {
    let fileSystem: TrackingFileSystem
    let trackedUrl: TrackedURL
    let srcUrl: String
    let dstUrl: String
  }

  var willMoveArguments: [WillMove] = []
  struct WillRemove: Equatable {
    let fileSystem: TrackingFileSystem
    let trackedUrl: TrackedURL
  }

  var willRemoveArguments: [WillRemove] = []

  func trackingFileSystem(_ fileSystem: TrackingFileSystem, didStartTracking trackedUrl: TrackedURL) {
    didStartTrackingArguments.append(.init(fileSystem: fileSystem, trackedUrl: trackedUrl))
  }

  func trackingFileSystem(_ fileSystem: TrackingFileSystem, willMove trackedUrl: TrackedURL, from srcUrl: URL, to dstUrl: URL) {
    willMoveArguments.append(.init(fileSystem: fileSystem, trackedUrl: trackedUrl, srcUrl: srcUrl.path, dstUrl: dstUrl.path))
  }

  func trackingFileSystem(_ fileSystem: TrackingFileSystem, willRemove trackedUrl: TrackedURL) {
    willRemoveArguments.append(.init(fileSystem: fileSystem, trackedUrl: trackedUrl))
  }
}
