# shellcheck shell=bash
# agent-root revoke: root-side steps, embedded in the script that
# `agent-root revoke HOST` prints. The generated header defines host_name and
# pubkey; common.sh supplies the shared target-side helpers.
# shellcheck disable=SC2154

_revoke() {
  _require_root
  _snapshot "$exec_path" "$dropin" "$auth_keys"

  _rewrite_keys "$(_key_blob "$pubkey")"

  # The wrapper, drop-in, and key file serve every agent-root key on this
  # host. Remove them only with the last key, so revoking one client keeps
  # the others.
  if ! grep -q '[^[:space:]]' "$auth_keys" 2>/dev/null; then
    rm -f -- "$dropin" "$exec_path" "$auth_keys"
    rmdir -- "$(dirname -- "$auth_keys")" 2>/dev/null || true
  fi

  "$sshd_bin" -t >"$work/sshd-t.out" 2>&1 ||
    _fail "sshd rejected the configuration: $(<"$work/sshd-t.out")"
  _reload_sshd
  _committed
  if [[ -e "$dropin" ]]; then
    printf 'agent-root: revoked %s; other agent-root keys remain enrolled\n' "$host_name"
  else
    printf 'agent-root: revoked %s; removed the last key, %s, its key file, and the sshd drop-in\n' \
      "$host_name" "$EXEC_PATH"
  fi
}

_revoke
