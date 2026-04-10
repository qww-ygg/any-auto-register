#!/usr/bin/env bash

set -euo pipefail

ENV_NAME="${APP_CONDA_ENV:-any-auto-register}"
BIND_HOST="${HOST:-0.0.0.0}"
PORT_VALUE="${PORT:-8000}"
SOLVER_PORT_VALUE="${SOLVER_PORT:-8889}"
RESTART_EXISTING="${RESTART_EXISTING:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-name)
      ENV_NAME="${2:?缺少 --env-name 参数值}"
      shift 2
      ;;
    --host)
      BIND_HOST="${2:?缺少 --host 参数值}"
      shift 2
      ;;
    --port)
      PORT_VALUE="${2:?缺少 --port 参数值}"
      shift 2
      ;;
    --solver-port)
      SOLVER_PORT_VALUE="${2:?缺少 --solver-port 参数值}"
      shift 2
      ;;
    --restart-existing)
      RESTART_EXISTING="${2:?缺少 --restart-existing 参数值}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
用法: ./start_backend.sh [选项]

选项:
  --env-name NAME         指定 conda 环境名，默认 any-auto-register
  --host HOST             指定绑定地址，默认 0.0.0.0
  --port PORT             指定后端端口，默认 8000
  --solver-port PORT      指定 Solver 端口，默认 8889
  --restart-existing 0|1  启动前是否先停止旧进程，默认 1
EOF
      exit 0
      ;;
    *)
      echo "[ERROR] 未知参数: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v conda >/dev/null 2>&1; then
  echo "[ERROR] 未找到 conda 命令。请先安装 Miniconda/Anaconda，并确保 conda 可在终端中使用。" >&2
  exit 1
fi

DISPLAY_HOST="$BIND_HOST"
if [[ "$DISPLAY_HOST" == "0.0.0.0" ]]; then
  DISPLAY_HOST="localhost"
fi

echo "[INFO] 项目目录: $ROOT_DIR"
echo "[INFO] 使用 conda 环境: $ENV_NAME"
echo "[INFO] 启动后端: http://$DISPLAY_HOST:$PORT_VALUE"
echo "[INFO] 按 Ctrl+C 可停止服务"

if [[ "$RESTART_EXISTING" == "1" ]]; then
  echo "[INFO] 启动前先清理旧的后端 / Solver 进程"
  BACKEND_PORT="$PORT_VALUE" SOLVER_PORT="$SOLVER_PORT_VALUE" FULL_STOP=0 bash "$ROOT_DIR/stop_backend.sh"
fi

PYTHON_EXE="$(conda run --no-capture-output -n "$ENV_NAME" python -c 'import sys; print(sys.executable)' | tail -n 1)"
if [[ -z "$PYTHON_EXE" || ! -x "$PYTHON_EXE" ]]; then
  echo "[ERROR] 无法解析 conda 环境 '$ENV_NAME' 对应的 python 路径。" >&2
  exit 1
fi

export HOST="$BIND_HOST"
export PORT="$PORT_VALUE"
export SOLVER_PORT="$SOLVER_PORT_VALUE"

echo "[INFO] Python: $PYTHON_EXE"
exec "$PYTHON_EXE" main.py
