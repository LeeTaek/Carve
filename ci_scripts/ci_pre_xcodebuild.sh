#!/usr/bin/env bash
set -Eeuo pipefail

# ---- 0) 환경 기본값 보정
CI_BUILD_NUMBER="${CI_BUILD_NUMBER:-1}"
BUILD_NUMBER_RESET_ON_VERSION_CHANGE="${BUILD_NUMBER_RESET_ON_VERSION_CHANGE:-0}"
XCODE_SCHEME="${XCODE_SCHEME:-}"
XCODE_WORKSPACE_PATH="${XCODE_WORKSPACE_PATH:-}"
XCODE_PROJECT_PATH="${XCODE_PROJECT_PATH:-}"
# 빌드 넘버 강제로 1로 설정
FORCE_BUILD_RESET="${FORCE_BUILD_RESET:-0}"

# ---- ) Test 단계에서는 빌드넘버 스크립트 생략
if [[ "${CI_XCODEBUILD_ACTION:-}" == "build-for-testing" ]] || [[ "${CI_XCODEBUILD_ACTION:-}" == "test-without-building" ]]; then
  echo "[ci_pre_xcodebuild] Detected Test phase (${CI_XCODEBUILD_ACTION}). Skipping build number update."
  exit 0
fi

# ---- 1) 프로젝트 디렉터리 계산
if [[ -n "${XCODE_WORKSPACE_PATH:-}" ]]; then
  PROJ_DIR="$(dirname "$XCODE_WORKSPACE_PATH")"
elif [[ -n "${XCODE_PROJECT_PATH:-}" ]]; then
  PROJ_DIR="$(dirname "$XCODE_PROJECT_PATH")"
elif [[ -d .git ]]; then
  PROJ_DIR="$(git rev-parse --show-toplevel)"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJ_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

cd "$PROJ_DIR"

