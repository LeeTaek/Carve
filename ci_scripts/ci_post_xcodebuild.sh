#!/usr/bin/env bash
# 아카이브가 끝나면 그 아카이브의 dSYM 을 Crashlytics 에 동기로 올린다.
#
# 앱 타깃의 「Firebase Crashlytics」 빌드 단계(Crashlytics/run)는 검증만 동기로 하고 업로드는 백그라운드로 돌린다.
# Xcode Cloud 빌드 머신은 빌드가 끝나면 곧 사라져 그 업로드가 콘솔에 닿지 않았다(2026-10-14 빌드 239, 시험 계획 T3-DSYM).
# 올리지 못해도 빌드를 실패로 만들지 않는다 — TestFlight 배포를 막지 않고, 경고를 남긴 뒤 수동 업로드(G-9)로 메운다.
set -uo pipefail

LOG_PREFIX="[ci_post_xcodebuild]"

# ---- 0) 아카이브 단계에서만, 아카이브가 성공했을 때만
if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  echo "$LOG_PREFIX ${CI_XCODEBUILD_ACTION:-unknown} 단계라 dSYM 업로드를 건너뛴다."
  exit 0
fi
if [[ "${CI_XCODEBUILD_EXIT_CODE:-0}" != "0" ]]; then
  echo "$LOG_PREFIX 아카이브가 실패해(종료 코드 ${CI_XCODEBUILD_EXIT_CODE}) dSYM 업로드를 건너뛴다."
  exit 0
fi

# ---- 1) 경로 — 패키지는 ci_post_clone.sh 의 tuist install 이 저장소 루트의 Tuist/.build/checkouts 에 받는다
REPO_DIR="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
UPLOAD_SYMBOLS="$REPO_DIR/Tuist/.build/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
GOOGLE_SERVICE_PLIST="$REPO_DIR/App/CarveApp/Support/GoogleService-Info.plist"
DSYMS_DIR="${CI_ARCHIVE_PATH:-}/dSYMs"

for required in "$UPLOAD_SYMBOLS" "$GOOGLE_SERVICE_PLIST" "$DSYMS_DIR"; do
  if [[ ! -e "$required" ]]; then
    echo "$LOG_PREFIX[WARN] 없음: $required — dSYM 을 올리지 못했다. 아카이브의 dSYMs 를 Crashlytics 콘솔에 수동으로 올린다."
    exit 0
  fi
done

# ---- 2) 올릴 dSYM — 앱에 들어가는 앱 · 위젯 · 프레임워크만. 아카이브의 dSYMs 에는 TCA 등 매크로 플러그인(맥에서 도는 컴파일러 도구)의 dSYM 도 있다
DSYMS=()
for dsym in "$DSYMS_DIR"/*.app.dSYM "$DSYMS_DIR"/*.appex.dSYM "$DSYMS_DIR"/*.framework.dSYM; do
  [[ -e "$dsym" ]] && DSYMS+=("$dsym")
done
if [[ ${#DSYMS[@]} -eq 0 ]]; then
  echo "$LOG_PREFIX[WARN] $DSYMS_DIR 에 앱 dSYM 이 없다 — 아카이브의 dSYMs 를 Crashlytics 콘솔에 수동으로 올린다."
  exit 0
fi

# UUID 를 남겨 콘솔 dSYM 목록과 맞춰 볼 수 있게 한다
echo "$LOG_PREFIX 올릴 dSYM ${#DSYMS[@]}개:"
for dsym in "${DSYMS[@]}"; do
  xcrun dwarfdump --uuid "$dsym" || true
done

# ---- 3) 동기 업로드
if "$UPLOAD_SYMBOLS" -gsp "$GOOGLE_SERVICE_PLIST" -p ios "${DSYMS[@]}"; then
  echo "$LOG_PREFIX ✅ dSYM 업로드 끝"
else
  echo "$LOG_PREFIX[WARN] upload-symbols 실패(종료 코드 $?) — 아카이브의 dSYMs 를 Crashlytics 콘솔에 수동으로 올린다."
fi
exit 0
