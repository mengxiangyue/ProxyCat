//
//  ContentView.swift
//  ProxyCat
//
//  Created by xiangyue on 2023/2/7.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 250)
        } detail: {
            MainView()
                .frame(minWidth: 400)
        }
        .frame(
            minWidth: 600,
            idealWidth: 1080,
            maxWidth: .infinity,
            minHeight: 400,
            idealHeight: 800,
            maxHeight: .infinity
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
