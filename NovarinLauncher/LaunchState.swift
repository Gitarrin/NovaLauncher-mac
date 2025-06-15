//
//  LaunchState.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/15/25.
//

import Foundation
import Combine

class LaunchState: ObservableObject {
    @Published var status: String = "Connecting to Novarin..."
    @Published var smallStatus: String = "Click the 'Join' button on any game to join the action!"
    @Published var buttonText: String = "Cancel"
    @Published var showLoading: Bool = true
    @Published var showButton: Bool = true
    @Published var showSmallStatus: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
}

