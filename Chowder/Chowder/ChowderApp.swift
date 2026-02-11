//
//  ChowderApp.swift
//  Chowder
//
//  Created by Gabriel Mitchell on 2/10/26.
//

import SwiftUI

@main
struct ChowderApp: App {
    init() {
        print("🟢 APP LAUNCHED — if you see this, print() works")
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
        }
    }
}
