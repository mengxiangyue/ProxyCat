//
//  SidebarView.swift
//  ProxyCat
//
//  Created by xiangyue on 2023/2/8.
//

import SwiftUI

struct SidebarView: View {
    @Environment(\.injected) private var injected: DIContainer
    
    var body: some View {
        VStack {
            Divider()
            Spacer()
            Text("Hello, World!")
            Spacer()
        }
        .onReceive(injected.appState.updates(for: \.userData.hosts)) {
            print($0)
        }
    }
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView()
    }
}
