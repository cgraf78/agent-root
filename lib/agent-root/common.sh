# shellcheck shell=bash
# Target-side helpers shared by the enroll and revoke scripts that agent-root
# prints. Those scripts run as root on hosts that may not have agent-root
# installed, so the client embeds this file verbatim instead of sourcing it.
#
# Every change is transactional: files are snapshotted first, and any failure
# before _committed restores them (and reloads sshd if it was already
# reloaded), so a bad configuration cannot lock out ordinary logins.

set -euo pipefail

# The paths written into the key entry and the sshd drop-in. AGENT_ROOT_TARGET_ROOT
# relocates the files for tests only; the logical paths never change.
EXEC_PATH=/usr/local/sbin/agent-root-exec
KEYS_PATH=/etc/ssh/agent-root/authorized_keys
target_root=${AGENT_ROOT_TARGET_ROOT:-}

# These paths and tools are read by the enroll and revoke steps that follow
# this file in the generated script.
# shellcheck disable=SC2034
exec_path=$target_root$EXEC_PATH
# shellcheck disable=SC2034
dropin=$target_root/etc/ssh/sshd_config.d/50-agent-root.conf
sshd_config=$target_root/etc/ssh/sshd_config
# agent-root keys live in their own file, named by the drop-in's
# AuthorizedKeysFile, so root's own authorized_keys is never edited and never
# grants access through this path.
auth_keys=$target_root$KEYS_PATH
# shellcheck disable=SC2034
sshd_bin=${AGENT_ROOT_SSHD:-$(command -v sshd 2>/dev/null || printf /usr/sbin/sshd)}
systemctl_bin=${AGENT_ROOT_SYSTEMCTL:-systemctl}

work=$(mktemp -d "${TMPDIR:-/tmp}/agent-root-target.XXXXXXXX")
snapshots=()
created_dirs=()
reloaded=0
committed=0

_fail() {
  printf 'agent-root: %s\n' "$1" >&2
  exit 1
}

# Restore every snapshot even if one restore fails, so a single problem does not
# leave the rest of the change in place.
_rollback() {
  local status=$? i file incomplete=0

  if ((committed == 0)); then
    for i in "${!snapshots[@]}"; do
      file=${snapshots[$i]}
      if [[ -e "$work/snap.$i" ]]; then
        _make_dir "$(dirname -- "$file")" &&
          cp -p -- "$work/snap.$i" "$file" || incomplete=1
      else
        rm -f -- "$file" || incomplete=1
      fi
    done
    # Newest first, so nested directories go before their parents. rmdir
    # leaves any directory that still holds something.
    for ((i = ${#created_dirs[@]} - 1; i >= 0; i--)); do
      rmdir -- "${created_dirs[$i]}" 2>/dev/null || true
    done
    if ((incomplete)); then
      printf 'agent-root: could not restore every file; check: %s\n' "${snapshots[*]}" >&2
    elif ((${#snapshots[@]} > 0)); then
      printf 'agent-root: restored the previous files; nothing changed\n' >&2
    fi
    ((reloaded == 0)) || _reload_sshd || true
  fi
  rm -rf -- "$work"
  exit "$status"
}
trap _rollback EXIT

_committed() {
  committed=1
}

_require_root() {
  [[ -n "$target_root" || "$(id -u)" == 0 ]] || _fail "run this script as root"
}

# The drop-in only takes effect if sshd_config includes sshd_config.d. Refuse
# rather than edit the stock main file.
_require_dropin_include() {
  [[ -f "$sshd_config" ]] || _fail "missing $sshd_config"
  grep -Eq '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d/' "$sshd_config" ||
    _fail "$sshd_config does not include sshd_config.d; add the stock Include line first"
}

_snapshot() {
  local file i

  for file in "$@"; do
    i=${#snapshots[@]}
    snapshots+=("$file")
    if [[ -e "$file" ]]; then
      cp -p -- "$file" "$work/snap.$i"
    fi
  done
}

# Create a directory and its missing parents, recording each one created so a
# rollback can remove them again. Mode 0755 regardless of umask, because sshd's
# StrictModes rejects a key file under a group- or world-writable directory.
_make_dir() {
  local dir="$1" missing=() i

  while [[ ! -d "$dir" ]]; do
    missing=("$dir" ${missing[@]+"${missing[@]}"})
    dir=$(dirname -- "$dir")
  done
  for i in "${!missing[@]}"; do
    mkdir -m 0755 -- "${missing[$i]}" || return 1
    created_dirs+=("${missing[$i]}")
  done
}

# Write through a temporary file in the destination directory so a reader (or
# sshd) never sees a partial file.
_install_file() {
  local dest="$1" mode="$2" producer="$3" dir tmp

  dir=$(dirname -- "$dest")
  _make_dir "$dir"
  tmp=$(mktemp "$dir/.agent-root.XXXXXXXX")
  "$producer" >"$tmp"
  chmod "$mode" "$tmp"
  mv -f -- "$tmp" "$dest"
}

_key_blob() {
  printf '%s\n' "$1" | awk '{ print $2 }'
}

# Drop every authorized_keys line carrying this key blob, then append the new
# entry if one is given. Matching the base64 blob as a whole field (not a
# substring or comment) keeps unrelated keys untouched.
_rewrite_keys() {
  local blob="$1" line="${2:-}"

  # Invoked through _install_file.
  # shellcheck disable=SC2329
  _keys_producer() {
    if [[ -f "$auth_keys" ]]; then
      awk -v blob="$blob" '{ for (i = 1; i <= NF; i++) if ($i == blob) next; print }' "$auth_keys"
    fi
    if [[ -n "$line" ]]; then
      printf '%s\n' "$line"
    fi
  }
  _install_file "$auth_keys" 0600 _keys_producer
}

# sshd -T needs concrete addresses; CIDR ranges and patterns in from_addrs are
# still enforced by sshd but cannot be probed. Split on commas without word
# splitting so a pattern such as 10.0.0.* is never glob-expanded.
_literal_addrs() {
  local addr addrs

  IFS=, read -r -a addrs <<<"$1"
  for addr in "${addrs[@]}"; do
    case "$addr" in
      */* | *'*'* | *'?'*) ;;
      *) printf '%s\n' "$addr" ;;
    esac
  done
}

_reload_sshd() {
  local unit

  for unit in sshd.service ssh.service; do
    if "$systemctl_bin" is-active --quiet "$unit" 2>/dev/null; then
      "$systemctl_bin" reload "$unit" || return 1
      reloaded=1
      return 0
    fi
  done
  # Socket-activated sshd (for example Debian's ssh.socket) reads the
  # configuration for each connection, so there is nothing to reload.
  printf 'agent-root: no running sshd service to reload; new connections read the updated configuration\n'
}
