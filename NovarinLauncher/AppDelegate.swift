//
//  AppDelegate.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/15/25.
//

import Foundation
import Cocoa
import SwiftUI
import Compression

class AppDelegate: NSObject, NSApplicationDelegate {
    var launchState = LaunchState()
    var isLaunching: Bool = false
    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        guard let url = urls.first else { return }
        let base64 = url.absoluteString.replacingOccurrences(of: "novarin:", with: "")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.shared.log("Failed to decode Base64 or JSON")
            return
        }
        
        printJSON(json)
        
        self.isLaunching = true

        let ticket = json["ticket"] as? String ?? ""
        let scriptURL = json["joinscript"] as? String ?? ""
        let jobID = json["jobid"] as? String ?? ""
        let placeID = String(json["placeid"] as? Int ?? 0)
        let gameVersion = String(json["version"] as? Int ?? 0)
        let launchType = json["LaunchType"] as? String ?? ""
//        let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
//        print(installedVersion)
        
        Task {
//            Logger.shared.log("Checking server version to see if the launcher needs to be updated...")
            do {
                self.isLaunching = true
                
//                let (_, serverVersion) = try await self.fetchLauncherVersionInfo()
//                if(!self.isLauncherUpToDate(version: serverVersion)) {
//                    Logger.shared.log("We're out of date, so I'll go update the launcher.")
//                    await self.installLauncher(launchData: json)
//                    return
//                }
                
                DispatchQueue.main.async {
                    self.launchState.status = "Launching Novarin \(gameVersion)..."
                    self.launchState.showButton = false
                }
                
                if let versionInt = Int(gameVersion), versionInt < 2018 {
                    DispatchQueue.main.async {
                        self.launchState.status = "Unsupported Version"
                        self.launchState.showLoading = false
                        self.launchState.showSmallStatus = true
                        self.launchState.smallStatus = "This version of Novarin is not supported on macOS."
                        self.launchState.showButton = true
                        self.launchState.buttonText = "Close"
                    }
                    return
                }
                
                switch launchType.lowercased() {
                    case "client":
                        launchPlayer(ticket: ticket, scriptURL: scriptURL, jobID: jobID, placeID: placeID, gameVersion: gameVersion)
                    case "studio":
                        DispatchQueue.main.async {
                            self.launchState.status = "Launching Novarin Studio \(gameVersion)..."
                            self.launchState.showButton = false
                        }
                        launchStudio(ticket: ticket, scriptURL: scriptURL, placeID: placeID, gameVersion: gameVersion)
                    default:
                        DispatchQueue.main.async {
                            self.launchState.status = "Invalid Launch Type"
                            self.launchState.showLoading = false
                            self.launchState.showSmallStatus = true
                            self.launchState.smallStatus = "If you were trying to play a game, or open a place in Novarin Studio, please ask for help in the Novarin Discord server."
                            self.launchState.showButton = true
                            self.launchState.buttonText = "Close"
                        }
                }
            } catch {
                Logger.shared.log("Launcher update failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.launchState.status = "Connection Error"
                    self.launchState.showLoading = false
                    self.launchState.showSmallStatus = true
                    self.launchState.smallStatus = "We were unable to connect to our servers. Check your internet connection."
                    self.launchState.showButton = true
                    self.launchState.buttonText = "Close"
                }
            }
        }
    }
    
    func printJSON(_ object: Any, indent: String = "") {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                Logger.shared.log("\(indent)\(key):")
                printJSON(value, indent: indent + "  ")
            }
        } else if let array = object as? [Any] {
            for (index, value) in array.enumerated() {
                Logger.shared.log("\(indent)[\(index)]:")
                printJSON(value, indent: indent + "  ")
            }
        } else {
            Logger.shared.log("\(indent)\(object)")
        }
    }

    func launchPlayer(ticket: String, scriptURL: String, jobID: String, placeID: String, gameVersion: String) {
        Task {
            Logger.shared.log("Checking server version to see if anything needs to be updated before we launch the player...")
            let (_, _, serverVersion) = try await self.fetchVersionInfo(gameVersion: gameVersion)
            if(self.isVersionUpToDate(gameVersion: gameVersion, version: serverVersion)) {
                Logger.shared.log("We're up to date, so let's continue with launching the player...")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Applications/Novarin/\(gameVersion)/NovarinPlayer.app/Contents/MacOS/RobloxPlayer")
                process.arguments = [
                    "-authURL", "\"http://novarin.co/Login/Negotiate.ashx\"",
                    "-ticket", "\"\(ticket)\"",
                    "-scriptURL", "\"\(scriptURL)\""
                ]
                
                do {
                    try process.run()
                    Task {
                        let rpcManagerPath = Bundle.main.resourcePath! + "/NovarinRPCManager/NovarinRPCManager.app/Contents/MacOS/NovarinRPCManager"
                        let task = Process()
                        task.launchPath = rpcManagerPath
                        task.arguments = ["-jobID", jobID, "-placeID", placeID, "-version", gameVersion, "-processID", String(process.processIdentifier)]
                        task.launch()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        NSApp.terminate(nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.launchState.status = "Failed to launch Novarin Player.\nPlease ask for help in the Novarin Discord server."
                        self.launchState.showLoading = false
                    }
                    Logger.shared.log("Could not launch NovarinPlayer: \(error)")
                }
            } else {
                let launchData: [String: Any] = [
                    "ticket": ticket,
                    "joinscript": scriptURL,
                    "jobid": jobID,
                    "placeid": placeID,
                    "version": gameVersion,
                    "LaunchType": "client"
                ]

                Logger.shared.log("We're out of date, so I'll go redownload the applications.")
                await self.installClient(gameVersion: gameVersion, launchData: launchData)
            }
        }
    }
    
    func launchStudio(ticket: String, scriptURL: String, placeID: String, gameVersion: String) {
        Task {
            Logger.shared.log("Checking server version to see if Studio needs to be updated before we launch it...")
            let (_, _, serverVersion) = try await self.fetchVersionInfo(gameVersion: gameVersion)
            if(self.isVersionUpToDate(gameVersion: gameVersion, version: serverVersion)) {
                Logger.shared.log("We're up to date, so let's continue with launching Studio...")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Applications/Novarin/\(gameVersion)/NovarinStudio.app/Contents/MacOS/RobloxStudio")
                process.arguments = [
                    "-task", "EditPlace",
                    "-placeId", "\(placeID)"
                ]
                
                do {
                    try process.run()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        NSApp.terminate(nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.launchState.status = "Failed to launch Novarin Studio.\nPlease ask for help in the Novarin Discord server."
                        self.launchState.showLoading = false
                    }
                    Logger.shared.log("Could not launch NovarinStudio: \(error)")
                }
            } else {
                Logger.shared.log("We're out of date, so I'll go redownload Studio.")
                
                let launchData: [String: Any] = [
                    "ticket": ticket,
                    "joinscript": scriptURL,
                    "jobid": NSNull.self,
                    "placeid": placeID,
                    "version": gameVersion,
                    "LaunchType": "studio"
                ]
                
                await self.installStudio(gameVersion: gameVersion, launchData: launchData)
            }
        }
    }
    
    func saveLaunchDataAsJSON(_ json: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: json, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(jsonString, forKey: "PendingLaunchJSON")
            UserDefaults.standard.synchronize()
        }
    }
    
    // version info stuff
    func fetchLauncherVersionInfo() async throws -> (launcherUrl: String, version: String) {
        guard let url = URL(string: "http://n.termy.lol/client/launcher/mac") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let launcherUrl = json["launcherUrl"] as? String,
              let version = json["version"] as? String else {
            Logger.shared.log(String(bytes: data, encoding: String.Encoding.utf8) ?? "nojson")
            throw NSError(domain: "JSONError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid JSON"])
        }
        
        return (launcherUrl, version)
    }
    
    func fetchVersionInfo(gameVersion: String) async throws -> (playerUrl: String, studioUrl: String, version: String) {
        guard let url = URL(string: "http://n.termy.lol/client/setup/client/\(gameVersion)/mac") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let playerUrl = json["playerUrl"] as? String,
              let studioUrl = json["studioUrl"] as? String,
              let version = json["version"] as? String else {
            Logger.shared.log(String(bytes: data, encoding: String.Encoding.utf8) ?? "nojson")
            throw NSError(domain: "JSONError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid JSON"])
        }
        
        return (playerUrl, studioUrl, version)
    }
    
    func saveVersion(gameVersion: String, version: String) {
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.shared.log("Could not find Application Support directory")
            return
        }

        let novarinFolder = appSupportDir.appendingPathComponent("Novarin")

        do {
            try FileManager.default.createDirectory(at: novarinFolder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.shared.log("Failed to create directory: \(error)")
            return
        }

        let versions: [String: String] = [
            "ver": version
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: versions, options: .prettyPrinted)
            let jsonFileURL = novarinFolder.appendingPathComponent("\(gameVersion).json")
            try jsonData.write(to: jsonFileURL)
            Logger.shared.log("Saved \(gameVersion).json to \(jsonFileURL.path)")
        } catch {
            Logger.shared.log("Failed to save JSON: \(error)")
        }
    }

    func isLauncherUpToDate(version: String) -> Bool {
        let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        return installedVersion == version
    }
    
    func isVersionUpToDate(gameVersion: String, version: String) -> Bool {
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.shared.log("Could not find Application Support directory.")
            return false
        }

        let versionsFile = appSupportDir.appendingPathComponent("Novarin/\(gameVersion).json")

        guard FileManager.default.fileExists(atPath: versionsFile.path) else {
            Logger.shared.log("\(gameVersion).json not found.")
            return false
        }

        do {
            let data = try Data(contentsOf: versionsFile)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let storedVersion = json["ver"] as? String {
                Logger.shared.log(version)
                return storedVersion == version
            } else {
                Logger.shared.log("Invalid JSON structure or 'ver' key missing.")
                return false
            }
        } catch {
            Logger.shared.log("Failed to read or parse \(gameVersion).json: \(error)")
            return false
        }
    }

    
    // installation stuff
    
    func installLauncher(launchData: [String: Any]) async {
        let launcherDestZip = "/tmp/NovarinLauncher.zip"
        let extractDir = "/Applications"
        let downloader = FileDownloader()
        
        Task {
            do {
                let updateUI: @MainActor (String, Bool, Double, Bool, Bool, Bool, String) -> Void = { status, isDownloading, progress, showLoading, showSmallStatus, showButton, buttonText in
                    self.launchState.status = status
                    self.launchState.isDownloading = isDownloading
                    self.launchState.downloadProgress = progress
                    self.launchState.showLoading = showLoading
                    self.launchState.showSmallStatus = showSmallStatus
                    self.launchState.showButton = showButton
                    self.launchState.buttonText = buttonText
                }
                
                updateUI("Fetching information...", false, 0.0, true, false, true, "Cancel")
                let (launcherUrl, version) = try await fetchLauncherVersionInfo()
                updateUI("Downloading Novarin Launcher...", true, 0.0, true, false, true, "Cancel")
                
                let launcherFileURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    downloader.downloadFile(
                        from: launcherUrl,
                        to: launcherDestZip,
                        progress: { progress in
                            Task { @MainActor in
                                self.launchState.downloadProgress = progress
                            }
                        },
                        completion: { result in
                            continuation.resume(with: result)
                        }
                    )
                }
                
                updateUI("Installing Novarin Launcher...", false, 100.0, true, false, false, "Cancel")
                
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try self.extractZip(from: launcherFileURL.path, to: extractDir)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    let path = Bundle.main.bundlePath
                    let task = Process()
                    task.launchPath = "/usr/bin/open"
                    task.arguments = [path]
                    do {
                        try task.run()
                    } catch {
                        print("Failed to restart via open: \(error)")
                    }
                    
                    self.saveLaunchDataAsJSON(launchData)

                    NSApp.terminate(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.launchState.isDownloading = false
                    self.launchState.downloadProgress = 0.0
                    self.launchState.status = "Download failed!"
                    self.launchState.smallStatus = error.localizedDescription
                    self.launchState.showLoading = false
                    self.launchState.showSmallStatus = true
                    self.launchState.showButton = true
                    self.launchState.buttonText = "Close"
                }
                Logger.shared.log("Error fetching launcher URL: \(error)")
            }
        }
    }
    
    func installAll(gameVersion: String, launchData: [String: Any]) async {
        let clientDestZip = "/tmp/NovarinPlayer\(gameVersion).zip"
            let studioDestZip = "/tmp/NovarinStudio\(gameVersion).zip"
            let extractDir = "/Applications/Novarin/\(gameVersion)"
            let downloader = FileDownloader()
            
            Task {
                do {
                    let updateUI: @MainActor (String, Bool, Double, Bool, Bool, Bool, String) -> Void = { status, isDownloading, progress, showLoading, showSmallStatus, showButton, buttonText in
                        self.launchState.status = status
                        self.launchState.isDownloading = isDownloading
                        self.launchState.downloadProgress = progress
                        self.launchState.showLoading = showLoading
                        self.launchState.showSmallStatus = showSmallStatus
                        self.launchState.showButton = showButton
                        self.launchState.buttonText = buttonText
                    }
                    
                    updateUI("Fetching information...", false, 0.0, true, false, true, "Cancel")
                    let (clientDownloadURL, studioDownloadURL, version) = try await fetchVersionInfo(gameVersion: gameVersion)
                    
                    updateUI("Downloading Novarin Player \(gameVersion)...", true, 0.0, true, false, true, "Cancel")
                    
                    let clientFileURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                        downloader.downloadFile(
                            from: clientDownloadURL,
                            to: clientDestZip,
                            progress: { progress in
                                Task { @MainActor in
                                    self.launchState.downloadProgress = progress
                                }
                            },
                            completion: { result in
                                continuation.resume(with: result)
                            }
                        )
                    }
                    
                    updateUI("Installing Novarin Player \(gameVersion)...", false, 100.0, true, false, false, "Cancel")
                    
                    try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                try self.extractZip(from: clientFileURL.path, to: extractDir)
                                continuation.resume()
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    
                    updateUI("Downloading Novarin Studio \(gameVersion)...", true, 0.0, true, false, true, "Cancel")
                    
                    let studioFileURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                        downloader.downloadFile(
                            from: studioDownloadURL,
                            to: studioDestZip,
                            progress: { progress in
                                Task { @MainActor in
                                    self.launchState.downloadProgress = progress
                                }
                            },
                            completion: { result in
                                continuation.resume(with: result)
                            }
                        )
                    }
                    
                    updateUI("Installing Novarin Studio \(gameVersion)...", false, 100.0, true, false, false, "Cancel")
                    
                    try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                try self.extractZip(from: studioFileURL.path, to: extractDir)
                                continuation.resume()
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    
                    saveVersion(gameVersion: gameVersion, version: version)

                    updateUI("Novarin \(gameVersion) IS SUCCESSFULLY INSTALLED!", false, 100.0, false, true, true, "OK")
                    
                } catch {
                    Logger.shared.log("Installation error: \(error)")
                    self.launchState.isDownloading = false
                    self.launchState.downloadProgress = 0.0
                    self.launchState.status = "Installation failed!"
                    self.launchState.smallStatus = error.localizedDescription
                    self.launchState.showLoading = false
                    self.launchState.showSmallStatus = true
                    self.launchState.showButton = true
                    self.launchState.buttonText = "Close"
                }
            }
    }

    
    func installClient(gameVersion: String, launchData: [String: Any]) async {
        let clientDestZip = "/tmp/NovarinPlayer\(gameVersion).zip"
        let extractDir = "/Applications/Novarin/\(gameVersion)"
        let downloader = FileDownloader()
        
        Task {
            do {
                let updateUI: @MainActor (String, Bool, Double, Bool, Bool, Bool, String) -> Void = { status, isDownloading, progress, showLoading, showSmallStatus, showButton, buttonText in
                    self.launchState.status = status
                    self.launchState.isDownloading = isDownloading
                    self.launchState.downloadProgress = progress
                    self.launchState.showLoading = showLoading
                    self.launchState.showSmallStatus = showSmallStatus
                    self.launchState.showButton = showButton
                    self.launchState.buttonText = buttonText
                }
                
                updateUI("Fetching information...", false, 0.0, true, false, true, "Cancel")
                let (clientDownloadURL, _, version) = try await fetchVersionInfo(gameVersion: gameVersion)
                
                updateUI("Downloading Novarin Player \(gameVersion)...", true, 0.0, true, false, true, "Cancel")
                
                let clientFileURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    downloader.downloadFile(
                        from: clientDownloadURL,
                        to: clientDestZip,
                        progress: { progress in
                            Task { @MainActor in
                                self.launchState.downloadProgress = progress
                            }
                        },
                        completion: { result in
                            continuation.resume(with: result)
                        }
                    )
                }
                
                updateUI("Installing Novarin Player \(gameVersion)...", false, 100.0, true, false, false, "Cancel")
                
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try self.extractZip(from: clientFileURL.path, to: extractDir)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                saveVersion(gameVersion: gameVersion, version: version)
                
                updateUI("Novarin \(gameVersion) IS SUCCESSFULLY INSTALLED!", false, 100.0, false, true, true, "OK")
                
//                DispatchQueue.main.async {
//                    let path = Bundle.main.bundlePath
//                    let task = Process()
//                    task.launchPath = "/usr/bin/open"
//                    task.arguments = [path]
//                    do {
//                        try task.run()
//                    } catch {
//                        print("Failed to restart via open: \(error)")
//                    }
//                    
//                    self.saveLaunchDataAsJSON(launchData)
//
//                    NSApp.terminate(nil)
//                }
            } catch {
                DispatchQueue.main.async {
                    self.launchState.isDownloading = false
                    self.launchState.downloadProgress = 0.0
                    self.launchState.status = "Download failed!"
                    self.launchState.smallStatus = error.localizedDescription
                    self.launchState.showLoading = false
                    self.launchState.showSmallStatus = true
                    self.launchState.showButton = true
                    self.launchState.buttonText = "Close"
                }
                Logger.shared.log("Error fetching client URL: \(error)")
            }
        }
    }
    
    func installStudio(gameVersion: String, launchData: [String: Any]) async {
        let studioDestZip = "/tmp/NovarinStudio\(gameVersion).zip"
        let extractDir = "/Applications/Novarin/\(gameVersion)"
        let downloader = FileDownloader()
        
        Task {
            do {
                let updateUI: @MainActor (String, Bool, Double, Bool, Bool, Bool, String) -> Void = { status, isDownloading, progress, showLoading, showSmallStatus, showButton, buttonText in
                    self.launchState.status = status
                    self.launchState.isDownloading = isDownloading
                    self.launchState.downloadProgress = progress
                    self.launchState.showLoading = showLoading
                    self.launchState.showSmallStatus = showSmallStatus
                    self.launchState.showButton = showButton
                    self.launchState.buttonText = buttonText
                }
                
                updateUI("Fetching information...", false, 0.0, true, false, true, "Cancel")
                let (_, studioDownloadURL, version) = try await fetchVersionInfo(gameVersion: gameVersion)
                
                updateUI("Downloading Novarin Studio \(gameVersion)...", true, 0.0, true, false, true, "Cancel")
                
                let studioFileURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    downloader.downloadFile(
                        from: studioDownloadURL,
                        to: studioDestZip,
                        progress: { progress in
                            Task { @MainActor in
                                self.launchState.downloadProgress = progress
                            }
                        },
                        completion: { result in
                            continuation.resume(with: result)
                        }
                    )
                }
                
                updateUI("Installing Novarin Studio \(gameVersion)...", false, 100.0, true, false, false, "Cancel")
                
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try self.extractZip(from: studioFileURL.path, to: extractDir)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                saveVersion(gameVersion: gameVersion, version: version)
                
                updateUI("Novarin STUDIO \(gameVersion) IS SUCCESSFULLY INSTALLED!", false, 100.0, false, true, true, "OK")
                
//                DispatchQueue.main.async {
//                    let path = Bundle.main.bundlePath
//                    let task = Process()
//                    task.launchPath = "/usr/bin/open"
//                    task.arguments = [path]
//                    do {
//                        try task.run()
//                    } catch {
//                        print("Failed to restart via open: \(error)")
//                    }
//                    
//                    self.saveLaunchDataAsJSON(launchData)
//
//                    NSApp.terminate(nil)
//                }
            } catch {
                DispatchQueue.main.async {
                    self.launchState.isDownloading = false
                    self.launchState.downloadProgress = 0.0
                    self.launchState.status = "Download failed!"
                    self.launchState.smallStatus = error.localizedDescription
                    self.launchState.showLoading = false
                    self.launchState.showSmallStatus = true
                    self.launchState.showButton = true
                    self.launchState.buttonText = "Close"
                }
                Logger.shared.log("Error fetching studio URL: \(error)")
            }
        }
    }

    func extractZip(from zipPath: String, to extractDir: String) throws {
        let task = Process()
        task.launchPath = "/usr/bin/unzip"
        task.arguments = ["-qo", zipPath, "-d", extractDir]
        
        let pipe = Pipe()
        task.standardError = pipe
        
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Extraction failed: \(error)", code: Int(task.terminationStatus), userInfo: nil)
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first {
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setContentSize(NSSize(width: 300, height: 300))
            window.styleMask.remove(.resizable)
            window.center()
        }
        
//        if let jsonString = UserDefaults.standard.string(forKey: "PendingLaunchJSON"),
//           let data = jsonString.data(using: .utf8),
//           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
//            
//            Logger.shared.log("Resuming launch from stored JSON after update")
//            UserDefaults.standard.removeObject(forKey: "PendingLaunchJSON")
//            self.isLaunching = true
//
//            printJSON(json)
//
//            let ticket = json["ticket"] as? String ?? ""
//            let scriptURL = json["joinscript"] as? String ?? ""
//            let jobID = json["jobid"] as? String ?? ""
//            let placeID = String(json["placeid"] as? Int ?? 0)
//            let gameVersion = String(json["version"] as? Int ?? 0)
//            let launchType = json["LaunchType"] as? String ?? ""
//
//            Task {
//                switch launchType.lowercased() {
//                    case "client":
//                        launchPlayer(ticket: ticket, scriptURL: scriptURL, jobID: jobID, placeID: placeID, gameVersion: gameVersion)
//                    case "studio":
//                        launchStudio(ticket: ticket, scriptURL: scriptURL, placeID: placeID, gameVersion: gameVersion)
//                    default:
//                        Logger.shared.log("Invalid stored launch type: \(launchType)")
//                }
//            }
//            return
//        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !self.isLaunching {
                if let url = URL(string: "https://novarin.co/") {
                    NSWorkspace.shared.open(url)
                    NSApp.terminate(nil)
                }
            }
        }
    }

}
