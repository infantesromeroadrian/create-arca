#!/usr/bin/env bash
# Live transcription launcher.
#
# Activates the runtime venv (heavy binaries live outside this skill folder
# in $LT_RUNTIME_DIR, default ~/Code/live-transcribe), prepends bundled CUDA 12
# libs to LD_LIBRARY_PATH (system CUDA may be 13+ which is ABI-incompatible
# with CTranslate2 wheels), resolves the default PipeWire sink, and pipes
# parec into transcribe.py.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="${LT_RUNTIME_DIR:-$HOME/Code/live-transcribe}"

if [ ! -f "$RUNTIME_DIR/.venv/bin/activate" ]; then
    echo "[start.sh] Runtime venv not found at $RUNTIME_DIR/.venv"
    echo "[start.sh] Bootstrap with:"
    echo "    mkdir -p $RUNTIME_DIR && cd $RUNTIME_DIR"
    echo "    uv venv --python 3.12 --seed"
    echo "    uv pip install faster-whisper>=1.2.1 numpy>=2.0 pyyaml>=6.0 nvidia-cublas-cu12 nvidia-cudnn-cu12"
    exit 1
fi
# shellcheck disable=SC1091
source "$RUNTIME_DIR/.venv/bin/activate"

# Resolve the actual python<major>.<minor> directory inside the venv so we
# survive Python upgrades without editing this script.
PY_LIB_NAME="$(python -c 'import sys; print(f"python{sys.version_info.major}.{sys.version_info.minor}")')"
VENV_NV="$RUNTIME_DIR/.venv/lib/${PY_LIB_NAME}/site-packages/nvidia"
if [ ! -d "${VENV_NV}/cublas/lib" ]; then
    echo "[start.sh] CUDA 12 libs not found at ${VENV_NV}/cublas/lib"
    echo "[start.sh] Install: uv pip install nvidia-cublas-cu12 nvidia-cudnn-cu12"
    exit 1
fi
export LD_LIBRARY_PATH="${VENV_NV}/cublas/lib:${VENV_NV}/cudnn/lib:${LD_LIBRARY_PATH:-}"
export LT_RUNTIME_DIR="$RUNTIME_DIR"

if ! command -v pactl >/dev/null 2>&1; then
    echo "[start.sh] pactl not installed (PulseAudio/PipeWire client tools)."
    exit 1
fi
DEFAULT_SINK="$(pactl get-default-sink 2>/dev/null)"
if [ -z "${DEFAULT_SINK}" ]; then
    echo "[start.sh] No default sink resolved. Is PipeWire/PulseAudio running?"
    exit 1
fi

# Bilateral mode (opt-in via LT_BILATERAL=1) — captures BOTH the local
# mic (⟦ user_name ⟧) and the default sink monitor (remote meeting audio) by
# mixing them into a single combined null-sink, then capturing its
# monitor. Resolves the asymmetric-capture problem where bluez headphones
# only carry one direction of the conversation.
#
# Module lifecycle: track loaded module IDs and unload on EXIT/INT/TERM
# so we never leak null-sinks across runs.
LT_LOADED_MODULES=()

cleanup_pulse_modules() {
    if [ ${#LT_LOADED_MODULES[@]} -gt 0 ]; then
        echo ""
        echo "[start.sh] Unloading bilateral modules: ${LT_LOADED_MODULES[*]}"
        for mod_id in "${LT_LOADED_MODULES[@]}"; do
            pactl unload-module "$mod_id" 2>/dev/null || true
        done
    fi
}
trap cleanup_pulse_modules EXIT INT TERM

if [ "${LT_BILATERAL:-0}" = "1" ]; then
    DEFAULT_SOURCE="$(pactl get-default-source 2>/dev/null)"
    if [ -z "${DEFAULT_SOURCE}" ]; then
        echo "[start.sh] LT_BILATERAL=1 but no default source resolved. Mic missing?"
        exit 1
    fi

    # 1. Null-sink that mixes everything.
    SINK_MOD="$(pactl load-module module-null-sink \
        sink_name=lt_combined \
        sink_properties='device.description="ARCA-LT-Combined"' 2>/dev/null)"
    if [ -z "${SINK_MOD}" ]; then
        echo "[start.sh] Failed to load module-null-sink lt_combined."
        exit 1
    fi
    LT_LOADED_MODULES+=("$SINK_MOD")

    # 2. Loopback: mic -> combined.
    MIC_LOOP="$(pactl load-module module-loopback \
        source="${DEFAULT_SOURCE}" \
        sink=lt_combined \
        latency_msec=100 2>/dev/null)"
    if [ -z "${MIC_LOOP}" ]; then
        echo "[start.sh] Failed to loopback mic ${DEFAULT_SOURCE} -> lt_combined."
        exit 1
    fi
    LT_LOADED_MODULES+=("$MIC_LOOP")

    # 3. Loopback: remote audio (default sink monitor) -> combined.
    REMOTE_LOOP="$(pactl load-module module-loopback \
        source="${DEFAULT_SINK}.monitor" \
        sink=lt_combined \
        latency_msec=100 2>/dev/null)"
    if [ -z "${REMOTE_LOOP}" ]; then
        echo "[start.sh] Failed to loopback ${DEFAULT_SINK}.monitor -> lt_combined."
        exit 1
    fi
    LT_LOADED_MODULES+=("$REMOTE_LOOP")

    MONITOR="lt_combined.monitor"
    echo "[start.sh] BILATERAL mode active."
    echo "[start.sh] Mic source: ${DEFAULT_SOURCE}"
    echo "[start.sh] Remote source: ${DEFAULT_SINK}.monitor"
    echo "[start.sh] Combined sink modules: ${LT_LOADED_MODULES[*]}"
else
    MONITOR="${DEFAULT_SINK}.monitor"
fi

echo "[start.sh] Skill: ${SKILL_DIR}"
echo "[start.sh] Runtime: ${RUNTIME_DIR}"
echo "[start.sh] Default sink: ${DEFAULT_SINK}"
echo "[start.sh] Capturing monitor: ${MONITOR}"
echo "[start.sh] Output: ${LT_TRANSCRIPT_PATH:-/tmp/live-transcript.txt}"
echo "[start.sh] Ctrl+C to stop."
echo ""

cd "$SKILL_DIR"
# NOTE: not 'exec' — we need the trap to fire on Ctrl+C so the modules
# get unloaded. With exec, the trap is replaced by parec.
parec \
    --device="${MONITOR}" \
    --format=s16le \
    --rate=16000 \
    --channels=1 \
    --raw \
    | python transcribe.py
