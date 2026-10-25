# Target-side files

Everything here runs on an enrolled host, as root, from a script that
`agent-root enroll` or `agent-root revoke` prints. Those scripts are
self-contained because enrolled hosts need not have agent-root installed: the
client embeds these files verbatim. Only `bin/agent-root` is a public command;
file and function names here may change together.

- `agent-root-exec` is installed as `/usr/local/sbin/agent-root-exec` and is
  the forced command for every agent-root key. It logs each request, with the
  client address and key fingerprint, to the journal before running it in a
  minimal environment, and logs the exit status afterwards.
- `sshd-match.conf.in` renders `/etc/ssh/sshd_config.d/50-agent-root.conf`
  with the enrolled `from` list. Every setting inside its Match block must be
  one that `sshd -T` prints back verbatim, because enroll verifies each one.
- `common.sh` holds the shared target helpers: paths, file snapshots, atomic
  writes, rewriting `/etc/ssh/agent-root/authorized_keys`, and sshd reloads. Its
  EXIT trap restores every snapshot unless the action reached `_committed`,
  so a failed enrollment cannot leave a half-applied sshd configuration.
- `enroll.sh` and `revoke.sh` are the two actions. They are fragments, not
  programs: the generated header defines `host_name`, `pubkey`, `from_addrs`,
  and (for enroll) the functions that print the files to install.

Enroll asks sshd, not the files, whether the change is correct: `sshd -t` must
pass, root from each literal enrolled address must get every setting in the
drop-in's Match block (an earlier Match in another file could otherwise win),
only those settings may differ from before, and `sshd -T` for other users and
for root from a documentation address must be unchanged. The drop-in ends
with `Match all` because distributions include `sshd_config.d` at the top of
`sshd_config`; without it, later global settings would fall inside the
root-only block.
