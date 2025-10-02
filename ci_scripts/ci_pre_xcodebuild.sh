#!/bin/sh
set -euo pipefail

# 1) 현재 워크플로의 CI 빌드 카운터를 읽어 타깃 빌드번호로 설정
#    (Xcode Cloud가 제공하는 표준 변수)
#    https://developer.apple.com/documentation/xcode/environment-variable-reference
TARGET_BUILD_NUMBER="$CI_BUILD_NUMBER"

# 2) 선택: 마케팅 버전이 바뀌면 빌드 번호를 1로 리셋하고 싶다면,
#    Xcode Cloud 환경변수에 BUILD_NUMBER_RESET_ON_VERSION_CHANGE=1 을 추가한 뒤
#    아래 블록의 주석을 해제해 사용하세요. (방법 B 참고)

if [ "${BUILD_NUMBER_RESET_ON_VERSION_CHANGE:-0}" = "1" ]; then
  MV=$(xcodebuild -showBuildSettings -quiet | awk '/MARKETING_VERSION/ {print $3; exit}')
  KEY="VERSION_BASE_$(echo "$MV" | tr . _)"
  BASE="${!KEY:-0}"
  TARGET_BUILD_NUMBER=$(( BASE + CI_BUILD_NUMBER ))
else
  TARGET_BUILD_NUMBER="$CI_BUILD_NUMBER"
fi

# 3) 타깃 빌드 번호 적용
xcrun agvtool new-version -all "$TARGET_BUILD_NUMBER"

echo "Applied CURRENT_PROJECT_VERSION=$TARGET_BUILD_NUMBER"
