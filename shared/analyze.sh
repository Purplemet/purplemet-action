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

# ── Build CLI argument string ─────────────────────────
# Reads PURPLEMET_* env vars, echoes the full argument string to stdout.
purplemet_build_args() {
  local args="analyze ${PURPLEMET_TARGET_URL}"
  args="${args} --format ${PURPLEMET_FORMAT:-json}"

  [ -n "${PURPLEMET_FAIL_SEVERITY}" ] \
    && args="${args} --fail-on-severity ${PURPLEMET_FAIL_SEVERITY}"

  [ "${PURPLEMET_WAIT_TIMEOUT:-300000}" != "0" ] \
    && args="${args} --wait-timeout ${PURPLEMET_WAIT_TIMEOUT:-300000}"

  [ -n "${PURPLEMET_FAIL_RATING}" ] \
    && args="${args} --fail-on-rating ${PURPLEMET_FAIL_RATING}"

  [ "${PURPLEMET_FAIL_CVSS:-0}" != "0" ] \
    && args="${args} --fail-on-cvss ${PURPLEMET_FAIL_CVSS}"

  [ "${PURPLEMET_FAIL_ON_EOL:-false}" = "true" ] \
    && args="${args} --fail-on-eol"

  [ "${PURPLEMET_FAIL_ON_SSL:-false}" = "true" ] \
    && args="${args} --fail-on-ssl"

  [ "${PURPLEMET_FAIL_ON_CERT:-false}" = "true" ] \
    && args="${args} --fail-on-cert"

  [ -n "${PURPLEMET_EXCLUDE_TECH}" ] \
    && args="${args} --exclude-tech ${PURPLEMET_EXCLUDE_TECH}"

  [ "${PURPLEMET_EXCLUDE_IGNORED:-false}" = "true" ] \
    && args="${args} --exclude-ignored"

  [ "${PURPLEMET_FAIL_ON_HEADERS:-false}" = "true" ] \
    && args="${args} --fail-on-headers"

  [ "${PURPLEMET_FAIL_ON_COOKIES:-false}" = "true" ] \
    && args="${args} --fail-on-cookies"

  [ "${PURPLEMET_FAIL_ON_UNSAFE:-false}" = "true" ] \
    && args="${args} --fail-on-unsafe"

  [ "${PURPLEMET_FAIL_ON_KEV:-false}" = "true" ] \
    && args="${args} --fail-on-kev"

  [ "${PURPLEMET_FAIL_ON_EPSS:-0}" != "0" ] \
    && args="${args} --fail-on-epss ${PURPLEMET_FAIL_ON_EPSS}"

  [ "${PURPLEMET_FAIL_ON_ACTIVE_EXPLOITS:-false}" = "true" ] \
    && args="${args} --fail-on-active-exploits"

  [ "${PURPLEMET_FAIL_ON_OSSF_SCORE:-0}" != "0" ] \
    && args="${args} --fail-on-ossf-score ${PURPLEMET_FAIL_ON_OSSF_SCORE}"

  [ "${PURPLEMET_FAIL_ON_CERT_EXPIRY:-0}" != "0" ] \
    && args="${args} --fail-on-cert-expiry ${PURPLEMET_FAIL_ON_CERT_EXPIRY}"

  [ "${PURPLEMET_FAIL_ON_ISSUE_COUNT:-0}" != "0" ] \
    && args="${args} --fail-on-issue-count ${PURPLEMET_FAIL_ON_ISSUE_COUNT}"

  [ "${PURPLEMET_REQUIRE_WAF:-false}" = "true" ] \
    && args="${args} --require-waf"

  [ "${PURPLEMET_FAIL_ON_SENSITIVE_SERVICES:-false}" = "true" ] \
    && args="${args} --fail-on-sensitive-services"

  [ "${PURPLEMET_NO_CREATE:-false}" = "true" ] \
    && args="${args} --no-create"

  echo "${args}"
}

# ── Run the analysis ──────────────────────────────────
# Sets: PURPLEMET_EXIT_CODE
purplemet_run_analysis() {
  local args="${1}"
  local output_dir="${PURPLEMET_OUTPUT_DIR:-.}"

  [ -n "${PURPLEMET_BASE_URL}" ] && export PURPLEMET_BASE_URL

  echo "Running: purplemet-cli ${args}"
  echo "──────────────────────────────────────────"

  set +e
  purplemet-cli ${args} 2>"${output_dir}/purplemet-stderr.log" \
    | tee "${output_dir}/purplemet-report.json"
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

  if command -v jq > /dev/null 2>&1 \
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

# ── Print human-readable summary ──────────────────────
purplemet_print_summary() {
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

  echo "──────────────────────────────────────────"
  echo "  Gate:       fail on severity >= ${PURPLEMET_FAIL_SEVERITY:-high}"

  case "${PURPLEMET_EXIT_CODE}" in
    0) echo "  Result:     PASSED" ;;
    1)
      echo "  Result:     FAILED — threshold exceeded"
      if [ -n "${PURPLEMET_RESULT_FAILED_GATES}" ]; then
        echo "  Failed:     ${PURPLEMET_RESULT_FAILED_GATES}"
      fi
      # Show the CLI's gate detail from stderr
      local output_dir="${PURPLEMET_OUTPUT_DIR:-.}"
      if [ -s "${output_dir}/purplemet-stderr.log" ]; then
        local gate_msg
        gate_msg=$(grep -i "gate" "${output_dir}/purplemet-stderr.log" 2>/dev/null || true)
        if [ -n "${gate_msg}" ]; then
          echo "  Detail:     ${gate_msg}"
        fi
      fi
      ;;
    2) echo "  Result:     ERROR — analysis failed" ;;
    3) echo "  Result:     ERROR — timeout" ;;
    4) echo "  Result:     ERROR — network/API error" ;;
    *) echo "  Result:     ERROR (code ${PURPLEMET_EXIT_CODE})" ;;
  esac

  echo "══════════════════════════════════════════"

  # Show non-gate warnings from stderr
  local output_dir="${PURPLEMET_OUTPUT_DIR:-.}"
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
  ARGS=$(purplemet_build_args)
  purplemet_run_analysis "${ARGS}"
  purplemet_parse_results
  purplemet_print_summary
  purplemet_generate_dotenv
  exit "${PURPLEMET_EXIT_CODE}"
fi
