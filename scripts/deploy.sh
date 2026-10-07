#!/usr/bin/env bash
# Push the latest code to the EC2 instance and restart the IDE server.
#
# Prerequisites:
#   - Terraform has been applied (terraform -chdir=infra/terraform apply)
#   - AWS CLI is configured (aws configure)
#   - The .pem file is available at the path given by --key
#
# Usage:
#   scripts/deploy.sh --ip <EC2_PUBLIC_IP> --key <PATH_TO_PEM>
#
# Example:
#   scripts/deploy.sh --ip 13.55.123.45 --key ~/.ssh/CAD-DA2-SSH-ACCESS-KEY.pem
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Argument parsing ──────────────────────────────────────────────────────
EC2_IP=""
PEM_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)  EC2_IP="$2";  shift 2 ;;
    --key) PEM_KEY="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$EC2_IP" || -z "$PEM_KEY" ]]; then
  echo "Usage: scripts/deploy.sh --ip <EC2_PUBLIC_IP> --key <PATH_TO_PEM>" >&2
  exit 1
fi

SSH_OPTS="-i $PEM_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15"
REMOTE="ubuntu@$EC2_IP"
REMOTE_DIR="/home/ubuntu/agentic-ide"

echo "=== Building React frontend ==="
(cd "$REPO_ROOT/frontend" && npm ci && npm run build)

echo "=== Syncing code to EC2 ($EC2_IP) ==="
# rsync everything except .git, node_modules, __pycache__, .venv, and dist
rsync -az --delete \
  --exclude='.git' \
  --exclude='frontend/node_modules' \
  --exclude='frontend/dist' \
  --exclude='backend/app/__pycache__' \
  --exclude='.venv' \
  --exclude='.venv-vllm' \
  --exclude='infra/terraform/.terraform' \
  --exclude='infra/terraform/*.tfstate*' \
  --exclude='infra/terraform/*.tfvars' \
  --exclude='workspace' \
  --exclude='.env' \
  -e "ssh $SSH_OPTS" \
  "$REPO_ROOT/" \
  "$REMOTE:$REMOTE_DIR/"

echo "=== Copying built frontend dist/ ==="
rsync -az --delete \
  -e "ssh $SSH_OPTS" \
  "$REPO_ROOT/frontend/dist/" \
  "$REMOTE:$REMOTE_DIR/frontend/dist/"

echo "=== Installing Python deps on EC2 ==="
ssh $SSH_OPTS "$REMOTE" bash <<'REMOTE_SCRIPT'
  set -euo pipefail
  cd /home/ubuntu/agentic-ide
  . .venv/bin/activate
  pip install -q -r backend/requirements.txt
REMOTE_SCRIPT

echo "=== Restarting agentic-ide service ==="
ssh $SSH_OPTS "$REMOTE" "sudo systemctl restart agentic-ide"

echo "=== Waiting for health check ==="
for i in $(seq 1 12); do
  STATUS=$(ssh $SSH_OPTS "$REMOTE" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/api/files" || echo "000")
  if [[ "$STATUS" == "200" || "$STATUS" == "401" ]]; then
    echo "Service is up (HTTP $STATUS)."
    break
  fi
  echo "  Attempt $i/12: HTTP $STATUS — waiting 5 s..."
  sleep 5
done

echo ""
echo "=== Deploy complete ==="
echo "App URL: run  terraform -chdir=infra/terraform output app_url"
echo "(Port 8080 is only reachable from the ALB, not directly.)"
