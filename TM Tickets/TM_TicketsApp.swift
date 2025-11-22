//
//  TM_TicketsApp.swift
//  TM Tickets
//
//  Created by Cooper Foster on 10/27/25.
//

import SwiftUI

@main
struct TM_TicketsApp: App {
    init() {
        // Ensure any legacy base URL is migrated to the new classic app host
        AppConfig.migrateBaseURLIfNeeded()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
