#!/usr/bin/env bash
# arca-tts.sh — ARCA out-loud voice via ElevenLabs TTS.
#
# CONSTRAINT #1 (non-negotiable, ADR-015): the voice must NEVER block, hang or
# freeze the Claude Code session. Design = fail-open everywhere (exit 0 on every
# branch) + all network/audio work detached into a background worker so the hook
# returns in milliseconds. The previous voice impl was removed for freezing the
# session; robustness wins over features every single time here.
#
# THREE MODES:
#   (default, no args)  Stop-hook dispatcher. Reads hook JSON from stdin, extracts
#                       the last assistant message, spawns a DETACHED worker, and
#                       exits 0 immediately. Auto-summarises long text via Ollama.
#   --worker            Internal. The detached job that does cleaning + (optional)
#                       summarisation + TTS + playback. Not meant to be called by
#                       hand. Reads its text from a temp file passed as $2.
#   --speak             Manual mode (/speak). Reads the WHOLE last answer from the
#                       newest transcript, no summary, no threshold. Same TTS pipe.
#
# Exit code is ALWAYS 0. There is no failure path that propagates upward.

# Deliberately NO `set -e` / `set -u` / `set -o pipefail`: under fail-open we want
# every command's failure to be swallowed, not to abort the script. A single trap
# guarantees exit 0 even on an unexpected signal or error.
trap 'exit 0' EXIT INT TERM

# --- Load config (fail-open if missing) --------------------------------------
CONFIG_FILE="${ARCA_TTS_CONFIG:-$HOME/.config/elevenlabs/config.sh}"
# shellcheck source=/dev/null
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null

# Defaults in case the config file is absent — the script must still be safe.
ELEVENLABS_VOICE_ID="${ELEVENLABS_VOICE_ID:-gD1IexrzCvsXPHUuT0s3}"
ELEVENLABS_MODEL="${ELEVENLABS_MODEL:-eleven_turbo_v2_5}"
ELEVENLABS_KEY_FILE="${ELEVENLABS_KEY_FILE:-$HOME/.config/elevenlabs/key}"
ELEVENLABS_BASE_URL="${ELEVENLABS_BASE_URL:-https://api.elevenlabs.io/v1/text-to-speech}"
ARCA_TTS_SUMMARY_THRESHOLD="${ARCA_TTS_SUMMARY_THRESHOLD:-400}"
ARCA_TTS_MAX_CHARS="${ARCA_TTS_MAX_CHARS:-1200}"
ARCA_TTS_NET_TIMEOUT="${ARCA_TTS_NET_TIMEOUT:-15}"
ARCA_TTS_OLLAMA_URL="${ARCA_TTS_OLLAMA_URL:-http://127.0.0.1:11434}"
ARCA_TTS_OLLAMA_MODEL="${ARCA_TTS_OLLAMA_MODEL:-qwen2.5:7b}"
ARCA_TTS_OLLAMA_TIMEOUT="${ARCA_TTS_OLLAMA_TIMEOUT:-8}"
ARCA_TTS_PLAYERS="${ARCA_TTS_PLAYERS:-mpv ffplay paplay pw-play aplay}"
ARCA_TTS_CACHE_DIR="${ARCA_TTS_CACHE_DIR:-$HOME/.cache/arca-tts}"
ARCA_TTS_DEBUG="${ARCA_TTS_DEBUG:-0}"

mkdir -p "$ARCA_TTS_CACHE_DIR" 2>/dev/null

# --- Tiny debug logger (off by default) --------------------------------------
log() {
  [ "$ARCA_TTS_DEBUG" = "1" ] || return 0
  printf '%s [arca-tts] %s\n' "$(date '+%H:%M:%S')" "$*" \
    >>"$ARCA_TTS_CACHE_DIR/arca-tts.log" 2>/dev/null
}

