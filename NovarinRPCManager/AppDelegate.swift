//
//  AppDelegate.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/16/25.
//

import Foundation
import Cocoa

final class FailureCounter {
    var count: Int = 0
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var discord: DiscordManager?
    var args: ArgumentParser?
    var monitorSource: DispatchSourceProcess?

    var failureCounter = FailureCounter()
    var loopsTillPlayerCountCheck: Int = 0
    var cachedPlayersInJob: [String: Any] = [:]
    
    var openedByDiscord: Bool = false
    
    func fetchPlaceInfo(for placeID: Int) async throws -> [String: Any] {
        guard let url = URL(string: "https://novarin.cc/marketplace/productinfo?assetId=\(placeID)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("NovarinRPC/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.shared.log(String(bytes: data, encoding: .utf8) ?? "nojson")
            throw NSError(domain: "JSONError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid JSON"])
        }

        return json
    }
    
    func fetchPlayersInJob(for jobID: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://novarin.cc/app/api/games/playersInJob?jobid=\(jobID)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("NovarinRPC/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.shared.log(String(bytes: data, encoding: .utf8) ?? "nojson")
            throw NSError(domain: "JSONError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid JSON"])
        }

        return json
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "novarin", url.host == "join" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let secret = components.queryItems?.first(where: { $0.name == "secret" })?.value {
                    Logger.shared.log("Received join via URL with secret: \(secret)")
                    self.discord = DiscordManager()
                    self.discord?.onActivityJoin(event_data: nil, secret: secret)
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.discord = DiscordManager()
        
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            guard let discord = self.discord else { return }
            let corePtr = discord.corePtr
            _ = corePtr.pointee?.pointee.run_callbacks?(corePtr.pointee)
        }
        
        Logger.shared.log(CommandLine.arguments.joined(separator: " "))
        args = ArgumentParser(arguments: CommandLine.arguments)
        Logger.shared.log("NovarinRPCManager started")
        
        guard let discord = discord else {
            Logger.shared.log("Failed to unwrap `discord`.")
            return
        }
        guard let args = args else {
            Logger.shared.log("Failed to unwrap `args`.")
            return
        }
        guard let jobID = args.jobID else {
            Logger.shared.log("Failed to unwrap `args.jobID`.")
            return
        }
        guard let placeID = args.placeID else {
            Logger.shared.log("Failed to unwrap `args.placeID`.")
            return
        }
        guard let processID = args.processID else {
            Logger.shared.log("Failed to unwrap `args.processID`.")
            return
        }
        
        let targetPID = pid_t(processID)
        monitorProcessExit(pid: targetPID)
        
        Logger.shared.log("All required values unwrapped. Proceeding with Discord presence update.")
        
        let startPlayTime = Int64(Date().timeIntervalSince1970)
        Task {
            do {
                let placeInfo = try await self.fetchPlaceInfo(for: placeID)

                Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
                    Task {
                        do {
                            let count = await MainActor.run { self.loopsTillPlayerCountCheck }
                            if count >= 50 {
                                let newPlayersInJob = try await self.fetchPlayersInJob(for: jobID)
                                await MainActor.run { self.cachedPlayersInJob = newPlayersInJob }
                                await MainActor.run { self.loopsTillPlayerCountCheck = 0 }
                            } else {
                                await MainActor.run { self.loopsTillPlayerCountCheck += 1 }
                            }
                            
                            let cachedPlayersInJob = await MainActor.run { self.cachedPlayersInJob }
                            let playerCount = cachedPlayersInJob["playercount"] as? Int32 ?? 0
                            let maxPlayers = cachedPlayersInJob["maxplayers"] as? Int32 ?? 0

                            await self.discord?.updatePresence(
                                state: "Playing",
                                details: "Playing \(placeInfo["Name"] ?? "???")",
                                startPlayTime: startPlayTime,
                                largeImage: "novarin_logo",
                                largeText: "Novarin",
                                partyId: jobID,
                                partyCurrentSize: playerCount,
                                partyMaxSize: maxPlayers,
                                joinSecret: "\(placeID)+\(jobID)"
                            )

                            await MainActor.run { self.failureCounter.count = 0 } // Succeeded, so I'll reset the failure count
                        } catch {
                            await MainActor.run { self.failureCounter.count += 1 }
                            let failureCount = await MainActor.run { self.failureCounter.count }
                            await Logger.shared.log("Presence update failed (\(failureCount)/5): \(error)")
                            if failureCount >= 5 {
                                await Logger.shared.log("Too many failures. Stopping presence updates.")
                                timer.invalidate()
                            }
                        }
                    }
                }
            } catch {
                Logger.shared.log("Failed to fetch initial place info: \(error)")
            }
        }
    }
    
    func monitorProcessExit(pid: pid_t) {
            let queue = DispatchQueue.global()
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)

            source.setEventHandler {
                Logger.shared.log("Roblox process \(pid) exited.")
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }

            source.setCancelHandler {
                Logger.shared.log("Stopped monitoring Roblox process \(pid)")
            }

            monitorSource = source
            source.resume()
        }

    func applicationWillTerminate(_ notification: Notification) {
    }
}

