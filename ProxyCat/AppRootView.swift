//
//  ContentView.swift
//  ProxyCat
//
//  Created by xiangyue on 2023/2/7.
//

import SwiftUI

struct AppRootView: View {
    private let container: DIContainer
    
    init(container: DIContainer) {
        self.container = container
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            container.appState.value.system.isActive = true
            container.appState.value.userData.hosts = ["xxx"]
        }
    }
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 250)
        } detail: {
            MainView()
                .frame(minWidth: 400)
        }
        .inject(container)
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
        AppRootView(container: DIContainer(appState: AppState(), interactors: .stub))
    }
}
