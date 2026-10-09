#!/usr/bin/env bash
# Starts vLLM serving an OpenAI-compatible API on http://127.0.0.1:8000.
# Designed for an NVIDIA T4 (g4dn.xlarge): no bf16, so --dtype half.
#
# First run downloads the model (~4 GB for the AWQ variant).
# Check model availability with:  curl http://127.0.0.1:8000/v1/models
set -euo pipefail

# ── GPU check ─────────────────────────────────────────────────────────────
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi not found. vLLM requires an NVIDIA GPU." >&2
  echo "       On a CPU-only instance, use a hosted fallback instead:" >&2
  echo "       set LLM_BASE_URL=https://api.openai.com/v1 and LLM_API_KEY in .env" >&2
  exit 1
fi

if ! nvidia-smi --query-gpu=name --format=csv,noheader >/dev/null 2>&1; then
  echo "ERROR: NVIDIA driver not loaded or no GPU visible." >&2
  echo "       Check 'nvidia-smi' output and driver installation." >&2
  exit 1
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
echo "GPU detected: ${GPU_NAME}"

# ── Load .env if present ──────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env"
  set +a
fi

MODEL="${LLM_MODEL:-Qwen/Qwen2.5-Coder-7B-Instruct-AWQ}"
echo "Starting vLLM with model: ${MODEL}"
echo "Note: first run downloads ~4 GB — this may take several minutes."

exec python -m vllm.entrypoints.openai.api_server \
  --model           "${MODEL}" \
  --quantization    awq \
  --dtype           half \
  --max-model-len   4096 \
  --gpu-memory-utilization 0.90 \
  --served-model-name "${MODEL}" \
  --host            127.0.0.1 \
  --port            8000
