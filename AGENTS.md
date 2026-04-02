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

## 공통 명령어
- 프로젝트 생성: `tuist generate`
- 기본 테스트 검증: `xcodebuild test`
- 선택적 Tuist 기반 검증: `tuist test`

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
