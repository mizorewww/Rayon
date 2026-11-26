#!/bin/bash
# Runs VNCLiveTests' VNC-over-SSH test against a throwaway container (VNC on
# its loopback, reached through sshd) and removes it afterwards. Needs Docker.

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
name="rayon-vnc-live-$$"
docker build -q -t rayon-vnc-test:latest "$here" >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" -p 127.0.0.1::22 rayon-vnc-test:latest >/dev/null
port="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
sleep 3
cd "$here/../.."
VNC_LIVE_PORT=5900 VNC_LIVE_PASSWORD=vnc-password \
VNC_LIVE_SSH_PORT="$port" VNC_LIVE_SSH_USER=rayon VNC_LIVE_SSH_PASSWORD=rayon-password \
    swift test --filter VNCLiveTests/testConnectsOverSSHDirectTCPIP "$@"
