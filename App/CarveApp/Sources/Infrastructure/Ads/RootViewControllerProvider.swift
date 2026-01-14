//
//  RootViewControllerProvider.swift
//  CarveApp
//
//  Created by 이택성 on 1/8/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import UIKit

/// 현재 사용자에게 보이는 view 기준 최상단 VC를 찾아 제공.
/// - AdMob 등 사용
enum RootViewControllerProvider {
    /// 현재 표시 중인 최상단 ViewController.
    @MainActor
    static func topMostViewController() -> UIViewController? {
        guard let window = keyWindow(),
              let rootViewController = window.rootViewController
        else {
            return nil
        }
        return topMost(from: rootViewController)
    }
    
    /// keyWindow 우선 → 없으면(전환 중 등) visible window로 fallback
    @MainActor
    private static func keyWindow() -> UIWindow? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = windowScenes.flatMap { $0.windows }
        
        if let keyWindow = windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        
        return windows.first(where: { $0.isHidden == false })
    }
    
    
    /// presented / navigation / tab 컨테이너를 따라가며 최상단 VC 조회.
    @MainActor
    private static func topMost(from rootViewController: UIViewController) -> UIViewController {
        if let presented = rootViewController.presentedViewController {
            return topMost(from: presented)
        }
        
        if let navigationController = rootViewController as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return topMost(from: visibleViewController)
        }
        
        if let tabBarController = rootViewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return topMost(from: selectedViewController)
        }
        
        return rootViewController
    }
}
