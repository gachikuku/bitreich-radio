#!/bin/sh

# Plumber script for sacc — handles media URLs by launching mpv,
# and falls back to xdg-open/open for everything else.

pidfile="${XDG_RUNTIME_DIR:-/tmp}/sacc-mpv.pid"

kill_prev() {
    if [ -f "$pidfile" ]; then
        oldpid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
            kill "$oldpid" 2>/dev/null
        fi
        rm -f "$pidfile"
    fi
}

# Detect system opener
if command -v xdg-open >/dev/null 2>&1; then
    OPENER="xdg-open"
elif command -v open >/dev/null 2>&1; then
    OPENER="open"
else
    OPENER="echo"
fi

case "$1" in
    *.mp3|*.m3u|*.pls|*.ogg|*.opus|*.wav|*.flac|*.aac|*.m4a|http://*|https://*)
        kill_prev
        nohup mpv --no-video --ytdl-raw-options=yes-playlist=,no-check-certificates= --ytdl-format=bestaudio "$1" >/dev/null 2>&1 &
        echo $! > "$pidfile"
        ;;
    *)
        exec $OPENER "$1"
        ;;
esac
