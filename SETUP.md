# Agentic IDE — Complete Setup Guide

Everything from zero to a running app on AWS, and how to shut it down cleanly.

---

## Prerequisites (one-time, on your Mac)

### 1. Install tools

```bash
# Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Terraform
brew tap hashicorp/tap && brew install hashicorp/tap/terraform

# AWS CLI
brew install awscli

# Node.js 18+
brew install node

# rsync (already on macOS, but ensure it's up to date)
brew install rsync
```

### 2. Configure AWS CLI

```bash
aws configure
```

Enter when prompted:
- **AWS Access Key ID** — from IAM → Users → main-admin → Security credentials
- **AWS Secret Access Key** — same place
- **Default region** — `ap-southeast-2`
- **Default output format** — `json`

Verify it works:
```bash
aws sts get-caller-identity
```

### 3. Move your PEM key to the right place

```bash
mv "/Users/tharungopinath/Desktop/Summer ML Intern (VIT - 2026)/CAD-DA2/CAD-DA2 SSH ACCESS KEY.pem" \
   ~/.ssh/CAD-DA2-SSH-ACCESS-KEY.pem
chmod 400 ~/.ssh/CAD-DA2-SSH-ACCESS-KEY.pem
```

---

## Part 1 — Provision AWS infrastructure (Terraform)

> Only needed the very first time, or after a `terraform destroy`.

### 1. Set your passwords

```bash
export TF_VAR_ide_pass="your-strong-ide-password"
export TF_VAR_db_password="your-strong-db-password"
```

> Write these down — you'll need them again when creating `.env` on EC2.

### 2. Run Terraform

```bash
cd "/Users/tharungopinath/Desktop/Summer ML Intern (VIT - 2026)/CAD-DA2/agentic-ide/infra/terraform"
terraform init       # only needed once
terraform apply      # type 'yes' when prompted
```

This creates (in order):
- VPC, subnets, internet gateway, route tables
- Security groups (ALB, EC2, Aurora)
- S3 bucket (`tharun-gopinath-1086-CAD-DA2`)
- Secrets Manager secret
- WAFv2 WebACL
- Application Load Balancer
- RDS PostgreSQL (`db.t4g.micro`)
- EC2 `g4dn.xlarge`

Takes **~10 minutes** total (RDS takes the longest).

### 3. Note the outputs

```bash
terraform output
```

Copy these values — you'll need them:
- `app_url` — the ALB public URL
- `ec2_public_ip` — for SSH
- `aurora_endpoint` — RDS hostname for `.env`

---

## Part 2 — Set up the EC2 instance (first time only)

### 1. SSH into the instance

```bash
ssh -i ~/.ssh/CAD-DA2-SSH-ACCESS-KEY.pem ubuntu@<ec2_public_ip>
```

### 2. Fix Docker (DLAMI has it pre-installed)

```bash
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
newgrp docker
```

### 3. Install Node.js 20

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs
```

### 4. Install Python 3.11 venv

```bash
sudo apt-get install -y python3.11-venv
```

### 5. Create Python virtualenv and install deps

```bash
cd /home/ubuntu/agentic-ide
python3.11 -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements.txt
pip install vllm
```

> `pip install vllm` takes 3–5 minutes.

### 6. Build the React frontend

```bash
cd /home/ubuntu/agentic-ide/frontend
npm install
npm run build
cd ..
```

### 7. Build the sandbox Docker image

```bash
cd /home/ubuntu/agentic-ide
docker build -t ide-sandbox sandbox/
```

### 8. Create the .env file

```bash
cat > /home/ubuntu/agentic-ide/.env << 'EOF'
IDE_USER=admin
IDE_PASS=your-strong-ide-password
LLM_BASE_URL=http://127.0.0.1:8000/v1
LLM_API_KEY=none
LLM_MODEL=Qwen/Qwen2.5-Coder-7B-Instruct-AWQ
LLM_MAX_TOKENS=1500
LLM_TIMEOUT=120
SANDBOX_IMAGE=ide-sandbox
RUN_TIMEOUT=5
COMPILE_TIMEOUT=30
AGENT_MAX_ITERS=5
AWS_REGION=ap-southeast-2
S3_BUCKET=tharun-gopinath-1086-CAD-DA2
DB_HOST=<aurora_endpoint from terraform output>
DB_PORT=5432
DB_NAME=agenticide
DB_USER=ideadmin
DB_PASS=your-strong-db-password
ACTIVITY_FILE=/tmp/ide_last_activity
IDLE_MINUTES=30
EOF
chmod 600 /home/ubuntu/agentic-ide/.env
```

Replace the placeholder values with your actual passwords and RDS endpoint.

### 9. Create the systemd service

```bash
sudo tee /etc/systemd/system/agentic-ide.service > /dev/null << 'UNIT'
[Unit]
Description=Agentic IDE FastAPI server
After=network.target docker.service

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/agentic-ide
EnvironmentFile=/home/ubuntu/agentic-ide/.env
ExecStart=/home/ubuntu/agentic-ide/.venv/bin/uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable agentic-ide
sudo systemctl start agentic-ide
```

### 10. Verify the IDE server is running

```bash
sudo systemctl status agentic-ide
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/files
# Should print 401 (auth required = server is up)
```

### 11. Start vLLM (in tmux so it survives disconnect)

```bash
tmux new -s llm
. /home/ubuntu/agentic-ide/.venv/bin/activate
cd /home/ubuntu/agentic-ide
scripts/start_vllm.sh
```

Press `Ctrl+B` then `D` to detach. vLLM keeps running in the background.

First start downloads ~4 GB model weights — takes 5–10 minutes.
Check when it's ready:
```bash
curl http://127.0.0.1:8000/v1/models
```

### 12. Open the app

On your Mac, get the URL:
```bash
terraform -chdir="/Users/tharungopinath/Desktop/Summer ML Intern (VIT - 2026)/CAD-DA2/agentic-ide/infra/terraform" output app_url
```

Open it in your browser. Login with:
- **Username:** `admin`
- **Password:** the `IDE_PASS` you set in `.env`

---

## Part 3 — Daily workflow (starting the app after a stop)

Every time you start the EC2 instance after it's been stopped:

### On your Mac — start the EC2 instance

```bash
# Get the instance ID
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=agentic-ide-ide" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region ap-southeast-2

