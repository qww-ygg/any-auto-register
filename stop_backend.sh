#!/usr/bin/env bash

set -euo pipefail

BACKEND_PORT="${BACKEND_PORT:-8000}"
SOLVER_PORT="${SOLVER_PORT:-8889}"
GROK2API_PORT="${GROK2API_PORT:-8011}"
CLIPROXYAPI_PORT="${CLIPROXYAPI_PORT:-8317}"
FULL_STOP="${FULL_STOP:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend-port)
      BACKEND_PORT="${2:?缺少 --backend-port 参数值}"
      shift 2
      ;;
    --solver-port)
      SOLVER_PORT="${2:?缺少 --solver-port 参数值}"
      shift 2
      ;;
    --grok2api-port)
      GROK2API_PORT="${2:?缺少 --grok2api-port 参数值}"
      shift 2
      ;;
    --cliproxyapi-port)
      CLIPROXYAPI_PORT="${2:?缺少 --cliproxyapi-port 参数值}"
      shift 2
      ;;
    --full-stop)
      FULL_STOP="${2:?缺少 --full-stop 参数值}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
用法: ./stop_backend.sh [选项]

选项:
  --backend-port PORT     指定后端端口，默认 8000
  --solver-port PORT      指定 Solver 端口，默认 8889
  --grok2api-port PORT    指定 grok2api 端口，默认 8011
  --cliproxyapi-port PORT 指定 CLIProxyAPI 端口，默认 8317
  --full-stop 0|1         是否同时停止外部集成服务，默认 1
EOF
      exit 0
      ;;
    *)
      echo "[ERROR] 未知参数: $1" >&2
      exit 1
      ;;
  esac
done

PORTS=("$BACKEND_PORT" "$SOLVER_PORT")
if [[ "$FULL_STOP" != "0" ]]; then
  PORTS+=("$GROK2API_PORT" "$CLIPROXYAPI_PORT")
fi

declare -A PID_MAP=()

collect_pids_by_lsof() {
  local port
  for port in "${PORTS[@]}"; do
    [[ -n "$port" && "$port" != "0" ]] || continue
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && PID_MAP["$pid"]=1
    done < <(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
  done
}

collect_pids_by_fuser() {
  local port
  for port in "${PORTS[@]}"; do
    [[ -n "$port" && "$port" != "0" ]] || continue
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && PID_MAP["$pid"]=1
    done < <(fuser -n tcp "$port" 2>/dev/null | tr ' ' '\n' || true)
  done
}

collect_pids_by_ss() {
  local port
  for port in "${PORTS[@]}"; do
    [[ -n "$port" && "$port" != "0" ]] || continue
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && PID_MAP["$pid"]=1
    done < <(ss -ltnp "sport = :$port" 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' || true)
  done
}

if command -v lsof >/dev/null 2>&1; then
  collect_pids_by_lsof
elif command -v fuser >/dev/null 2>&1; then
  collect_pids_by_fuser
elif command -v ss >/dev/null 2>&1; then
  collect_pids_by_ss
else
  echo "[ERROR] 未找到 lsof / fuser / ss，无法按端口定位进程。" >&2
  exit 1
fi

if [[ "${#PID_MAP[@]}" -eq 0 ]]; then
  echo "[INFO] 未发现需要停止的进程"
  exit 0
fi

echo "[INFO] 准备停止端口: ${PORTS[*]}"

wait_for_exit() {
  local pid="$1"
  local timeout="${2:-6}"
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= timeout * 4 )); then
      return 1
    fi
    sleep 0.25
    elapsed=$((elapsed + 1))
  done
  return 0
}

for pid in "${!PID_MAP[@]}"; do
  if ! kill -0 "$pid" 2>/dev/null; then
    continue
  fi

  echo "[INFO] 尝试优雅停止 PID=$pid"
  kill "$pid" 2>/dev/null || true
  if wait_for_exit "$pid" 6; then
    echo "[OK] 已停止 PID=$pid"
    continue
  fi

  echo "[WARN] PID=$pid 未在预期时间退出，改为强制停止"
  kill -9 "$pid" 2>/dev/null || true
  if wait_for_exit "$pid" 6; then
    echo "[OK] 已强制停止 PID=$pid"
    continue
  fi

  echo "[WARN] PID=$pid 停止失败"
done

echo "[INFO] 停止完成"
