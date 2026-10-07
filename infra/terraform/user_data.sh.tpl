#!/usr/bin/env bash
# EC2 bootstrap script (runs once as root on first boot via cloud-init).
# Templated values are injected by Terraform.
set -euo pipefail
exec > /var/log/ide-bootstrap.log 2>&1

echo "=== Agentic IDE Bootstrap $(date) ==="

# ── System deps ───────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  git curl unzip awscli \
  python3.11 python3.11-venv python3-pip

# Node.js 20 (for React build)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# The Deep Learning AMI ships with Docker already installed.
# Just ensure the service is running and ubuntu is in the docker group.
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# ── Fetch secrets from Secrets Manager ───────────────────────────────────
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" \
  --region    "${aws_region}" \
  --query     SecretString \
  --output    text)

IDE_USER=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['ide_user'])")
IDE_PASS=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['ide_pass'])")
DB_PASS=$(echo  "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['db_password'])")

# ── Clone repo ────────────────────────────────────────────────────────────
REPO_DIR="/home/ubuntu/agentic-ide"
if [ ! -d "$REPO_DIR" ]; then
  # Clone from the public repo URL — update this if your repo is private.
  git clone https://github.com/tg1106/Agentic-IDE-AWS.git "$REPO_DIR" || \
  # Fallback: copy from local zip if git clone fails (useful during development).
  echo "WARNING: git clone failed — deploy manually with scripts/deploy.sh"
fi
if [ ! -f "$REPO_DIR/backend/requirements.txt" ]; then
  echo "ERROR: repo not found at $REPO_DIR (clone failed - private repo?). Run scripts/deploy.sh from your laptop, then redo the remaining bootstrap steps by hand."
  exit 1
fi
chown -R ubuntu:ubuntu "$REPO_DIR"

# ── Python virtualenv ─────────────────────────────────────────────────────
cd "$REPO_DIR"
sudo -u ubuntu python3.11 -m venv .venv
sudo -u ubuntu .venv/bin/pip install --upgrade pip
sudo -u ubuntu .venv/bin/pip install -r backend/requirements.txt
# vLLM gets its own venv so its pinned dependencies cannot break the API server's.
sudo -u ubuntu python3.11 -m venv .venv-vllm
sudo -u ubuntu .venv-vllm/bin/pip install --upgrade pip
sudo -u ubuntu .venv-vllm/bin/pip install vllm

# ── React frontend build ──────────────────────────────────────────────────
cd "$REPO_DIR/frontend"
sudo -u ubuntu npm ci
sudo -u ubuntu npm run build
cd "$REPO_DIR"

# ── Sandbox Docker image ──────────────────────────────────────────────────
docker build -t ide-sandbox sandbox/

# ── .env file ─────────────────────────────────────────────────────────────
cat > "$REPO_DIR/.env" <<ENV
IDE_USER=$IDE_USER
IDE_PASS=$IDE_PASS
LLM_BASE_URL=http://127.0.0.1:8000/v1
LLM_API_KEY=none
LLM_MODEL=${llm_model}
LLM_MAX_TOKENS=1500
LLM_TIMEOUT=120
SANDBOX_IMAGE=ide-sandbox
RUN_TIMEOUT=5
COMPILE_TIMEOUT=30
AGENT_MAX_ITERS=5
WORKSPACE_DIR=/home/ubuntu/agentic-ide/workspace
ACTIVITY_FILE=/tmp/ide_last_activity
IDLE_MINUTES=${idle_minutes}

# AWS
AWS_REGION=${aws_region}
S3_BUCKET=${s3_bucket}
SECRET_ARN=${secret_arn}

# Aurora
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USER=ideadmin
DB_PASS=$DB_PASS
ENV
chown ubuntu:ubuntu "$REPO_DIR/.env"
chmod 600 "$REPO_DIR/.env"

# ── systemd: vLLM service ─────────────────────────────────────────────────
cat > /etc/systemd/system/vllm.service <<'UNIT'
[Unit]
Description=vLLM OpenAI-compatible model server
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/agentic-ide
EnvironmentFile=/home/ubuntu/agentic-ide/.env
ExecStart=/home/ubuntu/agentic-ide/.venv-vllm/bin/python -m vllm.entrypoints.openai.api_server \
  --model ${llm_model} \
  --quantization awq \
  --dtype half \
  --max-model-len 8192 \
  --served-model-name ${llm_model} \
  --host 127.0.0.1 \
  --port 8000
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

# ── systemd: IDE server ───────────────────────────────────────────────────
cat > /etc/systemd/system/agentic-ide.service <<'UNIT'
[Unit]
Description=Agentic IDE FastAPI server
After=network.target docker.service

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/agentic-ide
EnvironmentFile=/home/ubuntu/agentic-ide/.env
ExecStart=/home/ubuntu/agentic-ide/.venv/bin/uvicorn app.main:app \
  --app-dir backend \
  --host 0.0.0.0 \
  --port 8080
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

# ── Idle shutdown cron ────────────────────────────────────────────────────
echo "*/5 * * * * root ACTIVITY_FILE=/tmp/ide_last_activity IDLE_MINUTES=${idle_minutes} /home/ubuntu/agentic-ide/scripts/idle_shutdown.sh" \
  > /etc/cron.d/ide-idle-shutdown

# ── Enable and start services ─────────────────────────────────────────────
systemctl daemon-reload
systemctl enable vllm agentic-ide
systemctl start  vllm
# IDE starts immediately; it will retry DB connection until Aurora is ready
systemctl start  agentic-ide

echo "=== Bootstrap complete $(date) ==="