# Start it
aws ec2 start-instances --instance-ids <instance-id> --region ap-southeast-2

# Wait for it to be running (~1 min)
aws ec2 wait instance-running --instance-ids <instance-id> --region ap-southeast-2

# Get the new public IP (it changes on every start)
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text --region ap-southeast-2
```

### SSH into the instance

```bash
ssh -i ~/.ssh/CAD-DA2-SSH-ACCESS-KEY.pem ubuntu@<new-public-ip>
```

### Check the IDE service (auto-starts on boot)

```bash
sudo systemctl status agentic-ide
# If not running:
sudo systemctl start agentic-ide
```

### Start vLLM

```bash
tmux new -s llm
. /home/ubuntu/agentic-ide/.venv/bin/activate
cd /home/ubuntu/agentic-ide
scripts/start_vllm.sh
# Ctrl+B then D to detach
```

Model is already downloaded — starts in ~1 minute.

### Open the app

The ALB DNS name stays the same even when EC2 restarts:
```bash
terraform -chdir="/Users/tharungopinath/Desktop/Summer ML Intern (VIT - 2026)/CAD-DA2/agentic-ide/infra/terraform" output app_url
```

---

## Part 4 — Deploying code changes

When you update the code on your Mac and want to push it to EC2:

```bash
cd "/Users/tharungopinath/Desktop/Summer ML Intern (VIT - 2026)/CAD-DA2/agentic-ide"

scripts/deploy.sh \
  --ip  <current-ec2-public-ip> \
  --key ~/.ssh/CAD-DA2-SSH-ACCESS-KEY.pem
```

The script:
1. Builds the React frontend locally
2. rsyncs all code to EC2
3. Installs any new Python deps
4. Restarts the `agentic-ide` service
5. Polls until the server responds

---

## Part 5 — Stopping the instance (to avoid billing)

### Option A — Manual stop from your Mac

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=agentic-ide-ide" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region ap-southeast-2)

aws ec2 stop-instances --instance-ids $INSTANCE_ID --region ap-southeast-2
```

A stopped instance costs only EBS storage (~$1/month for 100 GB gp3).
RDS also stops billing for compute when the instance is stopped separately:

```bash
aws rds stop-db-instance \
  --db-instance-identifier agentic-ide-postgres \
  --region ap-southeast-2
```

### Option B — Auto-stop (already configured)

The idle shutdown cron runs every 5 minutes on EC2. If no HTTP request hits the app for 30 minutes, it runs `shutdown -h now` automatically.

### Option C — Destroy everything (end of project)

Removes all AWS resources and stops all billing:

```bash
cd "/Users/tharungopinath/Desktop/Summer ML Intern (VIT - 2026)/CAD-DA2/agentic-ide/infra/terraform"
terraform destroy
# type 'yes' when prompted
```

> Warning: this deletes the S3 bucket and all workspace files. Back up anything important first.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Permission denied (publickey)` | Check PEM file path and `chmod 400` |
| `curl` returns 000 on port 8080 | `sudo systemctl status agentic-ide` — check logs |
| vLLM not responding | `tmux attach -t llm` — check if model finished loading |
| S3 permission denied | EC2 IAM role is missing — check `terraform apply` completed |
| ALB returns 502 | IDE server not running — `sudo systemctl start agentic-ide` |
| `docker: command not found` | `sudo systemctl start docker` |
| DB connection refused | RDS may be stopped — `aws rds start-db-instance --db-instance-identifier agentic-ide-postgres --region ap-southeast-2` |
| New public IP after restart | Always re-fetch IP with `aws ec2 describe-instances` — ALB URL stays the same |
