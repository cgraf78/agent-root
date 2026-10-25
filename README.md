# agent-root

[![Tests](https://github.com/cgraf78/agent-root/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/cgraf78/agent-root/actions/workflows/test.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-MIT-67ac09)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-%3E%3D3.2%20%283.2%20not%20CI--tested%29-blue)](#requirements)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL%20%7C%20Termux-lightgrey)](#requirements)

`agent-root` gives an automation account, such as the one your AI coding agents
run as, audited root access to a host without `sudo`, a stored password, or an
open root terminal. Each host gets its own SSH key that root accepts only from
the addresses you list and only through a forced command that logs every
request to the host's journal before running it, and refuses to run anything
it cannot log.

```console
$ agent-root run web1 -- systemctl reload nginx
$ agent-root run web1 < fix-permissions.sh
$ journalctl -t agent-root -o cat
[4121] run from=127.0.0.1 key=SHA256:3k9…: systemctl reload nginx
[4121] exit status=0
```

Revoking access removes one line from agent-root's own `authorized_keys` file
on the host. It takes effect for the next connection and does not depend on
the client behaving well.

## Installation

Install with a checkout-backed curl bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/cgraf78/agent-root/main/install.sh | bash
```

This keeps a durable managed checkout under `$XDG_DATA_HOME` when that path is
absolute, or under `$HOME/.local/share` otherwise, and publishes a link to its
`agent-root` command. Git and Bash 3.2 or newer are required; CI tests only
newer Bash (see [Requirements](#requirements)).

To choose and manage the checkout yourself instead:

```bash
git clone https://github.com/cgraf78/agent-root.git
cd agent-root
bash install.sh
```

Keep that checkout in place: the installer publishes a symlink to
`bin/agent-root`, and the command reads its private files from the same
checkout. `PREFIX` defaults to `$HOME/.local`; set `BIN_DIR` to override only
the binary directory. The installer retargets an existing symlink but refuses
to replace a real file or directory. Dependency managers can instead expose
`bin/agent-root` directly. For example, a shdeps registry entry is:

```text
cgraf78/agent-root  github
```

Only the machine that runs commands needs agent-root installed. Enrolled hosts
need just Bash and OpenSSH; enrollment copies the one file they need.

## Setup

1. Describe the host in `~/.config/agent-root/hosts.d/HOST.conf`:

   ```ini
   # Where to connect, and which source addresses root accepts the key from.
   host=localhost
   from=127.0.0.1,::1
   ```

2. Create the host's key:

   ```bash
   agent-root keygen HOST
   ```

3. Generate the enrollment script, read it, and run it as root on the host:

   ```bash
   agent-root enroll HOST > enroll.sh
   less enroll.sh
   sudo bash enroll.sh        # or from any root shell on HOST
   ```

   Enrollment ends by printing the host's SSH keys as `known_hosts` lines.
   Add them to `~/.config/agent-root/known_hosts` to pin the host key;
   otherwise the client trusts whatever key it sees on first connection.

4. Confirm it works:

   ```bash
   agent-root check HOST
   ```

For the same machine, use `host=localhost` with `from=127.0.0.1,::1`. For
another machine, set `host` to its name (your `ssh_config`, including
`ProxyJump`, still applies) and `from` to the address its sshd sees for this
client.

When the target's sshd cannot see a distinguishing client address, as behind
NAT where every client arrives from one gateway (WSL2, containers, port
proxies), reach it through its own loopback instead. Set `host=localhost`,
`jump` to the target's ordinary SSH login, and `from=127.0.0.1,::1`:

```ini
host=localhost
jump=wsl-box
from=127.0.0.1,::1
```

The jump uses that account's own keys and `ssh_config`, so the root key works
only for someone who can already log in to the target as that account.

## Usage

```text
agent-root run HOST [--] COMMAND [ARG...]
agent-root run HOST < SCRIPT
agent-root check HOST
agent-root list
agent-root keygen HOST
agent-root enroll HOST > enroll.sh
agent-root revoke HOST > revoke.sh
```

- `run` passes each argument through as one word, so quoting works as it
  does locally. A command gets no standard input, because streamed content
  would not be logged. With no command it runs a script from standard input
  with Bash, logged in full and limited to 64 KiB; it refuses a terminal so a
  forgotten command does not hang. The exit
  status is the remote command's, or 255 for a connection failure.
- `check` runs `id -u` and passes only when the answer is `0`.
- `list` prints each configured host, its target, its `from` list, and whether
  its key exists.
- `enroll` and `revoke` print root scripts instead of acting, so you can review
  exactly what will change. Both are safe to run again.

To revoke, run the revoke script as root. It can travel over agent-root itself,
since the running session is not interrupted:

```bash
agent-root revoke HOST | agent-root run HOST
rm ~/.config/agent-root/keys/HOST ~/.config/agent-root/keys/HOST.pub
```

## Requirements

The client needs Bash 3.2 or newer (CI runs only newer Bash), OpenSSH's `ssh`,
and `ssh-keygen` for `keygen`.

An enrolled host needs Bash, `logger`, `sha256sum` or `shasum`, and an OpenSSH
server (with its `ssh-keygen`, used to log key fingerprints) whose
`sshd_config` includes `sshd_config.d/*.conf`, which current
Debian, Ubuntu, Fedora, and Arch packages do. Enrollment reloads `sshd.service`
or `ssh.service` through systemd when one is running.

## Configuration

`agent-root` reads `$AGENT_ROOT_CONFIG_DIR`, else
`$XDG_CONFIG_HOME/agent-root` when that path is absolute, else
`~/.config/agent-root`:

| Path | Purpose |
| --- | --- |
| `hosts.d/HOST.conf` | Host settings. Safe to track in Git. |
| `keys/HOST`, `keys/HOST.pub` | The host's key pair, mode `0600` in a `0700` directory. Never track these. |
| `known_hosts` | Host keys, under the alias `agent-root-HOST`: pinned from enroll's output, or accepted on first connection. A changed key is refused. |

Host files are parsed, not sourced. Each line is `KEY=VALUE`; `#` starts a
comment line. Unknown keys are errors.

| Key | Required | Purpose |
| --- | --- | --- |
| `host` | yes | Name or address to connect to. |
| `port` | no | SSH port, if not the default. |
| `jump` | no | Host to jump through (`ssh -J`), such as the target's ordinary SSH login. A name or `ssh_config` alias; set its user and port in `ssh_config`. |
| `from` | yes | Comma-separated source addresses or CIDR ranges allowed to use the key. At least one must be a literal address so enrollment can verify sshd's settings. |

| Variable | Purpose |
| --- | --- |
| `AGENT_ROOT_CONFIG_DIR` | Configuration directory override. |
| `AGENT_ROOT_CONNECT_TIMEOUT` | SSH connect timeout in seconds. Defaults to 10. |

## Security model

Enrollment installs four things on the host, each removed by `revoke` with the
last key:

- `/usr/local/sbin/agent-root-exec`, the forced command. Before running a
  request it logs the command text, or a script's size, SHA-256, and full
  content (scripts over 64 KiB are refused), with the client address and the
  key's fingerprint, to
  `authpriv` under the tag `agent-root`. Long entries are split rather than
  truncated, and control characters are quoted so a request cannot forge
  journal lines. If logging fails, it refuses the request. It runs the request
  with a minimal environment and closed standard input, and logs the exit
  status afterwards.
- `/etc/ssh/sshd_config.d/50-agent-root.conf`, a `Match User root Address
  FROM` block closed with `Match all`. For root from those addresses only, it
  sets `PermitRootLogin forced-commands-only` and `ForceCommand` to the
  wrapper. It also allows only public keys from agent-root's own key file,
  turns off CA certificates, principals files, and `AuthorizedKeysCommand`
  lookups, accepts only `LANG` from the client's environment, disables
  tunnels and all forwarding, and lets root past any global `AllowUsers`
  list.
- `/etc/ssh/agent-root/authorized_keys`, with one line per client:
  `from="FROM",restrict,command="..."` followed by the key. `restrict`
  disables port, agent, and X11 forwarding and terminals. Root's own
  `authorized_keys` is never edited and is not consulted for these
  connections.

Enrollment is transactional. Before reloading sshd it asks sshd itself
(`sshd -t` and `sshd -T -C`) to confirm three things: the configuration is
valid; root from each enrolled literal address gets every setting above, and
only those settings change; and the settings for other users, and for root
from anywhere else, are unchanged. Any failure restores the previous files.

What this does not do: commands run as full root, so the key is root-equivalent
for whoever can read it. Protect `keys/` like any root credential, prefer one
key per host and client so revocation is narrow, and review the journal. The
log records what was requested; a root command can still erase local logs, and
a key holder who floods the journal past its rate limit (`RateLimitBurst`) can
get entries suppressed while `logger` still reports success. Forward the
journal off the host if you need tamper-evident records. `from` patterns are
matched by sshd against the client address; keep `UseDNS` off (the OpenSSH
default) so they never match host names.

## Development

Run the complete suite, including ShellCheck when it is installed, with:

```bash
test/run
```

Add `AGENT_ROOT_TEST_REAL_SSHD=1` to also run the end-to-end suite against a
real, unprivileged sshd on a loopback port. See
[`test/README.md`](test/README.md) for the test architecture,
[`bin/README.md`](bin/README.md) for the command's boundaries, and
[`lib/agent-root/README.md`](lib/agent-root/README.md) for the target-side
files.

## License

MIT. See [`LICENSE`](LICENSE).
