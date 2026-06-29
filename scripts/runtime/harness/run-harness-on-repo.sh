#!/usr/bin/env bash
# Runs the coding agent against a single repository.
#
# Usage: run-harness-on-repo.sh <PROJECT_KEY> <REPO_SLUG>
#
# Required env vars (typically set by Jenkinsfile):
#   GOAL               — what the agent should do
#   BITBUCKET_API_KEY  — PAT for git clone + Bitbucket REST API
#   DRY_RUN            — if "true", skip push and PR creation
#
# Optional env vars (forwarded to agent for skill use):
#   JIRA_API_TOKEN
#   SONAR_AUTH_TOKEN
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../config.env"

PROJECT_KEY="${1:-${BITBUCKET_PROJECT:-}}"
REPO_SLUG="${2:-}"
if [[ -z "${PROJECT_KEY}" || -z "${REPO_SLUG}" ]]; then
    echo "ERROR: PROJECT_KEY and REPO_SLUG are required" >&2
    exit 1
fi

GOAL="${GOAL:-}"
if [[ -z "${GOAL}" ]]; then
    echo "ERROR: GOAL env var is required" >&2
    exit 1
fi

DRY_RUN="${DRY_RUN:-false}"
HARNESS="${AGENT_HARNESS:-claude}"
CLAUDE_BIN="/npm-global/bin/claude"
OPENCODE_BIN="/npm-global/bin/opencode"
PI_BIN="/npm-global/bin/pi"
MODEL="${MODEL_NAME:?MODEL_NAME must be set in repo-root config.env}"
MODEL_BASE_URL="${MODEL_SERVER_BASE_URL:-http://localhost:8000/v1}"
MODEL_SERVER_PROVIDER="${MODEL_SERVER_PROVIDER:-vllm}"

PATH=$PATH:/npm-global/bin

