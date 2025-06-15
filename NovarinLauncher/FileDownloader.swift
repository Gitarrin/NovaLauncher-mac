//
//  FileDownloader.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/15/25.
//

import Foundation
import Combine

class FileDownloader: NSObject, URLSessionDownloadDelegate {
    
    private var progressHandler: ((Double) -> Void)?
    private var completionHandler: ((Result<URL, Error>) -> Void)?
    
    func downloadFile(from urlString: String, to destination: String,
                      progress: @escaping (Double) -> Void,
                      completion: @escaping (Result<URL, Error>) -> Void) {
        
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 1)))
            return
        }

        self.progressHandler = progress
        self.completionHandler = completion
        
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        let task = session.downloadTask(with: url)
        task.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.progressHandler?(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destinationURL = downloadTask.originalRequest?.url?.lastPathComponent else {
            self.completionHandler?(.failure(NSError(domain: "Missing destination", code: 3)))
            return
        }

        let documents = FileManager.default.temporaryDirectory
        let finalURL = documents.appendingPathComponent(destinationURL)
        print(finalURL)
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: location, to: finalURL)
            DispatchQueue.main.async {
                self.completionHandler?(.success(finalURL))
            }
        } catch {
            DispatchQueue.main.async {
                self.completionHandler?(.failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.completionHandler?(.failure(error))
            }
        }
    }
}
