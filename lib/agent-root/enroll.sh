# shellcheck shell=bash
# agent-root enroll: root-side steps, embedded in the script that
# `agent-root enroll HOST` prints. The generated header defines:
#   host_name   enrolled host name (for messages)
#   pubkey      the client's public key line
#   from_addrs  comma-separated source addresses allowed to use the key
#   _exec_source / _sshd_source  functions printing the files to install
# It also sources common.sh for the shared target-side helpers.
# shellcheck disable=SC2154

# Probe connections whose effective sshd settings must not change. The
# addresses are documentation ranges (RFC 5737) so they never match a real
# enrolled source.
other_probe="user=agent-root-probe,host=probe.invalid,addr=192.0.2.1"
remote_root_probe="user=root,host=probe.invalid,addr=192.0.2.1"

# OpenSSH prints keywords in lowercase up to 9.x and in their configuration
# spelling from 10.x on. Lowercase the keyword column so comparisons and
# checks mean the same thing on every version.
_settings_for() {
  "$sshd_bin" -T -C "$1" 2>&1 | awk '{ $1 = tolower($1); print }'
}

# The settings the drop-in's Match block sets, lowercased like _settings_for,
# one "keyword value" per line. Reading them from the installed drop-in keeps
# the template the single source of what enrollment must prove.
_dropin_settings() {
  awk '/^Match User root /{ inside = 1; next }
       /^Match all/{ inside = 0 }
       inside && $1 !~ /^#/ && NF { $1 = tolower($1); print }' "$dropin"
}

# Enrolling changes only how root logs in from the enrolled addresses. Prove
# that against sshd's own view of the effective configuration rather than by
# reading files, because Include ordering and Match semantics decide the result.
_verify() {
  local addr local_after changed setting owned

  "$sshd_bin" -t >"$work/sshd-t.out" 2>&1 ||
    _fail "sshd rejected the configuration: $(<"$work/sshd-t.out")"

  [[ "$(_settings_for "$other_probe")" == "$(<"$work/other.before")" ]] ||
    _fail "settings for other users changed; refusing to keep the change"
  [[ "$(_settings_for "$remote_root_probe")" == "$(<"$work/remote-root.before")" ]] ||
    _fail "settings for root from other addresses changed; refusing to keep the change"

  _dropin_settings >"$work/dropin.settings"
  [[ -s "$work/dropin.settings" ]] || _fail "the installed drop-in sets nothing"
  owned=$(awk '{ printf "%s%s", (NR > 1 ? "|" : ""), $1 }' "$work/dropin.settings")

  for addr in $(_literal_addrs "$from_addrs"); do
    local_after=$(_settings_for "user=root,host=localhost,addr=$addr")
    # sshd keeps the first value it reads for most keywords, so an earlier
    # Match can silently win over any line of the drop-in. Require every one.
    while IFS= read -r setting; do
      grep -qxF -- "$setting" <<<"$local_after" ||
        _fail "root from $addr does not get '$setting'; another sshd rule may take precedence"
    done <"$work/dropin.settings"
    # Only the settings the drop-in owns may differ for enrolled sources.
    changed=$(diff "$work/local-$addr.before" <(printf '%s\n' "$local_after") |
      sed -n 's/^[<>] //p' | grep -Ev "^($owned) " || true)
    [[ -z "$changed" ]] ||
      _fail "enrolling changed unrelated settings for root from $addr: $changed"
  done
}

_enroll() {
  local addr line

  _require_root
  _require_dropin_include
  _snapshot "$exec_path" "$dropin" "$auth_keys"

  _settings_for "$other_probe" >"$work/other.before"
  _settings_for "$remote_root_probe" >"$work/remote-root.before"
  for addr in $(_literal_addrs "$from_addrs"); do
    _settings_for "user=root,host=localhost,addr=$addr" >"$work/local-$addr.before"
  done

  _install_file "$exec_path" 0755 _exec_source
  _install_file "$dropin" 0644 _sshd_source

  # Replace any earlier entry for the same key so rerunning enroll (for example
  # after changing the allowed addresses) leaves exactly one line.
  line="from=\"$from_addrs\",restrict,command=\"$EXEC_PATH\" $pubkey"
  _rewrite_keys "$(_key_blob "$pubkey")" "$line"

  _verify
  _reload_sshd
  _committed
  printf 'agent-root: enrolled %s; root login allowed only from %s with the forced command %s\n' \
    "$host_name" "$from_addrs" "$EXEC_PATH"
  _print_host_keys
}

# The client otherwise trusts the host key it sees on first connection. Print
# this host's keys under the client's alias so the operator can pin them.
_print_host_keys() {
  local pub found=0

  for pub in "$target_root"/etc/ssh/ssh_host_*_key.pub; do
    [[ -f "$pub" ]] || continue
    if ((found == 0)); then
      printf 'agent-root: to pin this host key, add these lines to the client'\''s agent-root known_hosts file:\n'
      found=1
    fi
    awk -v alias="agent-root-$host_name" '{ print alias, $1, $2 }' "$pub"
  done
}

_enroll
