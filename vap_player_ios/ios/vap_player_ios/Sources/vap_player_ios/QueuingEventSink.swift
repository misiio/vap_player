import Foundation

/// An event sink that queues events until a downstream delegate attaches,
/// so events emitted before Dart subscribes are not lost.
final class QueuingEventSink<T> {
  private var delegate: PigeonEventSink<T>?
  private var queue: [Any] = []
  private var done = false

  private struct EndOfStream {}

  func setDelegate(_ delegate: PigeonEventSink<T>?) {
    self.delegate = delegate
    maybeFlush()
  }

  func endOfStream() {
    enqueue(EndOfStream())
    maybeFlush()
    done = true
  }

  func success(_ event: T) {
    enqueue(event)
    maybeFlush()
  }

  private func enqueue(_ event: Any) {
    if done { return }
    queue.append(event)
  }

  private func maybeFlush() {
    guard let delegate = delegate else { return }
    for event in queue {
      if event is EndOfStream {
        delegate.endOfStream()
      } else {
        delegate.success(event as! T)
      }
    }
    queue.removeAll()
  }
}
