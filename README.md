# Purplemet Web ASM — GitHub Action

[![Marketplace](https://img.shields.io/badge/GitHub%20Marketplace-Purplemet%20Web%20ASM-purple?logo=github)](https://github.com/marketplace/actions/purplemet-web-asm)

Purplemet: Proactive Web Attack Surface Management. Discover real-time security insights with Purplemet's Web ASM platform.

Run automated security analyses on your web applications directly in your GitHub Actions workflows. Get a security rating, detailed vulnerability report, and optional GitHub Code Scanning integration.

## Quick Start

```yaml
- uses: purplemet/purplemet-action@v1
  with:
    api-token: ${{ secrets.PURPLEMET_API_TOKEN }}
    target-url: 'https://your-app.example.com'
```

## Usage

### Basic analysis

```yaml
name: Security Analysis
on: [push]

jobs:
  purplemet:
    runs-on: ubuntu-latest
    steps:
      - uses: purplemet/purplemet-action@v1
        with:
          api-token: ${{ secrets.PURPLEMET_API_TOKEN }}
          target-url: 'https://your-app.example.com'
          fail-severity: 'high'
```

### With GitHub Code Scanning (SARIF)

```yaml
name: Security Analysis
on: [push]

jobs:
  purplemet:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
    steps:
      - uses: actions/checkout@v4

      - uses: purplemet/purplemet-action@v1
        with:
          api-token: ${{ secrets.PURPLEMET_API_TOKEN }}
          target-url: 'https://your-app.example.com'
          sarif-upload: 'true'
```

Results appear in the **Security** tab of your repository under **Code scanning alerts**.

### Use outputs in subsequent steps

```yaml
- uses: purplemet/purplemet-action@v1
  id: analysis
  with:
    api-token: ${{ secrets.PURPLEMET_API_TOKEN }}
    target-url: 'https://your-app.example.com'
  continue-on-error: true

- name: Check results
  run: |
    echo "Rating: ${{ steps.analysis.outputs.rating }}"
    echo "Issues: ${{ steps.analysis.outputs.issues }}"
    if [ "${{ steps.analysis.outputs.exit-code }}" = "1" ]; then
      echo "::warning::Security issues found above threshold"
    fi
```

### Docker-based action

If you prefer using the Docker image instead of downloading the binary. The image includes the shared `analyze.sh` script which reads all `PURPLEMET_*` variables automatically:

```yaml
- uses: docker://ppmsupport/purplemet-cli:latest
  env:
    PURPLEMET_API_TOKEN: ${{ secrets.PURPLEMET_API_TOKEN }}
    PURPLEMET_TARGET_URL: 'https://your-app.example.com'
    PURPLEMET_FAIL_SEVERITY: 'high'
  with:
    entrypoint: /usr/local/share/purplemet/analyze.sh
```

All `PURPLEMET_*` variables from the [CONVENTIONS](https://dev.purplemet.com/purplemet/integrations/cli/-/blob/main/integrations/CONVENTIONS.md) are supported as environment variables.

## Inputs

### Core configuration

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-token` | **Yes** | — | Purplemet API token ([create one](https://cloud.purplemet.com/#/tokens/create)) |
| `target-url` | **Yes** | — | URL of the web application to analyze |
| `base-url` | No | — | API base URL override (e.g. `https://api.dev.purplemet.com`) |
| `version` | No | `latest` | CLI version to use (e.g. `v1.2.0`, `latest`) |
| `timeout` | No | `1800000` | Wait timeout in milliseconds (30 min, 0 = unlimited) |
| `format` | No | `json` | Output format: `json`, `human`, `sarif`, `html` |
| `no-create` | No | `false` | Do not auto-create site if URL not found |
| `sarif-upload` | No | `false` | Upload SARIF results to GitHub Code Scanning |

### Severity gates

| Input | Default | Description |
|-------|---------|-------------|
| `fail-severity` | `high` | Fail if issues at or above this severity: `critical`, `high`, `medium`, `low`, `info` |
| `fail-rating` | — | Fail if rating is at or below this grade (`A`-`F`) |
| `fail-on-issue-count` | `0` | Fail if total issue count is greater than or equal to this value |

### CVE / exploitability gates

| Input | Default | Description |
|-------|---------|-------------|
| `fail-cvss` | `0` | Fail if any CVE has CVSS score >= this value (e.g. `9.0`) |
| `fail-on-kev` | `false` | Fail if CISA Known Exploited Vulnerabilities are detected |
| `fail-on-epss` | `0` | Fail if any issue has EPSS score >= this value (`0.0`-`1.0`) |
| `fail-on-active-exploits` | `false` | Fail if actively exploited vulnerabilities are detected |

### Component / technology gates

| Input | Default | Description |
|-------|---------|-------------|
| `fail-on-eol` | `false` | Fail if end-of-life components are detected |
| `fail-on-unsafe` | `false` | Fail if unsafe component issues are detected |
| `fail-on-ossf-score` | `0` | Fail if any technology has OpenSSF Scorecard score below this value (`0`-`10`) |
| `exclude-tech` | — | Fail if specified technologies are detected (comma-separated) |

### SSL / certificate gates

| Input | Default | Description |
|-------|---------|-------------|
| `fail-on-ssl` | `false` | Fail if SSL/TLS protocol issues are detected |
| `fail-on-cert` | `false` | Fail if certificate issues are detected |
| `fail-on-cert-expiry` | `0` | Fail if certificate expires within N days |

### HTTP / web configuration gates

| Input | Default | Description |
|-------|---------|-------------|
| `fail-on-headers` | `false` | Fail if HTTP security header issues are detected (CSP, HSTS, X-Frame-Options) |
| `fail-on-cookies` | `false` | Fail if insecure cookie issues are detected (HttpOnly, Secure, SameSite) |
| `require-waf` | `false` | Fail if no WAF is detected |
| `fail-on-sensitive-services` | `false` | Fail if sensitive services are exposed on the site IP |

### Comprehensive example

```yaml
- uses: purplemet/purplemet-action@v1
  with:
    api-token: ${{ secrets.PURPLEMET_API_TOKEN }}
    target-url: 'https://your-app.example.com'
    fail-severity: 'high'
    fail-on-kev: 'true'
    fail-cvss: '9.0'
    fail-on-eol: 'true'
    fail-on-cert-expiry: '30'
    fail-on-headers: 'true'
    sarif-upload: 'true'
```

> When using the binary or Docker methods, all of the above are also exposed as `PURPLEMET_*` environment variables (e.g. `PURPLEMET_FAIL_ON_KEV`, `PURPLEMET_FAIL_CVSS`).

## Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `exit-code` | Exit code of the analysis | `0` |
| `rating` | Security rating | `B` |
| `issues` | Total number of issues found | `12` |
| `result-json` | Full analysis result in JSON | `{"analysis": {...}}` |

## Exit Codes

| Code | Meaning | CI Behavior |
|------|---------|-------------|
| 0 | No issues above threshold | Pipeline passes |
| 1 | Issues found above severity threshold | Pipeline fails (use `continue-on-error: true` for warning) |
| 2 | Analysis error on Purplemet side | Pipeline fails |
| 3 | Timeout | Pipeline fails |
| 4 | Network or API error | Pipeline fails |
| 5 | Usage error (bad arguments) | Pipeline fails |
| 6 | API contract error | Pipeline fails |

## Job Summary

The action automatically generates a visual summary in the **Actions** tab showing:
- Security rating with color indicator
- Issue count and severity breakdown
- Pass/fail status against your threshold

## Setup

1. **Get an API token** at [cloud.purplemet.com](https://cloud.purplemet.com/#/tokens/create)
2. **Add the secret** to your repository: Settings → Secrets → Actions → `PURPLEMET_API_TOKEN`
3. **Add the workflow** to your `.github/workflows/` directory

## Documentation

See the full [GitHub Actions integration guide](https://dev.purplemet.com/purplemet/integrations/cli/-/blob/main/docs/integrations/github-actions.md) for advanced examples, SARIF and Code Scanning setup, security gates, and detailed troubleshooting.

## License

MIT
