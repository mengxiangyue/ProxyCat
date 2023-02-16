//
//  AppState.swift
//  ProxyCat
//
//  Created by xiangyue on 2023/2/16.
//

import SwiftUI
import Combine

struct AppState: Equatable {
    var userData = UserData()
    var system = System()
    var permissions = Permissions()
}

extension AppState {
    struct UserData: Equatable {
        /*
         The list of countries (Loadable<[Country]>) used to be stored here.
         It was removed for performing countries' search by name inside a database,
         which made the resulting variable used locally by just one screen (CountriesList)
         Otherwise, the list of countries could have remained here, available for the entire app.
         */
        var hosts: [String] = []
    }
}

extension AppState {
    struct System: Equatable {
        var isActive: Bool = false
        var keyboardHeight: CGFloat = 0
    }
}

extension AppState {
    struct Permissions: Equatable {
//        var push: Permission.Status = .unknown
    }
    
//    static func permissionKeyPath(for permission: Permission) -> WritableKeyPath<AppState, Permission.Status> {
//        let pathToPermissions = \AppState.permissions
//        switch permission {
//        case .pushNotifications:
//            return pathToPermissions.appending(path: \.push)
//        }
//    }
}

func == (lhs: AppState, rhs: AppState) -> Bool {
    return lhs.userData == rhs.userData &&
        lhs.system == rhs.system &&
        lhs.permissions == rhs.permissions
}

#if DEBUG
extension AppState {
    static var preview: AppState {
        var state = AppState()
        state.system.isActive = true
        return state
    }
}
#endif
