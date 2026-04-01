#!/bin/sh
set -e

# GitHub Action Docker entrypoint — delegates to shared analysis script.
# All PURPLEMET_* env vars are passed through by the action.

exec /usr/local/share/purplemet/analyze.sh
