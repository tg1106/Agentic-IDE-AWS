# Agentic IDE (C++ / Python)

Browser IDE with a **write → run → fix** agent for LeetCode-style problems.  
Deployed on AWS with **ALB → WAF → EC2 (g4dn.xlarge)**, workspace files in **S3**, run logs in **Aurora PostgreSQL**.

---

## AWS deployment (Terraform)

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured (`aws configure`)
- GPU quota approved for `g4dn.xlarge` in `ap-southeast-2`
- EC2 key pair **"CAD-DA2 SSH ACCESS KEY"** already created in `ap-southeast-2`
- Node.js 18+ and npm (for the React build)

### One-time setup

```bash
# 1. Set your real passwords (never commit these)
export TF_VAR_ide_pass="pick-a-strong-password"
export TF_VAR_db_password="pick-a-db-password"

# 2. Deploy all infrastructure (~10 min first time; Aurora takes the longest)
cd infra/terraform
terraform init
terraform apply      # review the plan, then type 'yes'

# 3. Note the outputs
terraform output      # shows app_url, ec2_public_ip, s3_bucket, aurora_endpoint
```

### Deploy the application code

```bash
# From the repo root — after terraform apply
scripts/deploy.sh \
  --ip  <ec2_public_ip from terraform output> \
  --key ~/.ssh/CAD-DA2-SSH-ACCESS-KEY.pem
```

The deploy script:
1. Builds the React frontend locally (`npm run build`)
2. rsyncs all code to the EC2 instance
3. Installs Python deps in the remote `.venv`
4. Restarts the `agentic-ide` systemd service
5. Polls the health check until the server responds

### Access the app

```
http://<alb_dns_name>      ← via ALB + WAF (public URL)
http://<ec2_public_ip>:8080 ← direct to EC2 (bypass ALB, useful for debugging)
```

The browser will prompt for the username/password set in `TF_VAR_ide_pass`.

### Tear down (stop billing)

```bash
cd infra/terraform
terraform destroy    # removes all AWS resources
```

---

## AWS architecture

```
Internet
   │
   ▼
WAFv2 WebACL  ◄── 3 managed rule groups (CommonRuleSet, KnownBadInputs, IPReputationList)
   │
   ▼
Application Load Balancer  (public, port 80, ap-southeast-2a + 2b)
   │
   ▼
EC2 g4dn.xlarge  (public subnet, port 8080)
   ├── FastAPI + React (agentic-ide.service)
   ├── vLLM Qwen2.5-Coder-7B-AWQ (vllm.service, port 8000)
   └── Docker sandbox (--network none, --read-only, --cap-drop ALL)
   │
   ├── S3  tharun-gopinath-1086-CAD-DA2  ← workspace .cpp/.py files
   │       (versioned, SSE-KMS, lifecycle to Glacier after 30 days)
   │
   └── Aurora Serverless v2 PostgreSQL  (private subnets, encrypted)
           run_logs table: every sandbox execution logged here
```

| AWS Service | Role |
|---|---|
| **WAFv2** | Security — OWASP Top 10, bad inputs, IP reputation blocking |
| **ALB** | Scalability — load balances HTTP traffic, health checks EC2 |
| **EC2 g4dn.xlarge** | Model inference (vLLM), app server, Docker sandbox |
| **S3** | Workspace file storage with versioning (disaster recovery) |
| **Aurora Serverless v2** | Run-log database; 7-day PITR backup (disaster recovery) |
| **Secrets Manager** | Stores IDE password + DB credentials; injected at EC2 boot |
| **IAM role** | EC2 gets least-privilege access to S3 + Secrets Manager only |

---

## Local development (no AWS, no GPU)

```bash
# Python environment
python3 -m venv .venv && . .venv/bin/activate
pip install -r backend/requirements.txt

cp .env.example .env
# Edit .env:
#   - Set LLM_BASE_URL / LLM_API_KEY / LLM_MODEL to a hosted provider
#   - Leave S3_BUCKET and DB_HOST blank (falls back to local files, no DB logging)

# Build React frontend
cd frontend && npm install && npm run build && cd ..

# Build sandbox image
docker build -t ide-sandbox sandbox/

# Start server (auto-rebuilds frontend if src/ changed)
scripts/run.sh --reload
```

**Frontend hot-reload** during UI development:
```bash
scripts/run.sh --reload       # terminal 1 — FastAPI at :8080
cd frontend && npm run dev    # terminal 2 — Vite HMR at :5173
```

Smoke-test without a model:
```bash
curl -u admin:change-me-ide-pass -X POST localhost:8080/api/run \
  -H 'Content-Type: application/json' \
  -d '{"language":"python","code":"print(1+1)"}'
```

# Start vLLM in a tmux pane (first start downloads ~4 GB model)
tmux new -d -s llm 'scripts/start_vllm.sh'

# Start the IDE server in another pane
# (run.sh auto-rebuilds the frontend if src/ is newer than dist/)
tmux new -d -s ide 'scripts/run.sh'