# ---- 2) MARKETING_VERSION 읽기
if [[ "${CI_XCODE_CLOUD:-}" == "TRUE" || "${CI:-}" == "TRUE" ]]; then
  # Xcode Cloud 환경이라면 CI 변수 기반 경로 사용
  echo "[ci_pre_xcodebuild] Detected Xcode Cloud environment."
  SCHEME="${CI_XCODE_SCHEME:-$XCODE_SCHEME}"
  PROJECT_PATH="${CI_PROJECT_FILE_PATH:-$XCODE_PROJECT_PATH}"
  if [[ -n "$PROJECT_PATH" && -f "$PROJECT_PATH" ]]; then
    MV=$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/ {print $3; exit}' || true)
  elif [[ -n "$PROJECT_PATH" && "$PROJECT_PATH" == *.xcworkspace ]]; then
    MV=$(xcodebuild -workspace "$PROJECT_PATH" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/ {print $3; exit}' || true)
  else
    MV="unknown"
  fi
else
  # 로컬 실행 시 기존 로직 유지
  MV="$(xcodebuild -scheme "$XCODE_SCHEME" -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/ {print $3; exit}' || true)"
fi
MV="${MV:-unknown}"
echo "[ci_pre_xcodebuild] MARKETING_VERSION=$MV"

# ---- 3) App Store Connect 인증 정보 (Secrets에서 로드)
APP_ID="${APP_ID:-}"
ISSUER_ID="${ISSUER_ID:-}"
KEY_ID="${KEY_ID:-}"
PRIVATE_KEY_PATH="./AuthKey_Temp.p8"

# PRIVATE_KEY를 임시 파일로 저장
if [[ -n "${PRIVATE_KEY:-}" ]]; then
  echo "$PRIVATE_KEY" > "$PRIVATE_KEY_PATH"
  chmod 600 "$PRIVATE_KEY_PATH"
else
  echo "[ci_pre_xcodebuild][WARN] PRIVATE_KEY not found. Skipping App Store Connect API lookup."
fi

# ---- 3.5) MARKETING_VERSION 변경 감지 (빌드번호 초기화)
VERSION_TRACK_FILE="$PROJ_DIR/.last_version"
LAST_VERSION=""
if [[ -f "$VERSION_TRACK_FILE" ]]; then
  LAST_VERSION=$(cat "$VERSION_TRACK_FILE")
fi


RESET_VERSION_FLAG="false"
if [[ "$MV" != "$LAST_VERSION" && "$MV" != "unknown" ]]; then
  echo "[ci_pre_xcodebuild] MARKETING_VERSION changed: $LAST_VERSION → $MV. Resetting build number to 1."
  TARGET_BUILD_NUMBER=1
  echo "$MV" > "$VERSION_TRACK_FILE"
  RESET_VERSION_FLAG="true"
fi

# ---- 3.6) 강제 빌드넘버 초기화 (환경변수로 제어)
if [[ "$FORCE_BUILD_RESET" == "1" ]]; then
  echo "[ci_pre_xcodebuild] ⚠️ FORCE_BUILD_RESET=1 detected. Forcing build number to 1."
  TARGET_BUILD_NUMBER=1
  RESET_VERSION_FLAG="true"
fi

# ---- 4) App Store Connect API를 통한 최신 빌드넘버 조회
if [[ "$RESET_VERSION_FLAG" == "true" ]]; then
  echo "[ci_pre_xcodebuild] Version changed; skipping ASC build number lookup."
else
  TARGET_BUILD_NUMBER="$CI_BUILD_NUMBER"
  if [[ -n "${APP_ID:-}" && -f "$PRIVATE_KEY_PATH" && "$MV" != "unknown" ]]; then
    echo "[ci_pre_xcodebuild] Fetching latest build number for $MV from App Store Connect..."

    # JWT 생성 (유효기간 20분)
    JWT=$(ruby -r jwt -e "puts JWT.encode({iss: '$ISSUER_ID', exp: Time.now.to_i + 1200, aud: 'appstoreconnect-v1'}, File.read('$PRIVATE_KEY_PATH'), 'ES256', {kid: '$KEY_ID'})")

    # API 호출
    RESPONSE=$(curl -s \
      -H "Authorization: Bearer $JWT" \
      "https://api.appstoreconnect.apple.com/v1/builds?filter[app]=$APP_ID&sort=-uploadedDate&limit=10")

    LATEST_BUILD=$(echo "$RESPONSE" | jq -r --arg MV "$MV" '.data[] | select(.attributes.version==$MV) | .attributes.buildNumber' | head -n 1)
    LATEST_BUILD=${LATEST_BUILD:-0}

    if [[ -z "$LATEST_BUILD" || "$LATEST_BUILD" == "null" ]]; then
      TARGET_BUILD_NUMBER=1
      echo "[ci_pre_xcodebuild] No previous build found for $MV → Start from 1"
    else
      TARGET_BUILD_NUMBER=$((LATEST_BUILD + 1))
      echo "[ci_pre_xcodebuild] Found ASC build $LATEST_BUILD for version $MV → Next = $TARGET_BUILD_NUMBER"
    fi
  else
    echo "[ci_pre_xcodebuild][WARN] Could not query ASC; using CI_BUILD_NUMBER=$CI_BUILD_NUMBER"
  fi
fi

# ---- 5) agvtool 실행
PROJECT_PATH="$PROJ_DIR/App/CarveApp/CarveApp.xcodeproj"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "[ci_pre_xcodebuild][ERROR] Expected CarveApp.xcodeproj at $PROJECT_PATH but not found."
  exit 3
fi

cd "$(dirname "$PROJECT_PATH")"
echo "[ci_pre_xcodebuild] Found project at: $PROJECT_PATH"
/usr/bin/xcrun agvtool new-version -all "$TARGET_BUILD_NUMBER"

echo "[ci_pre_xcodebuild] ✅ Updated build number to $TARGET_BUILD_NUMBER for version $MV"
