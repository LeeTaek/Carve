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
    
    static let firebaseCrashlytics: Self = .post(
        script: """
          if [ "${CONFIGURATION}" != "Debug" ]; then
            ROOT_DIR=
            "${SRCROOT%/*/*}/Tuist/Dependencies/SwiftPackageManager/.build/checkouts/firebase-ios-sdk/Crashlytics/run"
            echo "❗️ROOT_DIR Path: ${ROOT_DIR}"
          fi
          """,
        name: "Firebase Crashlytics",
        inputPaths: [
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}",
            "$(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)"
        ],
        basedOnDependencyAnalysis: false
    )
}
