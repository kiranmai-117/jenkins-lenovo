#!/usr/bin/env bash
# Prints one repo slug per line for a given Bitbucket project.
# If BITBUCKET_REPO is set (non-empty), prints just that slug and exits.
#
# Usage: enumerate-repos.sh <PROJECT_KEY>
# Output: one slug per line, e.g.:
#   lcp-core-device-state-service
#   lcp-auth-service
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../config.env"

PROJECT_KEY="${1:-${BITBUCKET_PROJECT:-}}"
if [[ -z "${PROJECT_KEY}" ]]; then
    echo "ERROR: PROJECT_KEY is required (pass as arg or set BITBUCKET_PROJECT)" >&2
    exit 1
fi

# If a specific repo was requested, just emit that slug.
if [[ -n "${BITBUCKET_REPO:-}" ]]; then
    echo "${BITBUCKET_REPO}"
    exit 0
fi

API_BASE="${BITBUCKET_URL}/rest/api/1.0"
PAGE_START=0
PAGE_LIMIT=100

while true; do
    RESPONSE=$(curl -sf \
        -H "Authorization: Bearer ${BITBUCKET_API_KEY}" \
        -H "Accept: application/json" \
        "${API_BASE}/projects/${PROJECT_KEY}/repos?start=${PAGE_START}&limit=${PAGE_LIMIT}")

    # Print slug for each repo
    echo "${RESPONSE}" | jq -r '.values[].slug'

    IS_LAST=$(echo "${RESPONSE}" | jq -r '.isLastPage')
    if [[ "${IS_LAST}" == "true" ]]; then
        break
    fi

    PAGE_START=$(echo "${RESPONSE}" | jq -r '.nextPageStart')
done
