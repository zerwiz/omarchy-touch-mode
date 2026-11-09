#!/usr/bin/env bash
# rodd-door.sh — the keyboard's three Rödd controls, in one place.
#
# The shell's touch keyboard carries a start, a stop and a microphone mute. This
# script is the single door behind them: the QML never builds a command, and the
# heavy lifting stays in apps/rodd/start.sh, which already owns the one seat.
#
#   rodd-door.sh start    raise the pipeline and the terminal client, no window
#   rodd-door.sh stop     lower the client, the toolbox and the tunnel
#   rodd-door.sh mute     toggle the microphone, and say which way it went
#   rodd-door.sh status   one line: what answers, and whether the mic is open
#
# The repository is found, never assumed: $YMIR_REPO, then this seat's checkout.
set -uo pipefail

repo="${YMIR_REPO:-}"
if [ -z "$repo" ]; then
  for candidate in "$HOME/ymir" "$HOME/ymir-main"; do
    [ -x "$candidate/apps/rodd/start.sh" ] && { repo="$candidate"; break; }
  done
fi
if [ -z "$repo" ] || [ ! -x "$repo/apps/rodd/start.sh" ]; then
  echo "no Ymir checkout with apps/rodd/start.sh — set YMIR_REPO" >&2
  exit 1
fi

mic_muted() {
  wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED
}

case "${1:-status}" in
  start)
    exec "$repo/apps/rodd/start.sh" --headless
    ;;
  stop)
    exec "$repo/apps/rodd/start.sh" --stop
    ;;
  toggle)
    # One button, two meanings: the same tap raises the voice when it is down and
    # lowers it when it is up, so the button never argues with the light beside it.
    running="$(ps -eo comm=,args= 2>/dev/null | awk '/ talk --url/ && $1 ~ /^speech-to-spee/ {n++} END {print n+0}')"
    if [ "${running:-0}" -gt 0 ]; then
      exec "$repo/apps/rodd/start.sh" --stop
    fi
    exec "$repo/apps/rodd/start.sh" --headless
    ;;
  mute)
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle || exit 1
    if mic_muted; then echo "microphone muted"; else echo "microphone open"; fi
    ;;
  status)
    # one line, for the keyboard's indicator: is the pipeline up, is a client attached,
    # is the microphone open, and is the model rail actually serving the head the voice asks for?
    host="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:8890/ 2>/dev/null)"
    case "$host" in 000|"") host="down" ;; esac
    # Count only real clients. `pgrep -f` would match this very shell, whose own command
    # line carries the pattern, and the light then claimed a voice that was not running.
    # The client's own comm is the truncated `speech-to-speec`, not `python`; match that,
    # and never the shell or awk lines that merely quote the pattern.
    client="$(ps -eo comm=,args= 2>/dev/null | awk '/ talk --url/ && $1 ~ /^speech-to-spee/ {n++} END {print n+0}')"
    if mic_muted; then mic="muted"; else mic="open"; fi
    # The head is whatever the RUNNING host was started with; the default is only a guess.
    head="$(systemctl --user show ymir-voice-host -p ExecStart 2>/dev/null \
      | grep -oE -- '--model_name [^ ]+' | awk '{print $2}' | head -1)"
    head="${head:-${RODD_HEAD_MODEL:-qwen3.6-35b-a3b@iq3_s}}"
    rail="down"; state=""
    models="$(curl -s --max-time 2 http://127.0.0.1:8080/v1/models 2>/dev/null)"
    if [ -n "$models" ]; then
      rail="up"
      # llama-swap reports each model's own state; absent means the rail does not carry it
      state="$(printf '%s' "$models" | python3 -c '
import json,sys
head = sys.argv[1]
try:
    data = json.load(sys.stdin).get("data", [])
except Exception:
    print("unknown"); raise SystemExit
for m in data:
    if m.get("id") == head:
        print((m.get("status") or {}).get("value") or "present")
        break
else:
    print("absent")
' "$head" 2>/dev/null || echo unknown)"
    fi
    echo "host=$host client=$client mic=$mic rail=$rail head=$state"
    ;;
  *)
    echo "usage: rodd-door.sh start|stop|toggle|mute|status" >&2
    exit 2
    ;;
esac
