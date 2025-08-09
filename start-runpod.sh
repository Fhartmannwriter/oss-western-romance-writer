bash -lc '
set -euo pipefail

echo "[GPU] Checking..."
nvidia-smi || { echo "[ERROR] No GPU detected"; exit 1; }

# ALWAYS move to a safe dir first
cd /                                  # <— important
echo "[DIR] Now in: $(pwd)"

echo "[CLEAN] Preparing /workspace"
mkdir -p /workspace
rm -rf /workspace/app

echo "[GIT] Cloning repo..."
git clone https://github.com/fhartmannwriter/oss-western-romance-writer.git /workspace/app

cd /workspace/app
chmod +x start-runpod.sh
echo "[RUN] ./start-runpod.sh"
./start-runpod.sh
'

