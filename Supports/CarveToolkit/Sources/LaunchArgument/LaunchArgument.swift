//
//  LaunchArgument.swift
//  CarveToolkit
//
//  Created by Claude on 9/30/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 앱이 읽는 실행 인자(`ProcessInfo.processInfo.arguments`) 이름을 모두 여기에 모은다.
///
/// - 이름마다 lowerCamelCase 상수 하나를 둔다(예: `public static let singleCanvas = "-SingleCanvas"`).
///   새 인자는 여기에 먼저 추가하고, 앱 · 모듈 코드와 UI 테스트는 문자열 대신 이 상수를 쓴다.
/// - 이 파일은 Foundation 만 import 한다. `CarveAppUITests` 가 CarveToolkit 을 링크하지 않고 이 파일을 소스로 함께 컴파일한다
///   (`App/CarveApp/Project.swift`) — 다른 모듈의 타입을 쓰면 UI 테스트 빌드가 깨진다.
public enum LaunchArgument {}
