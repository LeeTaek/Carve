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
/// - 상수마다 주석 한 줄에 무엇을 바꾸는지 · Debug 전용인지 · 읽는 곳을 적는다. Debug 전용 인자는 읽는 쪽이 `#if DEBUG` 안에 있어 Release 에서는 효과가 없다.
/// - 쓰는 절차(장 시드 · HUD · 표시 진단)는 `docs/device-simulator-verification.md` · `docs/device-debugging-cli.md` 에 있다.
public enum LaunchArgument {

    // MARK: - 필사 화면 경로 · 시작 장

    /// 저장된 flag(`singleCanvasEnabled`)와 관계없이 단일 Canvas 경로를 쓴다. Debug 전용. 읽는 곳: `CarveDetailFeature.State.usesSingleCanvas`.
    public static let singleCanvas = "-SingleCanvas"
    /// 뒤의 값(`BibleChapter` JSON, 예: `{"title":"1-19Psalms.txt","chapter":119}`)을 시작 장으로 저장한다. Debug 전용. 읽는 곳: `UITestLaunchChapter.apply`.
    public static let uiTestChapter = "-UITestChapter"

    // MARK: - 레이아웃 검증 (설계 §18-3)

    /// 레이아웃 오버레이와 HUD(`Δ max` · `columnX` · `gate`)를 그린다. Debug 전용. 읽는 곳: `ChapterLayoutDebugFlags.isOverlayEnabled`.
    public static let chapterLayoutOverlay = "-ChapterLayoutOverlay"
    /// settle 8초 뒤 11단계에 걸쳐 마지막 절까지 스스로 스크롤한다. Debug 전용. 읽는 곳: `ChapterLayoutDebugScenario.isScrollEnabled`.
    public static let chapterLayoutAutoScroll = "-ChapterLayoutAutoScroll"
    /// settle 8초 뒤 다음 장으로 스스로 넘어간다. Debug 전용. 읽는 곳: `ChapterLayoutDebugScenario.isNextChapterEnabled`.
    public static let chapterLayoutAutoNext = "-ChapterLayoutAutoNext"

    // MARK: - 캔버스 진단 (주로 실기기)

    /// 화면에 붙은 캔버스와 Store 의 drawing 을 0.5초마다 비교해 콘솔에 찍는다(읽기 전용). Debug 전용. 읽는 곳: `ChapterCanvasView.makeUIViewController`.
    public static let canvasDisplayProbe = "-CanvasDisplayProbe"
    /// 표시 진단이 원격 실험 명령(notify `kr.co.carve.canvas-probe.*`)을 받는다 — `-CanvasDisplayProbe` 와 함께 쓴다. Debug 전용. 읽는 곳: `ChapterCanvasDisplayProbe.init`.
    public static let canvasDisplayExperiments = "-CanvasDisplayExperiments"
    /// ⚠️ D9 H 수정(표시용 획 재구성)을 끄고 결함을 재현하는 opt-out — 기본 검증에는 쓰지 않는다. Debug 전용. 읽는 곳: `ChapterCanvasController.reusesStrokesOnApply`.
    public static let canvasReuseStrokesOnApply = "-CanvasReuseStrokesOnApply"
    /// footprint 와 jetsam 한도까지 남은 메모리를 100ms 마다 재어 최저 여유를 찍는다(R20). Debug 전용. 읽는 곳: `ChapterCanvasView`(`ChapterCanvasMemoryProbe.launchArgument`).
    public static let canvasMemoryProbe = "-CanvasMemoryProbe"
    /// 올가미 조작 때 캔버스의 획 · 도구 · undo 상태를 찍는다(읽기 전용). Debug 전용. 읽는 곳: `ChapterCanvasView`(`ChapterCanvasLassoProbe.launchArgument`).
    public static let lassoProbe = "-LassoProbe"

    // MARK: - 스크롤 스파이크 하네스 (설계 §11)

    /// 앱 대신 사용자 저장소와 연결되지 않는 스크롤 스파이크 하네스(`CanvasScrollSpikeView`)를 띄운다. Debug 전용. 읽는 곳: `CarveApp.body`.
    public static let canvasScrollSpike = "-CanvasScrollSpike"
    /// 뒤의 값(`A` · `B`, 기본 `B`)으로 하네스의 호스팅 구조를 고른다. Debug 전용. 읽는 곳: `SpikeLaunchOptions.parse`.
    public static let canvasScrollSpikeMode = "-CanvasScrollSpikeMode"
    /// 화면이 뜬 뒤 하네스의 자동 시나리오(왕복 · bounce · 헤더 · 왼손 · 폭 축소)를 돈다. Debug 전용. 읽는 곳: `SpikeLaunchOptions.parse`.
    public static let canvasScrollSpikeAuto = "-CanvasScrollSpikeAuto"
    /// 뒤의 값(pt) offset 으로 이동해 멈춘다 — 있으면 자동 시나리오는 돌지 않는다. Debug 전용. 읽는 곳: `SpikeLaunchOptions.parse`.
    public static let canvasScrollSpikeJump = "-CanvasScrollSpikeJump"
    /// 하네스를 왼손잡이 레이아웃으로 시작한다. Debug 전용. 읽는 곳: `SpikeLaunchOptions.parse`.
    public static let canvasScrollSpikeLeftHanded = "-CanvasScrollSpikeLeftHanded"
    /// 하네스의 필사 컬럼 폭을 줄여 시작한다(Split View resize 근사). Debug 전용. 읽는 곳: `SpikeLaunchOptions.parse`.
    public static let canvasScrollSpikeNarrow = "-CanvasScrollSpikeNarrow"
    /// 하네스 캔버스를 손가락 필기 허용(`.anyInput`)으로 시작한다. Debug 전용. 읽는 곳: `SpikeLaunchOptions.parse`.
    public static let canvasScrollSpikeAnyInput = "-CanvasScrollSpikeAnyInput"
    /// A 모드에서 offset · inset · zoom 정규화를 레이아웃마다 적용한다. Debug 전용. 읽는 곳: `SpikeLaunchOptions.parse`.
    public static let canvasScrollSpikeNormalizeA = "-CanvasScrollSpikeNormalizeA"

    // MARK: - 저장소 시험

    /// 시뮬레이터 · dev 컨테이너에서 확인된 계정을 저장소 소유자로 가정한다(ACC-1 2차 전용, 소유 증명이 아니다). Debug 전용. 읽는 곳: `StoreOwnershipInjection.isEnabled`.
    public static let acc1InjectStoreOwnership = "-ACC1InjectStoreOwnership"

    // MARK: - 앱 코드가 읽지 않는 인자

    /// Firebase Analytics 디버그 모드를 켠다. 빌드 구성과 무관하다. 앱 코드가 아니라 Firebase SDK 가 읽는다 — 스킴(`App/CarveApp/Project.swift`)의 실행 인자로만 넣는다.
    public static let firDebugEnabled = "-FIRDebugEnabled"
    /// UserDefaults 인자 도메인으로 `hasSeenFirstRunGuide` 키를 덮는다(뒤에 `YES`, 빌드 구성과 무관). 값이 문자열이라 `@Shared(.appStorage)` 의 Bool 로 읽히지 않아 효과가 없을 수 있다. 넣는 곳: UI 테스트.
    public static let hasSeenFirstRunGuide = "-hasSeenFirstRunGuide"
}
