bash -lc '
set -euo pipefail

echo "[GPU] Checking..."
nvidia-smi || { echo "[ERROR] No GPU detected"; exit 1; }

echo "[CLEAN] Removing /workspace/app"
mkdir -p /workspace
rm -rf /workspace/app

echo "[GIT] Cloning..."
git clone https://github.com/fhartmannwriter/oss-western-romance-writer.git /workspace/app

cd /workspace/app
chmod +x start-runpod.sh
echo "[RUN] ./start-runpod.sh"
./start-runpod.sh
'

