bash -lc '
set -euo pipefail

echo "[CHECK] Looking for GPU (nvidia-smi)…"
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "[ERROR] nvidia-smi not found. This pod has no GPU attached."
  echo "        Stop the pod and relaunch as a GPU pod (A40 is fine)."
  exit 1
fi

nvidia-smi || { echo "[ERROR] GPU not available. Try Restart Pod."; exit 1; }

echo "[CLEAN] Resetting /workspace/app…"
rm -rf /workspace/app

echo "[CLONE] Pulling repo…"
git clone https://github.com/fhartmannwriter/oss-western-romance-writer.git /workspace/app

cd /workspace/app
chmod +x start-runpod.sh

echo "[LAUNCH] Running start-runpod.sh…"
./start-runpod.sh
'
