import Foundation

enum VapNetworkFailureCode {
  static let invalidUrl: Int64 = 1001
  static let httpStatus: Int64 = 1002
  static let sizeExceeded: Int64 = 1003
  static let invalidMedia: Int64 = 1004
  static let networkIo: Int64 = 1005
}

enum VapNetworkPolicy {
  static let minimumDownloadBytes: Int64 = 10 * 1024 * 1024
  static let maxRedirects: Int = 3

  static func maxDownloadBytes(autoEvictionMaxBytes: Int64) -> Int64 {
    return max(minimumDownloadBytes, autoEvictionMaxBytes)
  }

  static func sanitizeURLString(_ source: String) -> String {
    guard
      let components = URLComponents(string: source),
      let scheme = components.scheme?.lowercased(),
      let host = components.host
    else {
      return "<invalid-url>"
    }
    let port = components.port.map { ":\($0)" } ?? ""
    let path = components.percentEncodedPath
    return "\(scheme)://\(host)\(port)\(path)"
  }

  static func hasIsoBmffSignature(fileURL: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
      return false
    }
    defer { try? handle.close() }
    guard
      let bytes = try? handle.read(upToCount: 12),
      bytes.count >= 12
    else {
      return false
    }
    let boxType = bytes.subdata(in: 4..<8)
    return String(data: boxType, encoding: .ascii) == "ftyp"
  }
}

struct VapNetworkPlaybackError: Error {
  let code: Int64
  let message: String
}

final class VapBoundedDownloadTaskDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
  private let sourceForError: String
  private let maxDownloadBytes: Int64
  private let maxRedirects: Int
  private let completion: (Result<URL, VapNetworkPlaybackError>) -> Void

  private var redirectCount: Int = 0
  private var completed = false
  private var downloadedFileURL: URL?
  private(set) var task: URLSessionDownloadTask!
  private var session: URLSession?

  init(
    sourceForError: String,
    url: URL,
    maxDownloadBytes: Int64,
    maxRedirects: Int,
    completion: @escaping (Result<URL, VapNetworkPlaybackError>) -> Void
  ) {
    self.sourceForError = sourceForError
    self.maxDownloadBytes = maxDownloadBytes
    self.maxRedirects = maxRedirects
    self.completion = completion
    super.init()

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 60
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    self.session = session
    self.task = session.downloadTask(with: url)
  }

  func start() {
    task.resume()
  }

  func cancel() {
    task.cancel()
    session?.invalidateAndCancel()
    session = nil
  }

  private func finish(_ result: Result<URL, VapNetworkPlaybackError>) {
    if completed {
      return
    }
    completed = true
    completion(result)
    session?.finishTasksAndInvalidate()
    session = nil
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    redirectCount += 1
    if redirectCount > maxRedirects {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.networkIo,
            message: "Too many redirects while loading \(sourceForError)"
          )
        )
      )
      completionHandler(nil)
      return
    }
    guard
      let redirectedURL = request.url,
      let scheme = redirectedURL.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.invalidUrl,
            message: "Redirected URL is not http/https for \(sourceForError)"
          )
        )
      )
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let httpResponse = response as? HTTPURLResponse else {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.httpStatus,
            message: "Network response is not HTTP for \(sourceForError)"
          )
        )
      )
      completionHandler(.cancel)
      return
    }

    if !(200...299).contains(httpResponse.statusCode) {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.httpStatus,
            message: "Network request failed with status \(httpResponse.statusCode) for \(sourceForError)"
          )
        )
      )
      completionHandler(.cancel)
      return
    }

    let expectedLength = response.expectedContentLength
    if expectedLength > 0 && expectedLength > maxDownloadBytes {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.sizeExceeded,
            message: "Network response exceeds max download size (\(maxDownloadBytes) bytes) for \(sourceForError)"
          )
        )
      )
      completionHandler(.cancel)
      return
    }

    completionHandler(.allow)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    if totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite > maxDownloadBytes {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.sizeExceeded,
            message: "Network response exceeds max download size (\(maxDownloadBytes) bytes) for \(sourceForError)"
          )
        )
      )
      downloadTask.cancel()
      return
    }
    if totalBytesWritten > maxDownloadBytes {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.sizeExceeded,
            message: "Network response exceeds max download size (\(maxDownloadBytes) bytes) for \(sourceForError)"
          )
        )
      )
      downloadTask.cancel()
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    downloadedFileURL = location
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if completed {
      return
    }
    if error != nil {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.networkIo,
            message: "Failed to load network source: \(sourceForError)"
          )
        )
      )
      return
    }
    guard let downloadedFileURL else {
      finish(
        .failure(
          VapNetworkPlaybackError(
            code: VapNetworkFailureCode.networkIo,
            message: "Network download did not provide file data for \(sourceForError)"
          )
        )
      )
      return
    }
    finish(.success(downloadedFileURL))
  }
}
