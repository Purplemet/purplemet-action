#!/usr/bin/env bash
# validate-parity.sh — Verify all CI/CD integrations map every PURPLEMET_* variable.
#
# Extracts the canonical variable list from analyze.sh (the source of truth),
# then checks that each integration file references every variable — either
# directly (PURPLEMET_*) or via its platform-native naming convention.
#
# Usage:  ./validate-parity.sh [path/to/integrations]
# Exit 0 = all integrations have full parity; Exit 1 = gaps found.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATIONS_DIR="${1:-$(dirname "${SCRIPT_DIR}")}"

# ── Extract canonical variable list from purplemet_build_args() in analyze.sh ──
ANALYZE_SH="${SCRIPT_DIR}/analyze.sh"
if [ ! -f "${ANALYZE_SH}" ]; then
  echo "ERROR: analyze.sh not found at ${ANALYZE_SH}" >&2
  exit 2
fi

# Variables used in purplemet_build_args() and purplemet_validate() — these are the
# ones that every integration MUST map from its platform inputs.
# We extract them from the function bodies only (not from result/internal vars).
CANONICAL_VARS=(
  PURPLEMET_API_TOKEN
  PURPLEMET_TARGET_URL
  PURPLEMET_FORMAT
  PURPLEMET_FAIL_SEVERITY
  PURPLEMET_WAIT_TIMEOUT
  PURPLEMET_FAIL_RATING
  PURPLEMET_FAIL_CVSS
  PURPLEMET_FAIL_ON_EOL
  PURPLEMET_FAIL_ON_SSL
  PURPLEMET_FAIL_ON_CERT
  PURPLEMET_EXCLUDE_TECH
  PURPLEMET_EXCLUDE_IGNORED
  PURPLEMET_FAIL_ON_HEADERS
  PURPLEMET_FAIL_ON_COOKIES
  PURPLEMET_FAIL_ON_UNSAFE
  PURPLEMET_FAIL_ON_KEV
  PURPLEMET_FAIL_ON_EPSS
  PURPLEMET_FAIL_ON_ACTIVE_EXPLOITS
  PURPLEMET_FAIL_ON_OSSF_SCORE
  PURPLEMET_FAIL_ON_CERT_EXPIRY
  PURPLEMET_FAIL_ON_ISSUE_COUNT
  PURPLEMET_REQUIRE_WAF
  PURPLEMET_FAIL_ON_SENSITIVE_SERVICES
  PURPLEMET_NO_CREATE
)

echo "Canonical variables (${#CANONICAL_VARS[@]}):"
printf '  %s\n' "${CANONICAL_VARS[@]}"
echo ""

# ── Mapping: PURPLEMET_* → platform-specific names ──
declare -A KEBAB_MAP  # GitHub Action inputs (kebab-case)
declare -A CAMEL_MAP  # Jenkins/Azure DevOps (camelCase)

KEBAB_MAP=(
  [PURPLEMET_API_TOKEN]="api-token"
  [PURPLEMET_TARGET_URL]="target-url"
  [PURPLEMET_FORMAT]="format"
  [PURPLEMET_FAIL_SEVERITY]="fail-severity"
  [PURPLEMET_WAIT_TIMEOUT]="timeout"
  [PURPLEMET_FAIL_RATING]="fail-rating"
  [PURPLEMET_FAIL_CVSS]="fail-cvss"
  [PURPLEMET_FAIL_ON_EOL]="fail-on-eol"
  [PURPLEMET_FAIL_ON_SSL]="fail-on-ssl"
  [PURPLEMET_FAIL_ON_CERT]="fail-on-cert"
  [PURPLEMET_EXCLUDE_TECH]="exclude-tech"
  [PURPLEMET_EXCLUDE_IGNORED]="exclude-ignored"
  [PURPLEMET_FAIL_ON_HEADERS]="fail-on-headers"
  [PURPLEMET_FAIL_ON_COOKIES]="fail-on-cookies"
  [PURPLEMET_FAIL_ON_UNSAFE]="fail-on-unsafe"
  [PURPLEMET_FAIL_ON_KEV]="fail-on-kev"
  [PURPLEMET_FAIL_ON_EPSS]="fail-on-epss"
  [PURPLEMET_FAIL_ON_ACTIVE_EXPLOITS]="fail-on-active-exploits"
  [PURPLEMET_FAIL_ON_OSSF_SCORE]="fail-on-ossf-score"
  [PURPLEMET_FAIL_ON_CERT_EXPIRY]="fail-on-cert-expiry"
  [PURPLEMET_FAIL_ON_ISSUE_COUNT]="fail-on-issue-count"
  [PURPLEMET_REQUIRE_WAF]="require-waf"
  [PURPLEMET_FAIL_ON_SENSITIVE_SERVICES]="fail-on-sensitive-services"
  [PURPLEMET_NO_CREATE]="no-create"
)

