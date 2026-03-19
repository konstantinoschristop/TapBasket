//
//  ContentView.swift
//  GroceriesNow
//
//  Created by k.christopoulos on 15/3/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        MainGridView()
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer.make())
}