# ── Derive branch name ────────────────────────────────────────────────────────
GOAL_SLUG=$(echo "${GOAL}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | cut -c1-40 | sed 's/-$//')
BRANCH_NAME="${AGENT_BRANCH_PREFIX}/$(date +%Y%m%d)-${GOAL_SLUG}"

# ── Clone repo ────────────────────────────────────────────────────────────────
CLONE_URL=$(echo "${BITBUCKET_URL}/scm/${PROJECT_KEY}/${REPO_SLUG}.git" | \
    sed "s|https://|https://${BITBUCKET_USER}:${BITBUCKET_API_KEY}@|")

REPO_DIR="/workspace/repos/${PROJECT_KEY}/${REPO_SLUG}"
mkdir -p "${REPO_DIR}"

if [[ -d "${REPO_DIR}/.git" ]]; then
    echo "=== Repository ${PROJECT_KEY}/${REPO_SLUG} exists. Fetching latest changes... ==="
    cd "${REPO_DIR}"
    git fetch origin
    git checkout "$(git remote show origin | awk '/HEAD branch/ {print $NF}')"
    git pull origin "$(git remote show origin | awk '/HEAD branch/ {print $NF}')"
else
    echo "=== Cloning ${PROJECT_KEY}/${REPO_SLUG} ==="
    git clone --depth 1 "${CLONE_URL}" "${REPO_DIR}"
    cd "${REPO_DIR}"
fi

cd "${REPO_DIR}"

# ── Get default branch for PR target ─────────────────────────────────────────
DEFAULT_BRANCH="develop"

# ── Create agent branch ───────────────────────────────────────────────────────
git checkout -b "${BRANCH_NAME}" || git checkout "${BRANCH_NAME}"
git clean -fdx

# ── Configure git identity ────────────────────────────────────────────────────
git config user.name  "${GIT_AUTHOR_NAME}"
git config user.email "${GIT_AUTHOR_EMAIL}"


# ── Setup skills directory ───────────────────────────────────────────────────
CURSOR_SKILLS_DIR="${CURSOR_COMMONS_DIR}/cursor-settings/skills"
LOCAL_SKILLS_DIR="${SCRIPT_DIR}/skills"
CLAUDE_SKILLS_HOME="${HOME}/.claude/skills"
OPENCODE_SKILLS_HOME="${HOME}/.agents/skills"
REPO_CLAUDE_SKILLS_DIR=".claude/skills"
REPO_OPENCODE_SKILLS_DIR=".agents/skills"
mkdir -p \
    "${CLAUDE_SKILLS_HOME}" \
    "${OPENCODE_SKILLS_HOME}" \
    "${REPO_CLAUDE_SKILLS_DIR}" \
    "${REPO_OPENCODE_SKILLS_DIR}"

link_skills_from() {
    local source_dir="$1"
    [[ -d "${source_dir}" ]] || return 0

    local skill_dir
    for skill_dir in "${source_dir}"/*; do
        [[ -d "${skill_dir}" ]] || continue
        ln -sfn "${skill_dir}" "${CLAUDE_SKILLS_HOME}/$(basename "${skill_dir}")"
        ln -sfn "${skill_dir}" "${OPENCODE_SKILLS_HOME}/$(basename "${skill_dir}")"
        ln -sfn "${skill_dir}" "${REPO_CLAUDE_SKILLS_DIR}/$(basename "${skill_dir}")"
        ln -sfn "${skill_dir}" "${REPO_OPENCODE_SKILLS_DIR}/$(basename "${skill_dir}")"
    done
}

link_skills_from "${CURSOR_SKILLS_DIR}"
link_skills_from "${LOCAL_SKILLS_DIR}"

echo ".agents" >> .git/info/exclude
echo ".claude" >> .git/info/exclude

# ── Run coding harness agent ──────────────────────────────────────────────────
LOGS_DIR="/workspace/logs/${PROJECT_KEY}/${REPO_SLUG}"
mkdir -p "${LOGS_DIR}"

echo "=== Running coding harness agent ==="
echo "Branch     : ${BRANCH_NAME}"
echo "Goal       : ${GOAL}"
echo "Harness    : ${HARNESS}"
echo "Skills dirs: ${CURSOR_SKILLS_DIR}, ${LOCAL_SKILLS_DIR}"
echo "Logs dir   : ${LOGS_DIR}"
echo "--------------------------------------------"

export BITBUCKET_TOKEN="${BITBUCKET_API_KEY}"
export JIRA_API_TOKEN="${JIRA_API_TOKEN:-}"
export SONARQUBE_TOKEN="${SONAR_AUTH_TOKEN:-}"
export ADDITIONAL_PROMPTS=$(cat <<EOF
Once the task is complete, run lint, unit tests and commit the changes.
For your commit message, keep it concise and use the existing convention, and mention the JIRA ticket number if available.
EOF
)

HARNESS_EXIT_CODE=0
case "${HARNESS}" in
    claude)

            export ANTHROPIC_BASE_URL="${MODEL_BASE_URL}"
            export ANTHROPIC_AUTH_TOKEN="dummy"
            export ANTHROPIC_API_KEY=""

            "${CLAUDE_BIN}" --model "${MODEL}" \
            --dangerously-skip-permissions \
            --output-format text \
            -p "Your Goal: ${GOAL}. ${ADDITIONAL_PROMPTS}" \
            2>&1 | tee "${LOGS_DIR}/coding-agent.log" \
            || HARNESS_EXIT_CODE=$?
        ;;
    opencode)
        OPENCODE_CONFIG_FILE="${LOGS_DIR}/coding-agent.json"
        cat > "${OPENCODE_CONFIG_FILE}" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "${MODEL_SERVER_PROVIDER}": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Model Server (local)",
      "options": {
        "baseURL": "${MODEL_BASE_URL}"
      },
      "models": {
        "${MODEL}": {
          "name": "${MODEL}"
        }
      }
    }
  }
}
EOF
        export OPENCODE_CONFIG="${OPENCODE_CONFIG_FILE}"
        "${OPENCODE_BIN}" run \
            --model "${MODEL_SERVER_PROVIDER}/${MODEL}" \
            --dangerously-skip-permissions \
            "Your Goal: ${GOAL}. ${ADDITIONAL_PROMPTS}" \
            2>&1 | tee "${LOGS_DIR}/opencode-output.log" \
            || HARNESS_EXIT_CODE=$?
        ;;
    pi.dev)
        PI_MODELS_DIR="${HOME}/.pi/agent"
        PI_MODELS_FILE="${PI_MODELS_DIR}/models.json"
        mkdir -p "${PI_MODELS_DIR}"
        cat > "${PI_MODELS_FILE}" <<EOF
{
  "providers": {
    "model-server": {
      "baseUrl": "${MODEL_BASE_URL}",
      "api": "openai-completions",
      "apiKey": "not-needed",
      "models": [
        {
          "id": "${MODEL}",
          "name": "${MODEL}"
        }
      ]
    }
  }
}
EOF
        export OPENAI_API_KEY="${OPENAI_API_KEY:-dummy}"
        "${PI_BIN}" \
            -p "Your Goal: ${GOAL}. ${ADDITIONAL_PROMPTS}" \
            --model "${MODEL}" \
            2>&1 | tee "${LOGS_DIR}/pi-dev-output.log" \
            || HARNESS_EXIT_CODE=$?
        ;;
    *)
        echo "ERROR: Unsupported AGENT_HARNESS '${HARNESS}'. Use 'claude', 'opencode', or 'pi.dev'." >&2
        exit 1
        ;;
esac

echo "=== ${HARNESS} exited with code ${HARNESS_EXIT_CODE} ==="

# ── Capture post-run logs (non-fatal) ────────────────────────────────────────
set +e

git diff HEAD > "${LOGS_DIR}/agent.diff" 2>/dev/null

set -e

echo "=== Logs written to ${LOGS_DIR} ==="
ls -lh "${LOGS_DIR}/"

# ── Check for new commits ─────────────────────────────────────────────────────
# The agent is expected to have already committed any changes.
# Let's check if new commits have been made compared to the previous HEAD (before agent run).

# Store the commit that was at HEAD before the agent ran (should be set before agent logic)
# If this script is re-entrant and doesn't have $PRE_AGENT_HEAD, use the remote tracking branch.
PRE_AGENT_HEAD="${PRE_AGENT_HEAD:-origin/${DEFAULT_BRANCH}}"

if [[ "$(git rev-parse HEAD)" == "$(git rev-parse "${PRE_AGENT_HEAD}")" ]]; then
    echo "=== No new commits made by agent for ${REPO_SLUG} — skipping PR ==="
    exit 0
fi

echo "=== Agent made changes (commits between ${PRE_AGENT_HEAD} and HEAD): ==="
git log --oneline "${PRE_AGENT_HEAD}..HEAD"
git diff --stat "${PRE_AGENT_HEAD}..HEAD"

# ── Push and raise PR ─────────────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "true" ]]; then
    echo "=== DRY_RUN=true — skipping push and PR creation ==="
    exit 0
fi

git push origin "${BRANCH_NAME}"

PR_DESCRIPTION="**Automated change by Coding Agent**

**Goal:** ${GOAL}
**Model:** ${HARNESS}
**Project:** ${PROJECT_KEY}
**Repo:** ${REPO_SLUG}
"

PR_RESULT=$(curl -sf -u "${BITBUCKET_USER}:${BITBUCKET_API_KEY}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${BITBUCKET_URL}/rest/api/1.0/projects/${PROJECT_KEY}/repos/${REPO_SLUG}/pull-requests" \
    -d "$(jq -n \
        --arg title "Agent: ${GOAL}" \
        --arg desc  "${PR_DESCRIPTION}" \
        --arg from  "${BRANCH_NAME}" \
        --arg to    "${DEFAULT_BRANCH}" \
        --arg proj  "${PROJECT_KEY}" \
        --arg repo  "${REPO_SLUG}" \
        '{
            title: $title,
            description: $desc,
            fromRef: { id: ("refs/heads/" + $from), repository: { slug: $repo, project: { key: $proj } } },
            toRef:   { id: ("refs/heads/" + $to),   repository: { slug: $repo, project: { key: $proj } } },
            reviewers: []
        }')")

PR_URL=$(echo "${PR_RESULT}" | jq -r '.links.self[0].href // "unknown"')
echo "=== PR raised: ${PR_URL} ==="

# Write PR URL to a summary file for the pipeline to collect
echo "${PROJECT_KEY}/${REPO_SLUG}: ${PR_URL}" >> /workspace/pr-summary.txt
