//
//  Script.swift
//  MyPlugin
//
//  Created by 이택성 on 1/25/24.
//

import Foundation
import ProjectDescription

public extension TargetScript {
    static let swiftLint: Self = .pre(
        script: """
        # mise에서 설치된 swiftlint 사용하도록 설정
        if [ -d "$HOME/.local/share/mise/shims" ]; then
            export PATH="$HOME/.local/share/mise/shims:$PATH"
        else
            echo "mise shims directory not found"
        fi
        
        # 현재 PATH 출력
        echo "Current PATH: $PATH"
        
        # swiftlint 경로 확인
        SWIFTLINT_PATH=$(which swiftlint)
        echo "❗️SwiftLint Path: $SWIFTLINT_PATH"
        SWIFTLINT_CONFIG_PATH="${SRCROOT%/*/*}/.swiftlint.yml"
        echo "❗️SRCROOT Path: ${SWIFTLINT_CONFIG_PATH}"
        
        # SwiftLint 실행
        if [ -n "$SWIFTLINT_PATH" ]; then
            swiftlint --config "$SWIFTLINT_CONFIG_PATH"
        else
            echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
        fi
        
        """,
        name: "SwiftLint",
        basedOnDependencyAnalysis: false
    )
    
    /// Firebase 공식 dSYM 업로드 스크립트(`Crashlytics/run`). Release 에서만 돈다 — Debug 는 수집도 꺼 두었다(앱 Project.swift).
    /// 패키지는 `tuist install` 이 저장소 루트의 `Tuist/.build/checkouts` 에 받는다. 앱 SRCROOT(`App/CarveApp`)의 두 단계 위가 루트다.
    /// `run` 은 먼저 동기로 검증(`--validate`)하고 실패하면 그 종료 코드로 빌드를 멈춘다. 업로드는 백그라운드라 빌드 로그에 남지 않는다.
    static let firebaseCrashlytics: Self = .post(
        script: """
        if [ "${CONFIGURATION}" != "Release" ]; then
          echo "Crashlytics dSYM 업로드는 Release 에서만 한다 (${CONFIGURATION})"
          exit 0
        fi
        CRASHLYTICS_RUN="${SRCROOT%/*/*}/Tuist/.build/checkouts/firebase-ios-sdk/Crashlytics/run"
        if [ ! -f "${CRASHLYTICS_RUN}" ]; then
          echo "error: Crashlytics run 스크립트가 없다: ${CRASHLYTICS_RUN} — mise x -- tuist install 을 먼저 한다"
          exit 1
        fi
        echo "Crashlytics run: ${CRASHLYTICS_RUN}"
        "${CRASHLYTICS_RUN}"
        """,
        name: "Firebase Crashlytics",
        // ENABLE_USER_SCRIPT_SANDBOXING 이 켜져 있어 run 이 읽는 파일을 선언해야 한다.
        // 목록은 SDK 의 Crashlytics/CrashlyticsInputFiles.xcfilelist 와 같다.
        inputPaths: [
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}",
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}",
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist",
            "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist",
            "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)"
        ],
        basedOnDependencyAnalysis: false
    )
}