# =============================================================================
# Text cleaning for TTS. Strips markdown noise that reads badly aloud:
# fenced code blocks, inline code, tables, links (keeps the link text), headings,
# list bullets, emphasis markers, and bare URLs. Collapses whitespace.
# Pure sed/awk so it has no runtime deps beyond coreutils.
# stdin -> stdout.
# =============================================================================
clean_for_tts() {
  awk '
    BEGIN { incode = 0 }
    # Toggle fenced code blocks (``` or ~~~). Drop everything inside them.
    /^[[:space:]]*(```|~~~)/ { incode = !incode; next }
    incode { next }
    { print }
  ' \
  | sed -E '
      s/`[^`]*`/ /g;                         # inline code -> space
      s/!\[[^]]*\]\([^)]*\)/ /g;             # images -> drop
      s/\[([^]]*)\]\([^)]*\)/\1/g;           # links -> keep visible text
      s#https?://[^[:space:]]+# #g;          # bare URLs -> drop
      s/^[[:space:]]*\|.*\|[[:space:]]*$//;  # table rows -> drop
      s/^[[:space:]]*#{1,6}[[:space:]]*//;   # heading markers
      s/^[[:space:]]*[-*+][[:space:]]+/ /;   # list bullets
      s/^[[:space:]]*[0-9]+\.[[:space:]]+/ /;# numbered list markers
      s/\*\*([^*]*)\*\*/\1/g;                # bold
      s/\*([^*]*)\*/\1/g;                    # italic
      s/__([^_]*)__/\1/g;                    # bold underscore
      s/_([^_]*)_/\1/g;                      # italic underscore
      s/[`*_#>~]/ /g;                        # leftover md punctuation
    ' \
  | tr '\n' ' ' \
  | tr -s ' ' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# =============================================================================
# Extract the text of the LAST assistant message from a transcript JSONL.
# Claude Code transcript lines look like:
#   {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"..."}]}}
# content may also contain tool_use blocks (no "text") which we ignore.
# Robust to junk lines (ai-title, mode, ...) and to invalid JSON via jq -R.
# $1 = transcript path. Prints text or nothing.
# =============================================================================
extract_last_assistant() {
  local tp="$1" line text
  [ -n "$tp" ] && [ -f "$tp" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # The transcript is true JSONL: one valid JSON object per PHYSICAL line, with
  # any newlines INSIDE a message escaped as \n. So we walk lines newest-first
  # and run jq per-line — never `tac | jq -r ... | head -1`, because jq -r would
  # re-materialise the escaped \n and a downstream head -1 would then truncate a
  # multi-paragraph answer at its first line (this was a real bug, fixed here).
  # We capture the whole joined text into a bash var (preserving its newlines)
  # and stop at the first assistant line that yields non-empty text.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    text="$(printf '%s' "$line" | jq -j '
      select(.type == "assistant")
      | (.message.content // [])
      | if type == "array"
          then [ .[] | select(.type == "text") | .text ] | join(" ")
          else (. | tostring)
        end
    ' 2>/dev/null)"
    if [ -n "$text" ]; then
      printf '%s' "$text"
      return 0
    fi
  done < <(tac "$tp" 2>/dev/null)
  return 0
}

# =============================================================================
# Summarise long text to 1-2 Spanish sentences via local Ollama.
# Fail-open: if Ollama is down/slow/garbled, prints NOTHING and the caller falls
# back to truncation. Network call is timeout-wrapped (short budget).
# $1 = text. Prints summary or nothing.
# =============================================================================
summarise_ollama() {
  local text="$1"
  command -v curl >/dev/null 2>&1 || return 0
  command -v jq   >/dev/null 2>&1 || return 0

  local prompt payload resp summary
  prompt="Resume el siguiente mensaje en 1 o 2 frases en castellano, en segunda persona, sin markdown, solo el resumen hablado: ${text}"
  # Build the request body with jq so the text is safely JSON-escaped.
  payload="$(jq -n --arg m "$ARCA_TTS_OLLAMA_MODEL" --arg p "$prompt" \
    '{model:$m, prompt:$p, stream:false}' 2>/dev/null)"
  [ -n "$payload" ] || return 0

  resp="$(timeout "$ARCA_TTS_OLLAMA_TIMEOUT" curl -s --max-time "$ARCA_TTS_OLLAMA_TIMEOUT" \
    "$ARCA_TTS_OLLAMA_URL/api/generate" \
    -H 'Content-Type: application/json' -d "$payload" 2>/dev/null)"
  [ -n "$resp" ] || { log "ollama no response -> fallback truncate"; return 0; }

  summary="$(printf '%s' "$resp" | jq -r '.response // empty' 2>/dev/null)"
  printf '%s' "$summary"
}

# =============================================================================
# Find the first usable audio player from ARCA_TTS_PLAYERS. Prints its name or
# nothing. ffplay/mpv decode MP3; the rest need a WAV (handled in play_mp3).
# =============================================================================
detect_player() {
  local p
  for p in $ARCA_TTS_PLAYERS; do
    command -v "$p" >/dev/null 2>&1 && { printf '%s' "$p"; return 0; }
  done
  return 0
}

# =============================================================================
# Play an MP3 file through the detected player. For PCM-only players, transcode
# MP3 -> WAV via ffmpeg first. All playback is best-effort and silent on failure.
# $1 = mp3 file path.
# =============================================================================
play_mp3() {
  local mp3="$1" player wav
  [ -s "$mp3" ] || { log "empty mp3, nothing to play"; return 0; }
  player="$(detect_player)"
  [ -n "$player" ] || { log "no audio player found"; return 0; }
  log "player=$player"

  case "$player" in
    mpv)
      mpv --no-video --really-quiet "$mp3" </dev/null >/dev/null 2>&1
      ;;
    ffplay)
      ffplay -nodisp -autoexit -loglevel quiet "$mp3" </dev/null >/dev/null 2>&1
      ;;
    paplay|pw-play|aplay)
      # These need PCM/WAV. Transcode with ffmpeg if available, else give up.
      if command -v ffmpeg >/dev/null 2>&1; then
        wav="${mp3%.mp3}.wav"
        ffmpeg -y -loglevel quiet -i "$mp3" "$wav" </dev/null >/dev/null 2>&1
        [ -s "$wav" ] && "$player" "$wav" </dev/null >/dev/null 2>&1
        rm -f "$wav" 2>/dev/null
      else
        log "player $player needs WAV but ffmpeg missing -> skip"
      fi
      ;;
  esac
  return 0
}

# =============================================================================
# Call ElevenLabs streaming TTS, write MP3 to $2, then play it.
# Network call is timeout-wrapped. Fail-open on any error.
# $1 = text to speak, $2 = output mp3 path.
# =============================================================================
synth_and_play() {
  local text="$1" out="$2" key body http
  [ -n "$text" ] || { log "empty text -> skip"; return 0; }

  [ -f "$ELEVENLABS_KEY_FILE" ] || { log "no key file -> skip"; return 0; }
  key="$(tr -d '[:space:]' <"$ELEVENLABS_KEY_FILE" 2>/dev/null)"
  [ -n "$key" ] || { log "empty key -> skip"; return 0; }

  # Enforce the hard char cap (credit guardrail) before sending.
  if [ "${#text}" -gt "$ARCA_TTS_MAX_CHARS" ]; then
    text="$(printf '%s' "$text" | cut -c1-"$ARCA_TTS_MAX_CHARS")"
    log "capped text to $ARCA_TTS_MAX_CHARS chars"
  fi

  # JSON body via jq so the text is properly escaped.
  body="$(jq -n --arg t "$text" --arg m "$ELEVENLABS_MODEL" \
    '{text:$t, model_id:$m}' 2>/dev/null)"
  [ -n "$body" ] || { log "failed to build TTS body"; return 0; }

  log "TTS request: ${#text} chars, voice=$ELEVENLABS_VOICE_ID"
  http="$(timeout "$ARCA_TTS_NET_TIMEOUT" curl -s -w '%{http_code}' \
    --max-time "$ARCA_TTS_NET_TIMEOUT" \
    -X POST "$ELEVENLABS_BASE_URL/$ELEVENLABS_VOICE_ID/stream" \
    -H @- \
    -H 'Content-Type: application/json' \
    -H 'Accept: audio/mpeg' \
    -d "$body" \
    -o "$out" <<<"xi-api-key: $key" 2>/dev/null)"

  if [ "$http" != "200" ]; then
    log "TTS http=$http -> skip playback"
    rm -f "$out" 2>/dev/null
    return 0
  fi
  play_mp3 "$out"
  rm -f "$out" 2>/dev/null
  return 0
}

# =============================================================================
# WORKER: the detached job. Reads cleaned text from a file, decides whether to
# summarise (AUTO long text) or speak verbatim, then synth+play. Single-flight
# guarded by a lock so overlapping Stops don't double-speak.
# $1 = "--worker", $2 = path to text file, $3 = mode tag (auto|manual)
# =============================================================================
run_worker() {
  local txt_file="$2" mode="${3:-auto}" text speak out lock
  text="$(cat "$txt_file" 2>/dev/null)"
  rm -f "$txt_file" 2>/dev/null
  [ -n "$text" ] || { log "worker: empty text"; return 0; }

  # Single-flight: if another worker holds the lock, skip silently. The lock dir
  # is removed on EXIT via the local trap so a crash can't leave it stuck.
  lock="$ARCA_TTS_CACHE_DIR/.lock"
  # Reap a stale lock first: a clean worker never holds it >1min, but a
  # SIGKILL/OOM victim can't fire its trap and would leave the lock forever,
  # muting all future audio. Age-based reap auto-recovers from that.
  [ -d "$lock" ] && find "$lock" -maxdepth 0 -mmin +1 -exec rm -rf {} + 2>/dev/null
  if ! mkdir "$lock" 2>/dev/null; then
    log "worker: lock held, skipping"
    return 0
  fi
  trap 'rm -rf "$lock" 2>/dev/null; exit 0' EXIT INT TERM

  if [ "$mode" = "auto" ] && [ "${#text}" -gt "$ARCA_TTS_SUMMARY_THRESHOLD" ]; then
    log "auto: ${#text} chars > $ARCA_TTS_SUMMARY_THRESHOLD -> summarise"
    speak="$(summarise_ollama "$text")"
    if [ -z "$speak" ]; then
      # Ollama unavailable -> truncate to threshold rather than abort.
      speak="$(printf '%s' "$text" | cut -c1-"$ARCA_TTS_SUMMARY_THRESHOLD")"
      log "auto: ollama empty -> truncated fallback (${#speak} chars)"
    elif [ "${#speak}" -gt "$ARCA_TTS_SUMMARY_THRESHOLD" ]; then
      # Ollama echoed/hallucinated longer than a 1-2 sentence summary -> cap it
      # so the spoken summary stays short instead of an arbitrary long slice.
      speak="$(printf '%s' "$speak" | cut -c1-"$ARCA_TTS_SUMMARY_THRESHOLD")"
      log "auto: ollama summary too long -> capped to threshold"
    fi
  else
    # Short AUTO text, or MANUAL mode: speak verbatim (cap applied in synth).
    speak="$text"
  fi

  out="$ARCA_TTS_CACHE_DIR/tts-$$.mp3"
  synth_and_play "$speak" "$out"
  rm -rf "$lock" 2>/dev/null
  return 0
}

# =============================================================================
# Spawn a fully detached worker and return immediately. setsid + redirected fds
# + background + disown means the worker outlives this hook process and is not
# tied to its stdio — so the hook can exit 0 in milliseconds while audio plays.
# $1 = text, $2 = mode tag.
# =============================================================================
spawn_worker() {
  local text="$1" mode="$2" txt_file
  [ -n "$text" ] || return 0
  txt_file="$ARCA_TTS_CACHE_DIR/text-$$-$RANDOM.txt"
  printf '%s' "$text" >"$txt_file" 2>/dev/null

  local self="${BASH_SOURCE[0]}"
  if command -v setsid >/dev/null 2>&1; then
    setsid bash "$self" --worker "$txt_file" "$mode" </dev/null >/dev/null 2>&1 &
  else
    bash "$self" --worker "$txt_file" "$mode" </dev/null >/dev/null 2>&1 &
  fi
  disown 2>/dev/null
  log "spawned worker mode=$mode pid=$!"
  return 0
}

# =============================================================================
# MAIN dispatch
# =============================================================================
case "${1:-}" in
  --worker)
    # Detached job path. Never reached by the hook runtime directly.
    run_worker "$@"
    exit 0
    ;;

  --speak)
    # MANUAL mode (/speak): read WHOLE last answer, no summary, no threshold.
    # Find newest transcript across all projects (the active session's file).
    tp="$(find "$HOME/.claude/projects" -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
          | sort -rn | head -1 | cut -d' ' -f2-)"
    raw="$(extract_last_assistant "$tp")"
    clean="$(printf '%s' "$raw" | clean_for_tts)"
    [ -n "$clean" ] || { log "speak: nothing to say"; exit 0; }
    spawn_worker "$clean" "manual"
    exit 0
    ;;

  *)
    # AUTO mode: Stop hook. Read the hook JSON from stdin, get transcript_path.
    stdin_json=""
    if [ ! -t 0 ]; then
      stdin_json="$(cat 2>/dev/null)"
    fi
    tp=""
    if [ -n "$stdin_json" ] && command -v jq >/dev/null 2>&1; then
      tp="$(printf '%s' "$stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null)"
    fi
    # Fallback: if no transcript_path provided, use the newest one.
    [ -n "$tp" ] || tp="$(find "$HOME/.claude/projects" -name '*.jsonl' \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"

    raw="$(extract_last_assistant "$tp")"
    clean="$(printf '%s' "$raw" | clean_for_tts)"
    [ -n "$clean" ] || { log "auto: nothing to say"; exit 0; }
    spawn_worker "$clean" "auto"
    exit 0
    ;;
esac
