#!/bin/bash

# Runs RayonSSH's live tests against two throwaway sshd containers — a
# server and, on a private network behind it, a ProxyJump target — and
# removes them afterwards. Needs Docker. Arguments go to `swift test`.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
NAME="rayon-ssh-test-$$"

cleanup() {
    docker rm -f "$NAME-server" "$NAME-target" >/dev/null 2>&1 || true
    docker network rm "$NAME" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

docker build -q -t rayon-ssh-test:latest "$HERE" >/dev/null

# Keys in every format the app reads.
ssh-keygen -q -t ed25519 -N '' -C ed25519 -f "$WORK/ed25519"
ssh-keygen -q -t ecdsa -b 256 -N '' -C ecdsa -f "$WORK/ecdsa"
ssh-keygen -q -t rsa -b 3072 -N '' -C rsa -f "$WORK/rsa"
ssh-keygen -q -t rsa -b 2048 -m PEM -N '' -C rsa-pem -f "$WORK/rsa-pem"
ssh-keygen -q -t ed25519 -N 'key-passphrase' -C ed25519-encrypted -f "$WORK/ed25519-encrypted"
ssh-keygen -q -t rsa -b 2048 -N 'key-passphrase' -C rsa-encrypted -f "$WORK/rsa-encrypted"
ssh-keygen -q -t rsa -b 2048 -m PEM -N 'key-passphrase' -C rsa-pem-encrypted -f "$WORK/rsa-pem-encrypted"
cat "$WORK"/*.pub > "$WORK/authorized_keys"

# The server is published on the host's loopback; the target is only on a
# private network the server is also on.
docker network create --internal "$NAME" >/dev/null
docker run -d --name "$NAME-target" --network "$NAME" --network-alias target rayon-ssh-test:latest >/dev/null
docker run -d --name "$NAME-server" -p 127.0.0.1::22 rayon-ssh-test:latest >/dev/null
docker network connect "$NAME" "$NAME-server"
for role in server target; do
    docker cp "$WORK/authorized_keys" "$NAME-$role:/home/rayon/.ssh/authorized_keys"
    docker exec "$NAME-$role" sh -c 'chown -R rayon /home/rayon/.ssh && chmod 600 /home/rayon/.ssh/authorized_keys'
done

PORT="$(docker port "$NAME-server" 22/tcp | head -1 | sed 's/.*://')"
docker exec "$NAME-server" sh -c 'cat /etc/ssh/ssh_host_ed25519_key.pub' > "$WORK/host_ed25519.pub"
for _ in $(seq 50); do
    nc -z 127.0.0.1 "$PORT" 2>/dev/null && break
    sleep 0.2
done

SSH_DOCKER_LIVE="$WORK" SSH_DOCKER_LIVE_PORT="$PORT" \
    swift test --package-path "$PACKAGE" --filter SSHLiveTests "$@"
