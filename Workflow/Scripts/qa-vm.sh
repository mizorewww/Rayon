#!/bin/zsh
# qa-vm.sh — drive the headless `rayon-qa` lume VM used for Rayon UI QA.
#   start | grant | push <Rayon.app> | run <cmd...> | shot <out.png> | stop | ip | vnc
set -euo pipefail

VM=${QA_VM:-rayon-qa}
GUEST_USER=lume
KEY=${QA_VM_KEY:-$HOME/.ssh/rayon_qa_vm}
LUME=${LUME:-$HOME/.local/bin/lume}
SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

die() { print -u2 -- "qa-vm: $*"; exit 1; }
info() { "$LUME" get "$VM" --format json 2>/dev/null | /usr/bin/python3 -Ic 'import sys,json; print(json.load(sys.stdin)[0].get(sys.argv[1]) or "")' "$1"; }
state() { info status; }
guest_ip() { local ip; ip=$(info ipAddress); [[ -n $ip ]] || die "$VM has no IP (is it running?)"; print -- $ip; }
gssh() { ssh "${SSH_OPTS[@]}" "$GUEST_USER@$(guest_ip)" "$@"; }

wait_ssh() {
  local i
  for i in {1..90}; do
    if [[ -n $(info ipAddress) ]] && gssh true 2>/dev/null; then return 0; fi
    sleep 2
  done
  die "SSH to $VM did not come up"
}

cmd=${1:-}; (( $# )) && shift
case $cmd in
  start)
    if [[ $(state) != running ]]; then
      "$LUME" run "$VM" --display none --detach >/dev/null 2>&1 || die "lume run failed (see ~/Library/Logs/lume/$VM.log)"
    fi
    wait_ssh
    # Launch the cua-driver daemon in the guest's GUI session (via LaunchServices, so TCC
    # attributes it to CuaDriver.app) unless it is already up.
    gssh '~/.local/bin/cua-driver status >/dev/null 2>&1 || open -g -a /Applications/CuaDriver.app --args serve'
    print -- "$VM running at $(guest_ip)"
    ;;
  push)
    (( $# == 1 )) || die "usage: push <path/to/App.app>"
    src=${1%/}
    [[ -d $src && $src == *.app ]] || die "not an .app bundle: $src"
    name=${src:t}
    gssh "mkdir -p ~/Applications && rm -rf ~/Applications/${(q)name}.incoming"
    # tar keeps symlinks, xattrs and the code signature intact.
    COPYFILE_DISABLE=0 tar -C "${src:h}" -cf - "$name" \
      | gssh "mkdir -p ~/Applications/${(q)name}.incoming && tar -C ~/Applications/${(q)name}.incoming -xf - \
              && rm -rf ~/Applications/${(q)name} && mv ~/Applications/${(q)name}.incoming/${(q)name} ~/Applications/ \
              && rmdir ~/Applications/${(q)name}.incoming"
    print -- "pushed $name -> ~/Applications/$name"
    ;;
  run)
    (( $# )) || die "usage: run <cmd...>"
    # Args are joined into one remote shell command line; quote JSON accordingly.
    gssh "export PATH=\$HOME/.local/bin:/opt/homebrew/bin:\$PATH; $*"
    ;;
  shot)
    (( $# == 1 )) || die "usage: shot <out.png>"
    # Capture through lume's VNC server on the host: needs no TCC grant in the guest.
    out=${1:a}
    url=$(info vncUrl); [[ -n $url ]] || die "$VM has no VNC URL (is it running?)"
    hostport=${url##*@}; pass=${${url#vnc://:}%@*}
    rm -f "$out"
    uvx -q --default-index https://pypi.org/simple --from 'vncdotool==1.2.0' \
      vncdo -s "${hostport%:*}::${hostport##*:}" -p "$pass" capture "$out" || die "VNC capture failed"
    [[ -s $out ]] || die "empty screenshot"
    print -- "$out"
    ;;
  grant)
    # The cua image ships with SIP off, so cua-driver's TCC grants can be written
    # straight into the guest's system TCC database; no click in the VM needed.
    gssh 'zsh -s' <<'EOF'
set -euo pipefail
codesign -dr - /Applications/CuaDriver.app 2>/dev/null | sed -n 's/^designated => //p' > /tmp/cua.req
csreq -r /tmp/cua.req -b /tmp/cua.req.bin
req=$(xxd -p /tmp/cua.req.bin | tr -d '\n')
for service in kTCCServiceAccessibility kTCCServiceScreenCapture kTCCServicePostEvent kTCCServiceListenEvent; do
  echo lume | sudo -S -p '' sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
    "INSERT OR REPLACE INTO access (service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified,pid,pid_version,boot_uuid,last_reminded) VALUES ('$service','com.trycua.driver',0,2,4,1,X'$req',NULL,0,'UNUSED',NULL,0,CAST(strftime('%s','now') AS INTEGER),NULL,NULL,'UNUSED',0);"
done
~/.local/bin/cua-driver stop >/dev/null 2>&1 || true
open -g -a /Applications/CuaDriver.app --args serve
sleep 3
~/.local/bin/cua-driver permissions grant
EOF
    ;;
  stop)
    if [[ $(state) == running ]]; then "$LUME" stop "$VM" --timeout 30 >/dev/null 2>&1; fi
    print -- "$VM $(state)"
    ;;
  ip)  guest_ip ;;
  vnc) info vncUrl ;;
  *) die "usage: qa-vm.sh start | grant | push <App.app> | run <cmd...> | shot <out.png> | stop | ip | vnc" ;;
esac