# Auto-stop after 30 minutes of inactivity (add to root crontab)
sudo crontab -e
# Add this line:
# */5 * * * * /home/ubuntu/agentic-ide/scripts/idle_shutdown.sh
```

## Access

```bash
# From your laptop — forwards port 8080 over SSH
ssh -L 8080:localhost:8080 ubuntu@<instance-public-ip>
# Then open http://localhost:8080 in your browser
```

No inbound port other than SSH (22, your IP only) is needed.
The browser will prompt for the username/password set in `.env`.

---

## Development (no GPU)

You can run the IDE locally without a GPU by pointing `LLM_BASE_URL` at a
hosted provider. See `.env.example` for examples with OpenAI and others.

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r backend/requirements.txt
cp .env.example .env
# Edit .env: set LLM_BASE_URL, LLM_API_KEY, LLM_MODEL for your provider

docker build -t ide-sandbox sandbox/

# Build React frontend
cd frontend && npm install && npm run build && cd ..

scripts/run.sh --reload        # --reload enables auto-reload on Python code changes
```

**Frontend hot-reload** — for fast UI iteration, run the Vite dev server
alongside the FastAPI backend. The Vite server proxies `/api/*` to FastAPI:

```bash
# Terminal 1 — FastAPI backend
scripts/run.sh --reload

# Terminal 2 — Vite dev server with HMR at http://localhost:5173
cd frontend && npm run dev
```

Quick smoke-test (no model needed — just checks the run endpoint):

```bash
curl -u admin:change-me -X POST localhost:8080/api/run \
  -H 'Content-Type: application/json' \
  -d '{"language":"python","code":"print(1+1)"}'
```

---

## Keyboard shortcuts

| Shortcut                       | Action            |
| ------------------------------ | ----------------- |
| `Ctrl+S` / `Cmd+S`         | Save current file |
| `Ctrl+Enter` / `Cmd+Enter` | Run code          |

---

## Architecture

```
Browser ──SSH tunnel──► EC2 g4dn.xlarge
                          FastAPI  (auth, files, /api/run, /api/agent/solve SSE)
                          │  └── Static files (frontend/)
                          ├── Docker sandbox (g++ + python3, --network none)
                          └── vLLM (Qwen2.5-Coder-7B-Instruct-AWQ, port 8000)
                        EBS: model weights + workspace files
```

### File layout

```
backend/app/main.py      FastAPI: auth middleware, file API, /api/run, /api/agent/solve
backend/app/sandbox.py   Docker-based secure runner for untrusted code
backend/app/agent.py     write → run → fix loop (async generator, SSE events)
backend/app/llm.py       OpenAI-compatible model gateway (vLLM or fallback)
backend/app/config.py    All settings, loaded from environment variables
frontend/src/App.tsx         Root component, all state, layout
frontend/src/api.ts          Typed fetch wrappers for all backend endpoints
frontend/src/types.ts        Shared types, language constants, templates
frontend/src/components/     Header, FilePanel, EditorPane, IOPane, SolvePanel
frontend/index.html          Vite entry point
frontend/vite.config.ts      Build config + /api proxy for dev mode
sandbox/Dockerfile       Sandbox image: python:3.12-slim + g++
scripts/run.sh           Builds React app, starts uvicorn; guards against root
scripts/start_vllm.sh    Starts vLLM; checks for GPU
scripts/idle_shutdown.sh Stops the EC2 instance after idle timeout
```

---

## Idle auto-shutdown

`scripts/idle_shutdown.sh` runs every 5 minutes via root cron. It reads the
modification time of `ACTIVITY_FILE` (default `/tmp/ide_last_activity`), which
the FastAPI server touches on every request. If the file is older than
`IDLE_MINUTES` (default 30), it runs `shutdown -h now`.

A stopped EC2 instance incurs only EBS storage costs (~$0.80/month for 10 GB).

---

## Switching the LLM provider

The model gateway (`backend/app/llm.py`) uses the OpenAI SDK and talks to any
OpenAI-compatible endpoint. To use a hosted provider instead of local vLLM,
update these variables in `.env`:

```dotenv
# OpenAI
LLM_BASE_URL=https://api.openai.com/v1
LLM_API_KEY=sk-...
LLM_MODEL=gpt-4o-mini

# Anthropic via LiteLLM proxy
LLM_BASE_URL=http://127.0.0.1:4000/v1
LLM_API_KEY=sk-ant-...
LLM_MODEL=claude-3-haiku-20240307
```

No code changes are needed — just update `.env` and restart the server.

---

## Troubleshooting

### "Docker not found" in Run output

Docker is not installed or not running.

```bash
sudo systemctl start docker
docker ps          # should list running containers (empty is fine)
```

### Model does not respond / times out

Check whether vLLM is running and the model is loaded:

```bash
tmux attach -t llm                      # view vLLM logs
curl http://127.0.0.1:8000/v1/models    # should list the model once loaded
```

The first start downloads ~4 GB and takes several minutes. Subsequent starts
load from the EBS volume and are ready in under a minute.

### "Server is running as root" warning in logs

`run.sh` will exit with an error if you start it as root. Create a non-root
user or switch to your regular user before running `scripts/run.sh`.

### Wrong model name error from vLLM

`LLM_MODEL` in `.env` must exactly match the Hugging Face model ID and the
`--served-model-name` vLLM was started with. Check:

```bash
curl http://127.0.0.1:8000/v1/models | python3 -m json.tool
```

### GPU quota not available on new AWS account

Request an increase for **"Running On-Demand G and VT instances"** in the AWS
Service Quotas console before launching a `g4dn` instance. This takes a few
hours to a day.

### Sandbox compile errors on valid code

Make sure the sandbox image is built and up to date:

```bash
docker build --no-cache -t ide-sandbox sandbox/
```

### Instance auto-stops too quickly

Check and adjust `IDLE_MINUTES` in `.env` and make sure the cron job is
installed in root's crontab (`sudo crontab -l`).
