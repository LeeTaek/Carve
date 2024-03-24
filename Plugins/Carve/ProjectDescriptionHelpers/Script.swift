//
//  Script.swift
//  MyPlugin
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription

public extension TargetScript {
    private static let swiftLintScript = """
    if test -d "/opt/homebrew/bin/"; then
        PATH="/opt/homebrew/bin/:${PATH}"
    fi

    export PATH

    if which swiftlint > /dev/null; then
        swiftlint
    else
        echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
    fi
    """
    
    private static let firebaseCrashlyticsScript = """
    if [ "${CONFIGURATION}" != "Debug" ]; then
         "Tuist/Dependencies/SwiftPackageManager/.build/checkouts/firebase-ios-sdk/Crashlytics/run" "Tuist/Dependencies/SwiftPackageManager/.build/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols" -gsp ./Resources/GoogleService-Info.plist -p ios ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}
    fi
    """
    
    static let swiftLint = TargetScript.pre(script: swiftLintScript, name: "SwiftLint", basedOnDependencyAnalysis: false)
    static let firebaseCrashlytics = TargetScript.pre(script: firebaseCrashlyticsScript, 
                                                      name: "FirebaseCrashlytics",
                                                      basedOnDependencyAnalysis: false)

}
