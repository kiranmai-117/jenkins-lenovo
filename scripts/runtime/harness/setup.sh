#!/usr/bin/env bash
# Runs inside the coding-agent container.
# 1. Installs system tools (git, curl, jq) and creates a uv-managed Python venv.
# 2. Installs selected coding harness CLI if not cached.
# 3. Clones cursor-commons to get skill files.
set -euo pipefail

PYTHON_VENV="/opt/venv"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../config.env"

echo "=== Installing system dependencies ==="
apt-get update -qq
apt-get install -y --no-install-recommends git curl jq ca-certificates unzip

echo "=== Installing jira-cli ==="
JIRA_CLI_VERSION=$(curl -sf https://api.github.com/repos/ankitpokhrel/jira-cli/releases/latest \
    | jq -r '.tag_name' | tr -d 'v')
curl -fsSL "https://github.com/ankitpokhrel/jira-cli/releases/download/v${JIRA_CLI_VERSION}/jira_${JIRA_CLI_VERSION}_linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=2 "jira_${JIRA_CLI_VERSION}_linux_x86_64/bin/jira"
echo "jira-cli $(jira version) installed"

echo "=== Configuring jira-cli ==="
mkdir -p "${HOME}/.config/.jira"
cat > "${HOME}/.config/.jira/.config.yml" <<EOF
auth_type: bearer
installation: Local
server: ${JIRA_URL}
login: ${BOT_SERVICE_ACCOUNT}
project: ""
EOF


echo "=== Installing uv ==="
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

echo "=== Creating Python venv ==="
uv venv --python 3.14 "${PYTHON_VENV}"

echo "=== Installing Python packages ==="
uv pip install --python "${PYTHON_VENV}" requests

echo "=== Installing mise ==="
curl -fsSL https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

echo "=== Installing Node.js via mise ==="
mise use --global node@22
eval "$(mise activate bash)"

# Symlink into /usr/local/bin so node is in PATH for all subsequent pipeline shells
NODE_DIR="$(mise where node)"
ln -sf "${NODE_DIR}/bin/node" /usr/local/bin/node
ln -sf "${NODE_DIR}/bin/npm"  /usr/local/bin/npm
ln -sf "${NODE_DIR}/bin/npx"  /usr/local/bin/npx
echo "Node $(node --version) available at $(which node)"

HARNESS="${AGENT_HARNESS:-claude}"
echo "=== Installing coding harness CLI (${HARNESS}) ==="
case "${HARNESS}" in
    claude)
        CLAUDE_BIN="/npm-global/bin/claude"
        if [[ ! -x "${CLAUDE_BIN}" ]]; then
            echo "Installing @anthropic-ai/claude-code (first run on this node)..."
            npm install --global @anthropic-ai/claude-code
        else
            echo "Claude Code CLI already cached — skipping install."
        fi
        ;;
    opencode)
        OPENCODE_BIN="/npm-global/bin/opencode"
        if [[ ! -x "${OPENCODE_BIN}" ]]; then
            echo "Installing opencode-ai (first run on this node)..."
            npm install --global opencode-ai
        else
            echo "OpenCode CLI already cached — skipping install."
        fi
        ;;
    pi.dev)
        PI_BIN="/npm-global/bin/pi"
        if [[ ! -x "${PI_BIN}" ]]; then
            echo "Installing @earendil-works/pi-coding-agent (first run on this node)..."
            npm install --global --ignore-scripts @earendil-works/pi-coding-agent
        else
            echo "Pi CLI already cached — skipping install."
        fi
        ;;
    *)
        echo "ERROR: Unsupported AGENT_HARNESS '${HARNESS}'. Use 'claude', 'opencode', or 'pi.dev'." >&2
        exit 1
        ;;
esac

echo "=== Cloning cursor-commons ==="
mkdir -p "$(dirname "${CURSOR_COMMONS_DIR}")"

CLONE_URL="${CURSOR_COMMONS_REPO}"
# Inject API key into clone URL if BITBUCKET_API_KEY is set
if [[ -n "${BITBUCKET_API_KEY:-}" ]]; then
    CLONE_URL=$(echo "${CURSOR_COMMONS_REPO}" | sed "s|https://|https://${BITBUCKET_USER}:${BITBUCKET_API_KEY}@|")
fi

if [[ -d "${CURSOR_COMMONS_DIR}/.git" ]]; then
    echo "cursor-commons already cloned — pulling latest."
    git -C "${CURSOR_COMMONS_DIR}" pull --ff-only
else
    git clone --depth 1 "${CLONE_URL}" "${CURSOR_COMMONS_DIR}"
fi

echo "=== Setup complete ==="
echo "cursor-commons skills available:"
ls "${CURSOR_COMMONS_DIR}/cursor-settings/skills/"
echo "local coding-agent skills available:"
ls "${SCRIPT_DIR}/skills/" 2>/dev/null || true
