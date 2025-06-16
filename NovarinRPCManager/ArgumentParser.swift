//
//  ArgumentParser.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/16/25.
//


import Cocoa

class ArgumentParser {
    var jobID: String?
    var placeID: Int?
    var processID: Int?

    init(arguments: [String]) {
        if let jobIDIndex = arguments.firstIndex(of: "-jobID"),
           arguments.count > jobIDIndex + 1 {
            self.jobID = arguments[jobIDIndex + 1]
        }

        if let placeIDIndex = arguments.firstIndex(of: "-placeID"),
           arguments.count > placeIDIndex + 1,
           let value = Int(arguments[placeIDIndex + 1]) {
            self.placeID = value
        }

        if let processIDIndex = arguments.firstIndex(of: "-processID"),
           arguments.count > processIDIndex + 1,
           let value = Int(arguments[processIDIndex + 1]) {
            self.processID = value
        }
    }
}

