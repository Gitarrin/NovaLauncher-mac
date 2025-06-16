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

        let ticket = json["ticket"] as? String ?? ""
        let scriptURL = json["joinscript"] as? String ?? ""
        let jobID = json["jobid"] as? String ?? ""
        let placeID = String(json["placeid"] as? Int ?? 0)
        
        DispatchQueue.main.async {
            self.launchState.status = "Launching Novarin..."
            self.launchState.showButton = false
        }
        
        self.isLaunching = true
        launchPlayer(ticket: ticket, scriptURL: scriptURL, jobID: jobID, placeID: placeID)
    }

    func launchPlayer(ticket: String, scriptURL: String, jobID: String, placeID: String) {
        Task {
            Logger.shared.log("Checking server version to see if anything needs to be updated before we launch the player...")
            let (_, _, serverVersion) = try await self.fetchVersionInfo()
            if(self.isVersionUpToDate(version: serverVersion)) {
                Logger.shared.log("We're up to date, so let's continue with launching the player...")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Applications/Novarin/NovarinPlayer.app/Contents/MacOS/RobloxPlayer")
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
                        task.arguments = ["-jobID", jobID, "-placeID", placeID, "-processID", String(process.processIdentifier)]
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
                Logger.shared.log("We're out of date, so I'll go redownload the applications.")
                await self.installAll()
            }
        }
    }
    
    // version info stuff
    func fetchVersionInfo() async throws -> (playerUrl: String, studioUrl: String, version: String) {
        guard let url = URL(string: "http://n.termy.lol/client/setup/client/2018/mac") else {
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
    
    func saveVersion(version: String) {
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
            let jsonFileURL = novarinFolder.appendingPathComponent("version.json")
            try jsonData.write(to: jsonFileURL)
            Logger.shared.log("Saved version.json to \(jsonFileURL.path)")
        } catch {
            Logger.shared.log("Failed to save JSON: \(error)")
        }
    }

    func isVersionUpToDate(version: String) -> Bool {
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.shared.log("Could not find Application Support directory.")
            return false
        }

        let versionsFile = appSupportDir.appendingPathComponent("Novarin/version.json")

        guard FileManager.default.fileExists(atPath: versionsFile.path) else {
            Logger.shared.log("version.json not found.")
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
            Logger.shared.log("Failed to read or parse version.json: \(error)")
            return false
        }
    }

    
    // installation stuff
    
    func installAll() async {
        let clientDestZip = "/tmp/NovarinPlayer.zip"
            let studioDestZip = "/tmp/NovarinStudio.zip"
            let extractDir = "/Applications/Novarin"
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
                    let (clientDownloadURL, studioDownloadURL, version) = try await fetchVersionInfo()
                    
                    updateUI("Downloading Novarin Player...", true, 0.0, true, false, true, "Cancel")
                    
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
                    
                    updateUI("Installing Novarin Player...", false, 100.0, true, false, false, "Cancel")
                    
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
                    
                    updateUI("Downloading Novarin Studio...", true, 0.0, true, false, true, "Cancel")
                    
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
                    
                    updateUI("Installing Novarin Studio...", false, 100.0, true, false, false, "Cancel")
                    
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
                    
                    saveVersion(version: version)

                    updateUI("NOVARIN IS SUCCESSFULLY INSTALLED!", false, 100.0, false, true, true, "OK")
                    
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

    
    func installClient() async {
        let clientDestZip = "/tmp/NovarinPlayer.zip"
        let extractDir = "/Applications/Novarin"
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
                let (clientDownloadURL, _, _) = try await fetchVersionInfo()
                
                updateUI("Downloading Novarin Player...", true, 0.0, true, false, true, "Cancel")
                
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
                
                updateUI("Installing Novarin Player...", false, 100.0, true, false, false, "Cancel")
                
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
                
                updateUI("NOVARIN IS SUCCESSFULLY INSTALLED!", false, 100.0, false, true, true, "OK")
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
    
    func installStudio() async {
        let studioDestZip = "/tmp/NovarinStudio.zip"
        let extractDir = "/Applications/Novarin"
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
                let (_, studioDownloadURL, _) = try await fetchVersionInfo()
                
                updateUI("Downloading Novarin Studio...", true, 0.0, true, false, true, "Cancel")
                
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
                
                updateUI("Installing Novarin Studio...", false, 100.0, true, false, false, "Cancel")
                
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
                
                updateUI("NOVARIN IS SUCCESSFULLY INSTALLED!", false, 100.0, false, true, true, "OK")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !self.isLaunching {
                let fileManager = FileManager.default
                let folderPath = "/Applications/Novarin"
                    
                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory)
                    
                let directoryExists = exists && isDirectory.boolValue
                let clientPath = "/Applications/Novarin/NovarinPlayer.app"
                let clientExists = fileManager.fileExists(atPath: clientPath)
                let studioPath = "/Applications/Novarin/NovarinStudio.app"
                let studioExists = fileManager.fileExists(atPath: studioPath)

                if !directoryExists || (!clientExists && !studioExists) {
                    Task {
                        Logger.shared.log("Either the Novarin directory does not exist, or it does, but both applications are not installed, so I'll just download both.")
                        await self.installAll()
                    }
                } else if !clientExists {
                    Task {
                        Logger.shared.log("The Novarin directory does exist with NovarinStudio, but NovarinPlayer isn't there, so I'll just download that, but before I do, I'll check the server version if NovarinStudio needs to be downloaded too.")
                        Logger.shared.log("Checking server version to see if anything needs to be updated...")
                        let (_, _, serverVersion) = try await self.fetchVersionInfo()
                        if(self.isVersionUpToDate(version: serverVersion)) {
                            Logger.shared.log("Studio is up to date, so I'll just download the client.")
                            await self.installClient()
                        } else {
                            Logger.shared.log("Studio is out of date, so I'll download both.")
                            await self.installAll()
                        }
                    }
                } else if !studioExists {
                    Task {
                        Logger.shared.log("The Novarin directory does exist with NovarinPlayer, but NovarinStudio isn't there, so I'll just download that, but before I do, I'll check the server version if NovarinPlayer needs to be downloaded too.")
                        Logger.shared.log("Checking server version to see if anything needs to be updated...")
                        let (_, _, serverVersion) = try await self.fetchVersionInfo()
                        if(self.isVersionUpToDate(version: serverVersion)) {
                            Logger.shared.log("Client is up to date, so I'll just download Studio.")
                            await self.installStudio()
                        } else {
                            Logger.shared.log("Client is out of date, so I'll download both.")
                            await self.installAll()
                        }
                    }
                } else {
                    Task {
                        Logger.shared.log("Checking server version to see if anything needs to be updated...")
                        let (_, _, serverVersion) = try await self.fetchVersionInfo()
                        if(self.isVersionUpToDate(version: serverVersion)) {
                            Logger.shared.log("Everything is there and up to date, so I'll just show the successfully installed message.")
                            self.launchState.status = "NOVARIN IS SUCCESSFULLY INSTALLED!"
                            self.launchState.showLoading = false
                            self.launchState.showSmallStatus = true
                            self.launchState.buttonText = "OK"
                        } else {
                            Logger.shared.log("Everything is there, though not up to date, so I'll redownload all applications.")
                            await self.installAll()
                        }
                    }
                }
            }
        }
    }

}
