public enum TrackingFileSystemError: Swift.Error {
  case initError(reason: String)
  case badTrackedURL(reason: String)
  case badURL(reason: String)
}
