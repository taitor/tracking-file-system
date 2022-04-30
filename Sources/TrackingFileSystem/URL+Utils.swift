import Foundation

extension URL {
  func isAncestorFileUrl(of url: URL) -> Bool {
    guard isFileURL, url.isFileURL else { return false }

    let components = pathComponents
    return components == Array(url.pathComponents.prefix(components.count))
  }

  func pathComponents(relativeTo url: URL) -> [String] {
    var copy = url
    var components = [String]()

    while !copy.isAncestorFileUrl(of: self) {
      copy = copy.deletingLastPathComponent()
      components.append("..")
    }

    let pathComponents = pathComponents

    components.append(contentsOf: pathComponents.suffix(pathComponents.count - copy.pathComponents.count))

    return components
  }
}
