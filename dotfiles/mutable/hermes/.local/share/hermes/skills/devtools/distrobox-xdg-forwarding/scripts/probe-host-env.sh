#!/bin/sh
# Host-side probe: drop this on the HOST at /tmp/probe-host-env.sh, chmod +x.
# Then from inside the container run:  host-spawn /tmp/probe-host-env.sh
# Inspect /tmp/probe-host-env.out on the HOST to see what env host-spawn
# actually delivered. DISPLAY=[] proves the -env whitelist is dropping DISPLAY.
out="${PROBE_OUT:-/tmp/probe-host-env.out}"
printf 'PROBE DISPLAY=[%s] WAYLAND=[%s] at %s\n' "${DISPLAY:-}" "${WAYLAND_DISPLAY:-}" "$(date +%T.%N)" >> "$out"