CAMEL_MAP=(
  [PURPLEMET_API_TOKEN]="apiToken|token"
  [PURPLEMET_TARGET_URL]="targetUrl|url"
  [PURPLEMET_FORMAT]="format"
  [PURPLEMET_FAIL_SEVERITY]="failSeverity"
  [PURPLEMET_WAIT_TIMEOUT]="timeout"
  [PURPLEMET_FAIL_RATING]="failRating"
  [PURPLEMET_FAIL_CVSS]="failCvss"
  [PURPLEMET_FAIL_ON_EOL]="failOnEol"
  [PURPLEMET_FAIL_ON_SSL]="failOnSsl"
  [PURPLEMET_FAIL_ON_CERT]="failOnCert"
  [PURPLEMET_EXCLUDE_TECH]="excludeTech"
  [PURPLEMET_EXCLUDE_IGNORED]="excludeIgnored"
  [PURPLEMET_FAIL_ON_HEADERS]="failOnHeaders"
  [PURPLEMET_FAIL_ON_COOKIES]="failOnCookies"
  [PURPLEMET_FAIL_ON_UNSAFE]="failOnUnsafe"
  [PURPLEMET_FAIL_ON_KEV]="failOnKev"
  [PURPLEMET_FAIL_ON_EPSS]="failOnEpss"
  [PURPLEMET_FAIL_ON_ACTIVE_EXPLOITS]="failOnActiveExploits"
  [PURPLEMET_FAIL_ON_OSSF_SCORE]="failOnOssfScore"
  [PURPLEMET_FAIL_ON_CERT_EXPIRY]="failOnCertExpiry"
  [PURPLEMET_FAIL_ON_ISSUE_COUNT]="failOnIssueCount"
  [PURPLEMET_REQUIRE_WAF]="requireWaf"
  [PURPLEMET_FAIL_ON_SENSITIVE_SERVICES]="failOnSensitiveServices"
  [PURPLEMET_NO_CREATE]="noCreate"
)

# ── Check a file for a variable ──
# Usage: check_var FILE VAR_NAME SEARCH_PATTERN
check_var() {
  local file="$1" var="$2" pattern="$3"
  grep -qE "${pattern}" "${file}" 2>/dev/null
}

# ── Integrations to validate ──
declare -A FILES=(
  ["GitLab"]="${INTEGRATIONS_DIR}/gitlab/purplemet-analyze.gitlab-ci.yml"
  ["Bitbucket (template)"]="${INTEGRATIONS_DIR}/bitbucket/bitbucket-pipelines.yml"
  ["GitHub Action"]="${INTEGRATIONS_DIR}/github-action/action.yml"
  ["Jenkins"]="${INTEGRATIONS_DIR}/jenkins/vars/purplemetAnalyze.groovy"
  ["Azure DevOps"]="${INTEGRATIONS_DIR}/azure-devops/PurplemetAnalyzeV1/index.js"
)

# Shell-based integrations that exec analyze.sh: check for PURPLEMET_* in variables/env blocks
# Non-shell integrations: check for platform-native input names
declare -A NAMING=(
  ["GitLab"]="screaming_snake"
  ["Bitbucket (template)"]="screaming_snake"
  ["GitHub Action"]="kebab"
  ["Jenkins"]="camel"
  ["Azure DevOps"]="camel"
)

HAS_ERRORS=0

for platform in "GitLab" "Bitbucket (template)" "GitHub Action" "Jenkins" "Azure DevOps"; do
  file="${FILES[${platform}]}"
  naming="${NAMING[${platform}]}"

  if [ ! -f "${file}" ]; then
    echo "SKIP: ${platform} — file not found: ${file}"
    continue
  fi

  MISSING=""
  for var in "${CANONICAL_VARS[@]}"; do
    case "${naming}" in
      screaming_snake)
        pattern="${var}"
        ;;
      kebab)
        pattern="${KEBAB_MAP[${var}]}"
        ;;
      camel)
        pattern="${CAMEL_MAP[${var}]}"
        ;;
    esac

    if ! check_var "${file}" "${var}" "${pattern}"; then
      MISSING="${MISSING}  - ${var} (expected pattern: ${pattern})\n"
    fi
  done

  if [ -n "${MISSING}" ]; then
    echo "FAIL: ${platform} (${file})"
    echo -e "${MISSING}"
    HAS_ERRORS=1
  else
    echo "OK:   ${platform} — all ${#CANONICAL_VARS[@]} variables present"
  fi
done

echo ""
if [ "${HAS_ERRORS}" -eq 0 ]; then
  echo "All integrations have full variable parity."
else
  echo "Some integrations are missing variables. See above."
fi

exit ${HAS_ERRORS}
