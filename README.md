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

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-token` | **Yes** | — | Purplemet API token ([create one](https://cloud.purplemet.com/#/tokens/create)) |
| `target-url` | **Yes** | — | URL of the web application to analyze |
| `fail-severity` | No | `high` | Fail if issues at or above this severity: `critical`, `high`, `medium`, `low`, `info` |
| `timeout` | No | `300000` | Wait timeout in milliseconds (0 = unlimited) |
| `version` | No | `latest` | CLI version to use (e.g. `v1.2.0`) |
| `base-url` | No | — | API base URL override |
| `sarif-upload` | No | `false` | Upload SARIF results to GitHub Code Scanning |

All [security gate environment variables](https://dev.purplemet.com/purplemet/integrations/cli/-/blob/main/docs/configuration.md) (`PURPLEMET_FAIL_ON_EOL`, `PURPLEMET_FAIL_ON_KEV`, `PURPLEMET_FAIL_CVSS`, etc.) are also supported when using the binary or Docker methods. See the [full parameter reference](https://dev.purplemet.com/purplemet/integrations/cli/-/blob/main/docs/integrations/github-actions.md#parameters).

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

## License

MIT
