bash -lc '
set -euo pipefail

echo "[CHECK] GPU status:"
nvidia-smi || { echo "No GPU found. Exiting."; exit 1; }

echo "[CLEAN] Removing old /workspace/app"
rm -rf /workspace/app

echo "[CLONE] Pulling latest repo"
git clone https://github.com/fhartmannwriter/oss-western-romance-writer.git /workspace/app

cd /workspace/app
chmod +x start-runpod.sh
echo "[START] Running startup script"
./start-runpod.sh
'
