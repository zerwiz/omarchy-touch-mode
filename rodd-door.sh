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
  mute)
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle || exit 1
    if mic_muted; then echo "microphone muted"; else echo "microphone open"; fi
    ;;
  status)
    host="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:8890/ 2>/dev/null || echo down)"
    client="$(pgrep -fc ' talk --url' 2>/dev/null || echo 0)"
    if mic_muted; then mic="muted"; else mic="open"; fi
    echo "host=$host client=$client mic=$mic"
    ;;
  *)
    echo "usage: rodd-door.sh start|stop|mute|status" >&2
    exit 2
    ;;
esac
