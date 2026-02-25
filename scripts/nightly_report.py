
import os
import datetime as dt
import requests
from google.cloud import bigquery


# MARK: - Environment

class Env:
    # Required
    GCP_PROJECT_ID = "GCP_PROJECT_ID"
    BQ_DATASET = "BQ_DATASET"
    GITHUB_TOKEN = "GITHUB_TOKEN"

    # Optional
    BQ_TABLE_PREFIX = "BQ_TABLE_PREFIX"
    GITHUB_OWNER = "GITHUB_OWNER"
    GITHUB_REPO = "GITHUB_REPO"
    NIGHTLY_ISSUE_NUMBER = "NIGHTLY_ISSUE_NUMBER"

    # Defaults
    DEFAULT_GITHUB_OWNER = "LeeTaek"
    DEFAULT_GITHUB_REPO = "Carve"
    DEFAULT_BQ_TABLE_PREFIX = "events_"
    DEFAULT_NIGHTLY_ISSUE_NUMBER = "2"


def env_required(key: str) -> str:
    value = os.environ.get(key)
    if value is None or value.strip() == "":
        raise RuntimeError(f"Missing required env: {key}")
    return value


def env_optional(key: str, default: str) -> str:
    value = os.environ.get(key)
    if value is None or value.strip() == "":
        return default
    return value


def kst_today_str() -> str:
    kst = dt.timezone(dt.timedelta(hours=9))
    return dt.datetime.now(tz=kst).strftime("%Y-%m-%d")


def build_bq_client() -> bigquery.Client:
    # google-github-actions/auth@v2 가 설정해준 ADC(Application Default Credentials)를 사용
    project_id = env_required(Env.GCP_PROJECT_ID)
    return bigquery.Client(project=project_id)


def query_top_errors(
    client: bigquery.Client,
    dataset: str,
    table_prefix: str,
) -> list[bigquery.table.Row]:
    project = env_required(Env.GCP_PROJECT_ID)

    # NOTE:
    # - Daily export 기준으로 events_YYYYMMDD 테이블이 생김.
    # - 비용 방지를 위해 _TABLE_SUFFIX로 날짜 범위를 제한.
    # - "최근 24시간 rolling" 기준(UTC 기반)으로 집계.
    query = f"""
    DECLARE end_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
    DECLARE start_ts TIMESTAMP DEFAULT TIMESTAMP_SUB(end_ts, INTERVAL 24 HOUR);
    DECLARE prev_start_ts TIMESTAMP DEFAULT TIMESTAMP_SUB(end_ts, INTERVAL 48 HOUR);

    WITH base AS (
      SELECT
        event_timestamp,
        event_name,
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'error_id') AS error_id,
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'feature_name') AS feature_name,
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'context') AS context
      FROM `{project}.{dataset}.{table_prefix}*`
      WHERE
        _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE(prev_start_ts))
                          AND FORMAT_DATE('%Y%m%d', DATE(end_ts))
        AND event_name = 'error_shown'
    ),
    windowed AS (
      SELECT
        error_id,
        feature_name,
        context,
        COUNTIF(TIMESTAMP_MICROS(event_timestamp) >= start_ts) AS count_24h,
        COUNTIF(
          TIMESTAMP_MICROS(event_timestamp) >= prev_start_ts
          AND TIMESTAMP_MICROS(event_timestamp) < start_ts
        ) AS count_prev_24h
      FROM base
      WHERE error_id IS NOT NULL
      GROUP BY error_id, feature_name, context
    ),
    ranked_context AS (
      SELECT
        error_id,
        ANY_VALUE(feature_name) AS feature_name,
        ARRAY_AGG(STRUCT(context, count_24h) ORDER BY count_24h DESC LIMIT 1)[OFFSET(0)].context AS top_context,
        SUM(count_24h) AS count_24h,
        SUM(count_prev_24h) AS count_prev_24h
      FROM windowed
      GROUP BY error_id
    )
    SELECT
      error_id,
      feature_name,
      top_context,
      count_24h,
      (count_24h - count_prev_24h) AS delta
    FROM ranked_context
    ORDER BY count_24h DESC
    LIMIT 3;
    """
    job = client.query(query)
    return list(job.result())


def github_get_issue(owner: str, repo: str, number: int, token: str) -> dict:
    url = f"https://api.github.com/repos/{owner}/{repo}/issues/{number}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
    }
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    return resp.json()


def github_update_issue(owner: str, repo: str, number: int, token: str, body: str) -> None:
    url = f"https://api.github.com/repos/{owner}/{repo}/issues/{number}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
    }
    resp = requests.patch(url, json={"body": body}, headers=headers, timeout=30)
    resp.raise_for_status()


def render_section(date_str: str, rows: list[bigquery.table.Row]) -> str:
    lines: list[str] = []
    lines.append(f"\n## {date_str}\n")
    lines.append("\n### ✅ Top 3 (데이터 기반: 오늘 제일 중요한 것)\n")

    if not rows:
        lines.append("- No `error_shown` events found in last 24h.\n")
        lines.append("\n---\n")
        return "".join(lines)

    for idx, row in enumerate(rows, start=1):
        error_id = row.get("error_id") or "UNKNOWN"
        feature_name = row.get("feature_name") or "Unknown"
        top_context = row.get("top_context") or "Unknown"
        count_24h = int(row.get("count_24h") or 0)
        delta = int(row.get("delta") or 0)
        delta_str = f"+{delta}" if delta >= 0 else str(delta)

        lines.append(f"{idx}) **[{error_id}]**\n")
        lines.append(f"   - Count / Trend: `x{count_24h}` (vs yesterday `{delta_str}`)\n")
        lines.append(f"   - Feature: `{feature_name}`\n")
        lines.append(f"   - Context: `{top_context}`\n")
        lines.append("   - Suggested labels: `area:*`, `prio:p*`, `status:*`\n")
        lines.append("   - Linked issue: \n\n")

    lines.append("\n---\n")
    lines.append("\n### 🎯 Suggested next actions (pick 1)\n")
    lines.append("- [ ] Top 1 이슈를 생성/업데이트하고 `go:fix` 라벨을 단다.\n")
    return "".join(lines)


def main() -> None:
    # 고정 repo: LeeTaek/Carve
    owner = env_optional(Env.GITHUB_OWNER, Env.DEFAULT_GITHUB_OWNER)
    repo = env_optional(Env.GITHUB_REPO, Env.DEFAULT_GITHUB_REPO)

    token = env_required(Env.GITHUB_TOKEN)
    issue_number = int(env_optional(Env.NIGHTLY_ISSUE_NUMBER, Env.DEFAULT_NIGHTLY_ISSUE_NUMBER))

    dataset = env_required(Env.BQ_DATASET)
    table_prefix = env_optional(Env.BQ_TABLE_PREFIX, Env.DEFAULT_BQ_TABLE_PREFIX)

    client = build_bq_client()
    rows = query_top_errors(client, dataset, table_prefix)

    today = kst_today_str()
    new_section = render_section(today, rows)

    issue = github_get_issue(owner, repo, issue_number, token)
    current_body = issue.get("body") or ""

    # 같은 날짜 섹션이 이미 있으면 중복 append 방지
    if f"## {today}" in current_body:
        print("Section already exists for today. Skipping update.")
        return

    updated_body = current_body.rstrip() + "\n" + new_section
    github_update_issue(owner, repo, issue_number, token, updated_body)
    print("Nightly report updated.")


if __name__ == "__main__":
    main()
