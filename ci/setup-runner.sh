#!/usr/bin/env bash
# Registers this VM as a self-hosted GitHub Actions runner and installs it
# as a systemd service, so it starts again after a reboot.
#
# Run on the VM as the ubuntu user (not root):
#   bash setup-runner.sh <repo-url> <registration-token> <label>
#
# Example:
#   bash setup-runner.sh https://github.com/Amin-0513/devops-capstone-client AABBCC... client-vm
#
# Get the token from GitHub: repo > Settings > Actions > Runners >
# New self-hosted runner (Linux). It is valid for one hour.
set -euo pipefail

REPO_URL="${1:?repo URL required}"
TOKEN="${2:?registration token required}"
LABEL="${3:?runner label required (client-vm or server-vm)}"
RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner}"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as the ubuntu user, not root." >&2; exit 1
fi

# The runner runs docker commands, so its user must be in the docker group
if ! id -nG | grep -qw docker; then
  sudo usermod -aG docker "$USER"
  echo "Added $USER to the docker group."
fi

sudo apt-get update -y
sudo apt-get install -y curl jq tar

case "$(uname -m)" in
  x86_64)  ARCH=x64 ;;
  aarch64) ARCH=arm64 ;;
  *) echo "Unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

VERSION=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')
echo "Installing actions-runner v${VERSION} (${ARCH}) in ${RUNNER_DIR}"

mkdir -p "$RUNNER_DIR" && cd "$RUNNER_DIR"
curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${VERSION}/actions-runner-linux-${ARCH}-${VERSION}.tar.gz"
tar xzf runner.tar.gz && rm runner.tar.gz
sudo ./bin/installdependencies.sh

./config.sh --unattended \
  --url "$REPO_URL" \
  --token "$TOKEN" \
  --name "$(hostname)-${LABEL}" \
  --labels "$LABEL" \
  --work _work \
  --replace

sudo ./svc.sh install "$USER"
sudo ./svc.sh start
sudo ./svc.sh status --no-pager || true
echo "Runner registered with label '${LABEL}'."
