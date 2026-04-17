#!/usr/bin/env bash
# Purplemet Security Analysis — Shared Script
#
# Single source of truth for building CLI arguments, running the analysis,
# parsing results, and printing summaries. Used by all CI/CD integrations.
#
# All configuration via PURPLEMET_* environment variables.
# See integrations/CONVENTIONS.md for the full variable list.
#
# Usage:
#   - Execute directly:  ./analyze.sh
#   - Source for functions:  source analyze.sh
#
# Required env vars:
#   PURPLEMET_API_TOKEN    — API authentication token
#   PURPLEMET_TARGET_URL   — URL to analyze
#
# Optional env vars: see CONVENTIONS.md §1

set -o pipefail

# ── Validate required inputs ──────────────────────────
purplemet_validate() {
  if [ -z "${PURPLEMET_TARGET_URL}" ]; then
    echo "ERROR: PURPLEMET_TARGET_URL is not set." >&2
    echo "Set it as a pipeline variable." >&2
    return 5
  fi
  if [ -z "${PURPLEMET_API_TOKEN}" ]; then
    echo "ERROR: PURPLEMET_API_TOKEN is not set." >&2
    echo "Add it as a secured/masked secret in your CI platform." >&2
    return 5
  fi
}

# ── Build CLI argument array ─────────────────────────
# Reads PURPLEMET_* env vars, populates the global PURPLEMET_ARGS array.
purplemet_build_args() {
  PURPLEMET_ARGS=("analyze" "${PURPLEMET_TARGET_URL}")
  PURPLEMET_ARGS+=("--format" "${PURPLEMET_FORMAT:-json}")

  [ -n "${PURPLEMET_FAIL_SEVERITY}" ] \
    && PURPLEMET_ARGS+=("--fail-on-severity" "${PURPLEMET_FAIL_SEVERITY}")

  [ "${PURPLEMET_WAIT_TIMEOUT:-300000}" != "0" ] \
    && PURPLEMET_ARGS+=("--wait-timeout" "${PURPLEMET_WAIT_TIMEOUT:-300000}")

  [ -n "${PURPLEMET_FAIL_RATING}" ] \
    && PURPLEMET_ARGS+=("--fail-on-rating" "${PURPLEMET_FAIL_RATING}")

  [ "${PURPLEMET_FAIL_CVSS:-0}" != "0" ] \
    && PURPLEMET_ARGS+=("--fail-on-cvss" "${PURPLEMET_FAIL_CVSS}")

  [ "${PURPLEMET_FAIL_ON_EOL:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-eol")

  [ "${PURPLEMET_FAIL_ON_SSL:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-ssl")

  [ "${PURPLEMET_FAIL_ON_CERT:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-cert")

  [ -n "${PURPLEMET_EXCLUDE_TECH}" ] \
    && PURPLEMET_ARGS+=("--exclude-tech" "${PURPLEMET_EXCLUDE_TECH}")

  [ "${PURPLEMET_EXCLUDE_IGNORED:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--exclude-ignored")

  [ "${PURPLEMET_FAIL_ON_HEADERS:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-headers")

  [ "${PURPLEMET_FAIL_ON_COOKIES:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-cookies")

  [ "${PURPLEMET_FAIL_ON_UNSAFE:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-unsafe")

  [ "${PURPLEMET_FAIL_ON_KEV:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-kev")

  [ "${PURPLEMET_FAIL_ON_EPSS:-0}" != "0" ] \
    && PURPLEMET_ARGS+=("--fail-on-epss" "${PURPLEMET_FAIL_ON_EPSS}")

  [ "${PURPLEMET_FAIL_ON_ACTIVE_EXPLOITS:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-active-exploits")

  [ "${PURPLEMET_FAIL_ON_OSSF_SCORE:-0}" != "0" ] \
    && PURPLEMET_ARGS+=("--fail-on-ossf-score" "${PURPLEMET_FAIL_ON_OSSF_SCORE}")

  [ "${PURPLEMET_FAIL_ON_CERT_EXPIRY:-0}" != "0" ] \
    && PURPLEMET_ARGS+=("--fail-on-cert-expiry" "${PURPLEMET_FAIL_ON_CERT_EXPIRY}")

  [ "${PURPLEMET_FAIL_ON_ISSUE_COUNT:-0}" != "0" ] \
    && PURPLEMET_ARGS+=("--fail-on-issue-count" "${PURPLEMET_FAIL_ON_ISSUE_COUNT}")

  [ "${PURPLEMET_REQUIRE_WAF:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--require-waf")

  [ "${PURPLEMET_FAIL_ON_SENSITIVE_SERVICES:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--fail-on-sensitive-services")

  [ "${PURPLEMET_NO_CREATE:-false}" = "true" ] \
    && PURPLEMET_ARGS+=("--no-create")

  return 0
}

