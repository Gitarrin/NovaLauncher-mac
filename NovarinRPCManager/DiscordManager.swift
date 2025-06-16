//
//  DiscordManager.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/16/25.
//

import Foundation
import AppKit

// Hi, this function is required for C interoperability
func discord_on_activity_join(event_data: UnsafeMutableRawPointer?, secret: UnsafePointer<CChar>?) {
    DiscordManager.shared?.onActivityJoin(event_data: event_data, secret: secret)
}

class DiscordManager {
    static var shared: DiscordManager?

    var activityEvents: IDiscordActivityEvents
    var corePtr: UnsafeMutablePointer<UnsafeMutablePointer<IDiscordCore>?>
    
    init() {
        self.corePtr = UnsafeMutablePointer<UnsafeMutablePointer<IDiscordCore>?>.allocate(capacity: 1)
        self.activityEvents = IDiscordActivityEvents(
            on_activity_join: discord_on_activity_join,
            on_activity_spectate: nil,
            on_activity_join_request: nil,
            on_activity_invite: nil
        )
        
        DiscordManager.shared = self

        var params = DiscordCreateParams()
        DiscordCreateParamsSetDefault(&params)
        params.client_id = 1353418280349470801
        params.flags = UInt64(DiscordCreateFlags_NoRequireDiscord.rawValue)
        params.activity_events = withUnsafeMutablePointer(to: &self.activityEvents) { $0 }

        let result = DiscordCreate(
            DISCORD_VERSION,
            &params,
            corePtr
        )
        
        if result != DiscordResult_Ok {
            Logger.shared.log("Uh oh! Discord SDK failed to initialize: \(result)")
            return
        }

        Logger.shared.log("Discord SDK initialized!")
        
        if let core = corePtr.pointee {
            let activityManager = core.pointee.get_activity_manager(core)
            let command = "novarin-discord://join"
            _ = activityManager?.pointee.register_command(activityManager, command)
            Logger.shared.log("Registered Discord join command: \(command)")
        }
    }
    
    func onActivityJoin(event_data: UnsafeMutableRawPointer?, secret: UnsafePointer<CChar>?) {
        guard let secret = secret else { return }

        let secretString = String(cString: secret)
        Logger.shared.log("Join Secret received: \(secretString)")

        let parts = secretString.components(separatedBy: "+")
        guard parts.count == 2 else {
            Logger.shared.log("Invalid join secret format.")
            return
        }

        let placeId = parts[0]
        let jobId = parts[1]

        let urlString = "https://novarin.cc/discord-redirect-place?id=\(placeId)&autoJoinJob=\(jobId)"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }

        exit(0)
    }

    func updatePresence(state: String, details: String, startPlayTime: Int64, largeImage: String, largeText: String, partyId: String, partyCurrentSize: Int32, partyMaxSize: Int32, joinSecret: String) {
        var presence = DiscordActivity()
        memset(&presence, 0, MemoryLayout<DiscordActivity>.size)

        _ = state.withCString { strncpy(&presence.state.0, $0, MemoryLayout.size(ofValue: presence.state)) }
        _ = details.withCString { strncpy(&presence.details.0, $0, MemoryLayout.size(ofValue: presence.details)) }

        presence.timestamps.start = startPlayTime

        _ = largeImage.withCString { strncpy(&presence.assets.large_image.0, $0, MemoryLayout.size(ofValue: presence.assets.large_image)) }
        _ = largeText.withCString { strncpy(&presence.assets.large_text.0, $0, MemoryLayout.size(ofValue: presence.assets.large_text)) }

        _ = partyId.withCString { strncpy(&presence.party.id.0, $0, MemoryLayout.size(ofValue: presence.party.id)) }
        presence.party.size.current_size = partyCurrentSize
        presence.party.size.max_size = partyMaxSize

        _ = joinSecret.withCString { strncpy(&presence.secrets.join.0, $0, MemoryLayout.size(ofValue: presence.secrets.join)) }
        
        presence.instance = true

        guard let core = self.corePtr.pointee else { return }
        let activityManager = core.pointee.get_activity_manager(core)
        activityManager?.pointee.update_activity(activityManager, &presence, nil) { data, result  in
            Logger.shared.log("Presence updated: \(String(describing: result))")
        }
    }
}

