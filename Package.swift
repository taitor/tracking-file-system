// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "TrackingFileSystem",
  products: [
    .library(
      name: "TrackingFileSystem",
      targets: ["TrackingFileSystem"]
    ),
  ],
  dependencies: [],
  targets: [
    .target(
      name: "TrackingFileSystem",
      dependencies: []
    ),
    .testTarget(
      name: "TrackingFileSystemTests",
      dependencies: ["TrackingFileSystem"]
    ),
  ]
)