# ── File extension for the configured format ──────────
# Echoes the extension (no leading dot) to use for the report file.
purplemet_report_ext() {
  case "${PURPLEMET_FORMAT:-json}" in
    json)  echo "json" ;;
    sarif) echo "sarif" ;;
    html)  echo "html" ;;
    human) echo "txt" ;;
    *)     echo "json" ;;
  esac
}

# ── Run the analysis ──────────────────────────────────
# Sets: PURPLEMET_EXIT_CODE, PURPLEMET_REPORT_FILE
purplemet_run_analysis() {
  local output_dir="${PURPLEMET_OUTPUT_DIR:-.}"
  local ext
  ext=$(purplemet_report_ext)
  PURPLEMET_REPORT_FILE="${output_dir}/purplemet-report.${ext}"

  [ -n "${PURPLEMET_BASE_URL}" ] && export PURPLEMET_BASE_URL

  echo "Running: purplemet-cli ${PURPLEMET_ARGS[*]}"
  echo "──────────────────────────────────────────"

  set +e
  purplemet-cli "${PURPLEMET_ARGS[@]}" 2> >(tee "${output_dir}/purplemet-stderr.log" >&2) \
    | tee "${PURPLEMET_REPORT_FILE}"
  PURPLEMET_EXIT_CODE=${PIPESTATUS[0]}
  set -e
}

