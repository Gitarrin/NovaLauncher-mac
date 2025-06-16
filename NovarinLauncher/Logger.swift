//
//  Logger.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/15/25.
//
//  those who log

import Foundation

class Logger {
    static let shared = Logger()

    private var logFileHandle: FileHandle?

    init() {
        setupLogFile()
    }

    private func setupLogFile() {
        let fileManager = FileManager.default
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd-yy_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())

        let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let novarinDir = supportDir.appendingPathComponent("Novarin/logs", isDirectory: true)

        try? fileManager.createDirectory(at: novarinDir, withIntermediateDirectories: true, attributes: nil)

        let logFileURL = novarinDir.appendingPathComponent("log_\(dateString).txt")

        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }

        do {
            logFileHandle = try FileHandle(forWritingTo: logFileURL)
            logFileHandle?.seekToEndOfFile()
        } catch {
            print("Failed to open log file: \(error)")
        }
    }

    func log(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: Date())
        let applicationString = "NovarinLauncher"
        let fullMessage = "[\(applicationString)]-[\(dateString)] \(message)\n"

        print(fullMessage, terminator: "")

        if let data = fullMessage.data(using: .utf8) {
            logFileHandle?.write(data)
        }
    }

    deinit {
        logFileHandle?.closeFile()
    }
}
