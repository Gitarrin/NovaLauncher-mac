//
//  ContentView.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/15/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var launchState: LaunchState

    var body: some View {
        VStack(spacing: 20) {
            Image("Logo")
                .resizable()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text(launchState.status)
                .font(.headline)
            if launchState.showSmallStatus {
                Text(launchState.smallStatus).font(.caption).lineLimit(50).multilineTextAlignment(.leading)
            }
            if launchState.showLoading {
                if launchState.isDownloading {
                    Text("Downloading: \(Int(launchState.downloadProgress * 100))%")
                    ProgressView(value: launchState.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1)
                }
            }
            if launchState.showButton {
                if #available(macOS 12.0, *) {
                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Text(launchState.buttonText)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Text(launchState.buttonText)
                    }.controlSize(.large)
                }
            }
        }
        .frame(width: 300, height: 300)
        .padding()
    }
}

#Preview {
    ContentView()
}
