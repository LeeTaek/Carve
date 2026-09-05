# Carve 프로젝트 지침

## 환경
- 이 저장소는 Tuist를 사용한다.
- 자동화 및 무인 검증에는 CLI 기반 워크플로를 우선 사용한다.
- 자동화 및 무인 검증에서는 테스트 실행에 Xcode MCP를 의존하지 않는다.
- 명시적으로 요청되지 않은 한 의존성 버전이나 빌드 설정은 수정하지 않는다.
- 이 앱은 iPad 전용이다. 빌드나 테스트 검증 시 iPhone destination을 사용하지 않는다.

## 아키텍처
- 기존의 TCA + MicroArchitecture 구조를 따른다.
- 현재 모듈 경계를 유지하는 작고 국소적인 변경을 우선한다.
- 작업과 무관한 광범위한 리팩토링은 피한다.

## 검증
- 검증은 Xcode MCP가 아니라 CLI 기반으로 수행한다.
- 항상 가장 좁은 관련 테스트 범위부터 실행한다.
- 기본 검증 경로는 `xcodebuild test`를 우선 사용한다.
- Tuist 특화 흐름이나 selective testing이 필요할 때는 `tuist test`를 사용한다.
- CLI 검증을 수행할 때는 iPhone simulator가 아니라 iPad simulator destination을 사용한다.

## 툴체인 제약 ★ 먼저 읽을 것

**Xcode 26.3 이 아니면 빌드되지 않는다.** 다른 버전을 쓰면 자사 코드와 무관한 곳에서 실패한다.

| 버전 | 결과 |
|---|---|
| **Xcode 26.3** | ✅ 유일하게 동작 (Swift 6.2.4) |
| Xcode 26.6 | ❌ Swift 6.3.3 에서 TCA 1.20.2 가 컴파일 실패 (`WritableKeyPath<Root, BindingState<Value>>` 의 `Sendable` 미충족) |
| Xcode 27.x | ❌ 위에 더해 의존성 배포 타깃(iOS 12/13, macOS 10.15)을 거부 |

의존성을 최신으로 올려도 해결되지 않는다 — `swift-syntax` 는 최신도 macOS 10.15,
`google-mobile-ads` 는 iOS 13 을 선언한다. TCA 핀 상향은 `@Shared` 의미론 변경 위험이 있어
별도 작업으로 분리한다.

**macOS 27 beta 에서는 Xcode GUI 실행이 막힌다.** `xcode-select` 도 Command Line Tools 를
가리키고 있을 수 있다. 두 문제 모두 `DEVELOPER_DIR` 로 우회한다 — GUI 게이팅은
앱 번들 안의 CLI 바이너리(`xcodebuild` / `simctl` / `devicectl` / `xctrace`)에 적용되지 않는다.

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer
```

**tuist 는 `.mise.toml` 로 4.39.0 에 고정돼 있다.** `PATH` 기본값과 다르므로 반드시
`mise x -- tuist ...` 로 실행한다.

## 공통 명령어

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer   # 모든 명령의 전제

mise x -- tuist generate --no-open        # 프로젝트 생성
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.2'
mise x -- swiftlint lint --quiet --config .swiftlint.yml <파일들>
```

- 회귀 기준선은 `docs/single-canvas-design.md` §19-4-2 에 기록돼 있다. **줄어들면 회귀다.**
- SwiftLint 주의: `identifier_name` 최소 길이 **2** (`x`/`y`/`id` 만 예외),
  `line_length` 180, `type_body_length` 300.
- 툴체인을 바꾼 뒤에는 `DerivedData` 를 지우고 클린 빌드한다. 다른 Swift 버전이 만든
  모듈 캐시가 남아 있으면 `unable to resolve module dependency` 로 실패한다.

## 실기기 검증

절차 전문은 `docs/phase-0a-d-device-test.md` 에 있다. 요점만:

- **Instruments 기록에는 USB 연결이 필수다.** Wi-Fi(`Transport Type: localNetwork`)에서는
  1~2초 만에 `Device disconnected` 로 끊기고, `Deferred` 모드라 그때까지의 데이터도 유실된다.
  `xcrun devicectl device info details --device <id> | grep "Transport Type"` 로 확인한다.
- **`Allocations` 템플릿은 쓰지 않는다.** 오버헤드가 커서 앱이 사실상 멈춘다.
  메모리·CPU 측정에는 **`Activity Monitor`** 를 쓴다(`sysmon-process` 스키마의
  `memory-physical-footprint` 가 목표 지표다).
- **기기 식별자가 도구마다 다르다.** `devicectl` 은 CoreDevice UUID,
  `xctrace` 와 `xcodebuild -destination` 은 하드웨어 UDID 를 쓴다.
  `xcrun xctrace list devices` 로 확인한다.
- 앱 인자를 넘길 때는 `--` 로 구분한다:
  `xcrun devicectl device process launch --device <id> <bundle> -- -MyFlag`
- 기록 중에는 **`pgrep`/`pkill` 로 프로세스를 건드리지 않는다.** 마무리 단계에 끼어들면
  트레이스가 템플릿 메타데이터 없이 저장되어 `xctrace export` 가 실패한다.

## 변경 정책
- 변경은 최소 범위로 유지한다.
- 폴더 구조를 재구성하지 않는다.
- 의존성을 업데이트하지 않는다.
- 명시적으로 요청되지 않은 한 CI, signing, build setting은 변경하지 않는다.

## 출력
- 작업에 다른 언어가 명시적으로 필요하지 않은 한, 모든 assistant 응답, 코드 주석, 설명, 생성 문서는 한글로 작성한다.
- 변경한 파일과 변경 이유를 요약한다.
- 어떤 방식으로 결과를 검증했는지 요약한다.
- 남아 있는 위험 요소나 후속 작업이 있으면 함께 알린다.
