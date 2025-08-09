#!/usr/bin/env bash
set -euo pipefail

# -------- CONFIG FROM ENV (with defaults for first boot) --------
: "${MODEL_ID:=Qwen/Qwen2-7B-Instruct}"
: "${TENSOR_PARALLEL_SIZE:=1}"
: "${DTYPE:=auto}"
: "${MAX_MODEL_LEN:=4096}"
: "${QUANTIZATION:=}"
: "${VLLM_PORT:=8000}"
: "${WRITER_BOT_PORT:=5050}"
: "${OPENAI_BASE_URL:=http://localhost:8000/v1}"
: "${OPENAI_API_KEY:=not-needed-but-required}"
: "${SYSTEM_PROMPT_PATH:=./configs/prompts/system-western.txt}"
: "${STYLE_GUIDE_PATH:=./configs/prompts/style-constraints.md}"

echo "[SETUP] Updating apt and installing basics..."
apt-get update -y && apt-get install -y python3 python3-pip git curl jq && rm -rf /var/lib/apt/lists/*

echo "[SETUP] Upgrading pip..."
python3 -m pip install --upgrade pip wheel

echo "[SETUP] Installing vLLM + Torch (CUDA 12.1)..."
python3 -m pip install vllm==0.5.4.post1 torch==2.3.1 --extra-index-url https://download.pytorch.org/whl/cu121

echo "[SETUP] Installing writer-bot deps..."
python3 -m pip install fastapi==0.111.0 uvicorn==0.30.1 httpx==0.27.0 pydantic==2.7.4

# Optional: Login to HF if HF token is provided (for gated models)
if [[ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
  echo "[HF] Token detected; configuring huggingface-cli..."
  python3 -m pip install --upgrade huggingface_hub
  python3 - <<'PY'
from huggingface_hub import login
import os
tok=os.environ.get("HUGGING_FACE_HUB_TOKEN")
if tok: login(tok)
PY
fi

echo "[VLLM] Launching server on port ${VLLM_PORT} with model ${MODEL_ID} ..."
python3 -m vllm.entrypoints.openai.api_server \
  --port "${VLLM_PORT}" \
  --model "${MODEL_ID}" \
  --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}" \
  --dtype "${DTYPE}" \
  --max-model-len "${MAX_MODEL_LEN}" \
  ${QUANTIZATION:+--quantization "${QUANTIZATION}"} \
  --served-model-name oss-writer-model \
  --enforce-eager \
  > /tmp/vllm.log 2>&1 &

echo "[VLLM] Waiting for readiness..."
for n in {1..90}; do
  if curl -s "http://localhost:${VLLM_PORT}/v1/models" | jq . >/dev/null 2>&1; then
    echo "[VLLM] Ready."
    break
  fi
  sleep 2
done

echo "[WRITER] Starting writer-bot on port ${WRITER_BOT_PORT} ..."
# Ensure prompts are present (they are in your repo)
export OPENAI_BASE_URL OPENAI_API_KEY SYSTEM_PROMPT_PATH STYLE_GUIDE_PATH
python3 - <<'PY' &
import os, uvicorn
from fastapi import FastAPI
import httpx
from pydantic import BaseModel
from pathlib import Path

OPENAI_BASE_URL=os.getenv("OPENAI_BASE_URL","http://localhost:8000/v1")
OPENAI_API_KEY=os.getenv("OPENAI_API_KEY","not-needed-but-required")
SYSTEM_PROMPT=Path(os.getenv("SYSTEM_PROMPT_PATH","./configs/prompts/system-western.txt")).read_text(encoding="utf-8")
STYLE_GUIDE=Path(os.getenv("STYLE_GUIDE_PATH","./configs/prompts/style-constraints.md")).read_text(encoding="utf-8")

app=FastAPI(title="Western Romance Writer Bot")

class DraftReq(BaseModel):
    instruction: str
    temperature: float = 0.8
    max_tokens: int = 800

async def openai_chat(messages, temperature: float, max_tokens: int):
    headers={"Authorization": f"Bearer {OPENAI_API_KEY}"}
    async with httpx.AsyncClient(timeout=120) as client:
        r=await client.post(f"{OPENAI_BASE_URL}/chat/completions",
            headers=headers,
            json={"model":"oss-writer-model","messages":messages,
                  "temperature":temperature,"max_tokens":max_tokens,"stream":False})
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"]

@app.post("/draft")
async def draft(req: DraftReq):
    sys_prompt=(SYSTEM_PROMPT+"\n\nStyle Guide:\n"+STYLE_GUIDE).strip()
    messages=[{"role":"system","content":sys_prompt},{"role":"user","content":req.instruction}]
    content=await openai_chat(messages, req.temperature, req.max_tokens)
    return {"content": content}

@app.post("/outline")
async def outline(req: DraftReq):
    prompt=("Create a detailed chapter-by-chapter outline for a Western romance novel. "
            "Honor traditional values and frontier realism. Include scene beats, conflict, and slow-burn escalation.\n\n"
            f"User request: {req.instruction}")
    messages=[{"role":"system","content":SYSTEM_PROMPT},{"role":"user","content":prompt}]
    content=await openai_chat(messages, req.temperature, req.max_tokens)
    return {"content": content}

@app.post("/revise")
async def revise(req: DraftReq):
    prompt=("Revise the passage for clarity, flow, and heat level for a steamy Western romance. "
            "Respect voice, keep sentences under 30 words, avoid em dashes.\n\n"
            f"PASSAGE:\n{req.instruction}")
    messages=[{"role":"system","content":SYSTEM_PROMPT},{"role":"user","content":prompt}]
    content=await openai_chat(messages, req.temperature, req.max_tokens)
    return {"content": content}

if __name__ == "__main__":
    port=int(os.getenv("WRITER_BOT_PORT","5050"))
    uvicorn.run(app, host="0.0.0.0", port=port)
PY

# Keep the container alive
tail -f /tmp/vllm.log
