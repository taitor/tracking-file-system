public struct Weak<T: AnyObject> {
  public weak var value: T?

  public init(value: T?) {
    self.value = value
  }
}