# ── Parse JSON results ────────────────────────────────
# Sets: PURPLEMET_RESULT_RATING, PURPLEMET_RESULT_ISSUES, PURPLEMET_RESULT_BREAKDOWN,
#       PURPLEMET_RESULT_FAILED_GATES
purplemet_parse_results() {
  local output_dir="${PURPLEMET_OUTPUT_DIR:-.}"
  PURPLEMET_RESULT_RATING="N/A"
  PURPLEMET_RESULT_ISSUES="0"
  PURPLEMET_RESULT_BREAKDOWN=""
  PURPLEMET_RESULT_FAILED_GATES=""

  # Only parse when the report is JSON (other formats aren't jq-readable).
  if [ "${PURPLEMET_FORMAT:-json}" = "json" ] \
     && command -v jq > /dev/null 2>&1 \
     && [ -f "${output_dir}/purplemet-report.json" ]; then
    PURPLEMET_RESULT_RATING=$(jq -r '.analysis.rating // "N/A"' \
      "${output_dir}/purplemet-report.json" 2>/dev/null || echo "N/A")
    PURPLEMET_RESULT_ISSUES=$(jq -r '.analysis.issueCnt // 0' \
      "${output_dir}/purplemet-report.json" 2>/dev/null || echo "0")

    # Extract issue breakdown by severity
    PURPLEMET_RESULT_BREAKDOWN=$(jq -r '
      .analysis.issueCnts // {} |
      to_entries |
      map(select(.key | test("^(CRITICAL|HIGH|MEDIUM|LOW|INFO)$")) | select(.value > 0)) |
      map("\(.value) \(.key | ascii_downcase)") |
      join(", ")' \
      "${output_dir}/purplemet-report.json" 2>/dev/null || echo "")

    # Extract failed gates
    PURPLEMET_RESULT_FAILED_GATES=$(jq -r '
      .gates // {} |
      to_entries |
      map(select(.value.passed == false)) |
      map(.key + " (" +
        (if .value.issueCount then "\(.value.issueCount) issues"
         elif .value.value then "value: \(.value.value)"
         elif .value.maxScore then "max: \(.value.maxScore)"
         else "failed" end) + ")") |
      join(", ")' \
      "${output_dir}/purplemet-report.json" 2>/dev/null || echo "")
  fi
}

# ── List configured gates ─────────────────────────────
# Echoes one "name|threshold" line per gate enabled via env vars.
purplemet_list_configured_gates() {
  [ -n "${PURPLEMET_FAIL_SEVERITY}" ] \
    && echo "severity|>= ${PURPLEMET_FAIL_SEVERITY}"
  [ -n "${PURPLEMET_FAIL_RATING}" ] \
    && echo "rating|worse than ${PURPLEMET_FAIL_RATING}"
  [ "${PURPLEMET_FAIL_CVSS:-0}" != "0" ] \
    && echo "cvss|>= ${PURPLEMET_FAIL_CVSS}"
  [ "${PURPLEMET_FAIL_ON_EOL:-false}" = "true" ] \
    && echo "eol|any end-of-life tech"
  [ "${PURPLEMET_FAIL_ON_SSL:-false}" = "true" ] \
    && echo "ssl|any SSL/TLS issue"
  [ "${PURPLEMET_FAIL_ON_CERT:-false}" = "true" ] \
    && echo "certificates|any cert issue"
  [ "${PURPLEMET_FAIL_ON_HEADERS:-false}" = "true" ] \
    && echo "headers|any security header issue"
  [ "${PURPLEMET_FAIL_ON_COOKIES:-false}" = "true" ] \
    && echo "cookies|any cookie issue"
  [ "${PURPLEMET_FAIL_ON_UNSAFE:-false}" = "true" ] \
    && echo "unsafe|any unsafe practice"
  [ "${PURPLEMET_FAIL_ON_KEV:-false}" = "true" ] \
    && echo "kev|any CISA KEV CVE"
  [ "${PURPLEMET_FAIL_ON_EPSS:-0}" != "0" ] \
    && echo "epss|>= ${PURPLEMET_FAIL_ON_EPSS}"
  [ "${PURPLEMET_FAIL_ON_ACTIVE_EXPLOITS:-false}" = "true" ] \
    && echo "active-exploits|any actively exploited CVE"
  [ "${PURPLEMET_FAIL_ON_OSSF_SCORE:-0}" != "0" ] \
    && echo "ossf-score|< ${PURPLEMET_FAIL_ON_OSSF_SCORE}"
  [ "${PURPLEMET_FAIL_ON_CERT_EXPIRY:-0}" != "0" ] \
    && echo "cert-expiry|< ${PURPLEMET_FAIL_ON_CERT_EXPIRY} days"
  [ "${PURPLEMET_FAIL_ON_ISSUE_COUNT:-0}" != "0" ] \
    && echo "issue-count|>= ${PURPLEMET_FAIL_ON_ISSUE_COUNT}"
  [ "${PURPLEMET_REQUIRE_WAF:-false}" = "true" ] \
    && echo "waf|require WAF"
  [ "${PURPLEMET_FAIL_ON_SENSITIVE_SERVICES:-false}" = "true" ] \
    && echo "sensitive-services|any sensitive service exposed"
  [ -n "${PURPLEMET_EXCLUDE_TECH}" ] \
    && echo "excluded-tech|${PURPLEMET_EXCLUDE_TECH}"
}

# ── Print human-readable summary ──────────────────────
purplemet_print_summary() {
  local output_dir="${PURPLEMET_OUTPUT_DIR:-.}"

  echo ""
  echo "══════════════════════════════════════════"
  echo "  PURPLEMET ANALYSIS RESULTS"
  echo "══════════════════════════════════════════"
  echo "  Target:     ${PURPLEMET_TARGET_URL}"
  echo "  Rating:     ${PURPLEMET_RESULT_RATING}"
  echo "  Issues:     ${PURPLEMET_RESULT_ISSUES}"

  if [ -n "${PURPLEMET_RESULT_BREAKDOWN}" ]; then
    echo "  Breakdown:  ${PURPLEMET_RESULT_BREAKDOWN}"
  fi

  # ── Gates section ──
  local gates_list
  gates_list=$(purplemet_list_configured_gates)

  echo "──────────────────────────────────────────"
  if [ -z "${gates_list}" ]; then
    echo "  Gates:      none configured (report-only mode)"
  else
    echo "  Gates configured:"
    # Pretty-print "name|threshold" with column alignment
    local name threshold
    while IFS='|' read -r name threshold; do
      [ -z "${name}" ] && continue
      printf "    - %-20s %s\n" "${name}" "${threshold}"
    done <<< "${gates_list}"
  fi

  # ── Result section ──
  echo "──────────────────────────────────────────"
  case "${PURPLEMET_EXIT_CODE}" in
    0)
      echo "  Result:     PASSED — all gates satisfied"
      ;;
    1)
      echo "  Result:     FAILED — one or more gates failed"
      if [ -n "${PURPLEMET_RESULT_FAILED_GATES}" ]; then
        echo "  Failed:     ${PURPLEMET_RESULT_FAILED_GATES}"
      fi
      # Show every gate-related line from the CLI's stderr (authoritative)
      if [ -s "${output_dir}/purplemet-stderr.log" ]; then
        local gate_msgs
        gate_msgs=$(grep -i "gate" "${output_dir}/purplemet-stderr.log" 2>/dev/null || true)
        if [ -n "${gate_msgs}" ]; then
          echo "  Reason(s):"
          while IFS= read -r line; do
            [ -z "${line}" ] && continue
            echo "    • ${line}"
          done <<< "${gate_msgs}"
        fi
      fi
      ;;
    2) echo "  Result:     ERROR — analysis failed on Purplemet side" ;;
    3) echo "  Result:     ERROR — analysis timed out" ;;
    4) echo "  Result:     ERROR — network/API error" ;;
    5) echo "  Result:     ERROR — CLI usage error" ;;
    6) echo "  Result:     ERROR — API contract error" ;;
    *) echo "  Result:     ERROR (code ${PURPLEMET_EXIT_CODE})" ;;
  esac
  echo "  Exit code:  ${PURPLEMET_EXIT_CODE}"
  echo "══════════════════════════════════════════"

  # ── Non-gate warnings from stderr ──
  if [ -s "${output_dir}/purplemet-stderr.log" ]; then
    local warnings
    warnings=$(grep -iv "gate" "${output_dir}/purplemet-stderr.log" 2>/dev/null || true)
    if [ -n "${warnings}" ]; then
      echo ""
      echo "Warnings:"
      echo "${warnings}" >&2
    fi
  fi
}

# ── Generate dotenv report ────────────────────────────
purplemet_generate_dotenv() {
  local output_dir="${PURPLEMET_OUTPUT_DIR:-.}"
  cat > "${output_dir}/purplemet-report.env" <<EOF
PURPLEMET_EXIT_CODE=${PURPLEMET_EXIT_CODE}
PURPLEMET_RATING=${PURPLEMET_RESULT_RATING}
PURPLEMET_ISSUES=${PURPLEMET_RESULT_ISSUES}
PURPLEMET_TARGET=${PURPLEMET_TARGET_URL}
EOF
}

# ── Main (when executed directly, not sourced) ────────
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ -z "${BASH_SOURCE[0]}" ]; then
  purplemet_validate || exit $?
  purplemet_build_args
  purplemet_run_analysis
  purplemet_parse_results
  purplemet_print_summary
  purplemet_generate_dotenv
  exit "${PURPLEMET_EXIT_CODE}"
fi
