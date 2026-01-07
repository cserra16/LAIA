//
//  LAIAApp.swift
//  LAIA
//
//  Created by carlos on 29/12/25.
//

import SwiftUI

@main
struct LAIAApp: App {
    
    var body: some Scene {
        WindowGroup {
            ActiveSessionView()
                .preferredColorScheme(.dark)
        }
    }
}
