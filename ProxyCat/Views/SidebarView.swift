//
//  SidebarView.swift
//  ProxyCat
//
//  Created by xiangyue on 2023/2/8.
//

import SwiftUI
struct TodoItem: Identifiable {
    var id: UUID = UUID()
    var task: String
    var imgName: String
}

struct SidebarView: View {
    @Environment(\.injected) private var injected: DIContainer
    
    @State private var hosts: [String] = []
    @State private var pinnedItem: [String] = []
    
    var listData: [TodoItem] = [
            TodoItem(task: "写一篇SwiftUI文章", imgName: "pencil.circle"),
            TodoItem(task: "看WWDC视频", imgName: "square.and.pencil"),
            TodoItem(task: "定外卖", imgName: "folder"),
            TodoItem(task: "关注OldBirds公众号", imgName: "link"),
            TodoItem(task: "6点半跑步2公里", imgName: "moon"),
            TodoItem(task: "写一篇SwiftUI文章", imgName: "pencil.circle"),
            TodoItem(task: "看WWDC视频", imgName: "square.and.pencil"),
            TodoItem(task: "定外卖", imgName: "folder"),
            TodoItem(task: "关注OldBirds公众号", imgName: "link"),
            TodoItem(task: "6点半跑步2公里", imgName: "moon"),
            TodoItem(task: "写一篇SwiftUI文章", imgName: "pencil.circle"),
            TodoItem(task: "看WWDC视频", imgName: "square.and.pencil"),
            TodoItem(task: "定外卖", imgName: "folder"),
            TodoItem(task: "关注OldBirds公众号", imgName: "link"),
            TodoItem(task: "6点半跑步2公里", imgName: "moon"),
            TodoItem(task: "写一篇SwiftUI文章", imgName: "pencil.circle"),
            TodoItem(task: "看WWDC视频", imgName: "square.and.pencil"),
            TodoItem(task: "定外卖", imgName: "folder"),
            TodoItem(task: "关注OldBirds公众号", imgName: "link"),
            TodoItem(task: "6点半跑步2公里", imgName: "moon"),
            TodoItem(task: "写一篇SwiftUI文章", imgName: "pencil.circle"),
            TodoItem(task: "看WWDC视频", imgName: "square.and.pencil"),
            TodoItem(task: "定外卖", imgName: "folder"),
            TodoItem(task: "关注OldBirds公众号", imgName: "link"),
            TodoItem(task: "6点半跑步2公里", imgName: "moon"),
            TodoItem(task: "写一篇SwiftUI文章", imgName: "pencil.circle"),
            TodoItem(task: "看WWDC视频", imgName: "square.and.pencil"),
            TodoItem(task: "定外卖", imgName: "folder"),
            TodoItem(task: "关注OldBirds公众号", imgName: "link"),
            TodoItem(task: "6点半跑步2公里", imgName: "moon"),
            TodoItem(task: "写一篇SwiftUI文章", imgName: "pencil.circle"),
            TodoItem(task: "看WWDC视频", imgName: "square.and.pencil"),
            TodoItem(task: "定外卖", imgName: "folder"),
            TodoItem(task: "关注OldBirds公众号", imgName: "link"),
            TodoItem(task: "6点半跑步2公里", imgName: "moon"),
        ]
    var body: some View {
        VStack {
            List(listData) { item in
                HStack{
                    Image(systemName: item.imgName)
                    Text(item.task)
                }
            }
        }
        .onReceive(injected.appState.updates(for: \.proxyData.hosts)) {
            print("mxy-------", $0)
            self.hosts = $0
        }
        .onReceive(injected.appState.updates(for: \.proxyData.pinnedItems)) {
            self.pinnedItem = $0
        }
    }
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView()
    }
}
