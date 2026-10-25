# Test Harness

`test/run` is the local and CI entrypoint. It runs the suites in a fixed order
so a failure report reads the same everywhere.

## Suite scope

- `install-test` covers the generated checkout installer: the direct wrapper
  and piped curl bootstrap, idempotent reinstall, `BIN_DIR` placement, refusal
  to replace a non-symlink destination, missing command and library sources,
  and a working published command.
- `agent-root-client-test` covers usage errors, host-name and host-config
  validation (including shell text in values), key creation and permissions,
  argument quoting, the pinned ssh options, scripts on standard input, status
  propagation, `check`, `list`, config-directory resolution, and running
  through a symlink. A fake `ssh` records its arguments and plays the target.
- `agent-root-exec-test` covers the forced command: running commands and
  scripts, what it logs and where, the key fingerprint, splitting long
  entries, quoting control characters, bounded entries for many-line scripts,
  refusing oversized scripts, the minimal environment, closed standard input,
  spool cleanup, and refusing requests it cannot log.
- `agent-root-target-test` runs the generated enroll and revoke scripts against
  a relocated target tree with fake `sshd` and `systemctl`: installed files
  and modes, root's own keys left alone, idempotence, multiple clients,
  unexpanded `from` patterns, sshd service detection, rollback for every
  verification failure, and revoking one key versus the last.
- `agent-root-sshd-test` is the end-to-end proof with a real, unprivileged
  OpenSSH server: the rendered drop-in passes `sshd -t`, gives root its
  settings only from enrolled addresses, and leaves other connections'
  settings unchanged. A copy matched on the test user then proves live that
  quoting, scripts, exit statuses, and the audit log work; that `ForceCommand`
  applies even without `command=`; that only agent-root's key file counts; and
  that a mismatched pinned host key or a non-matching `from` is refused.
  It runs only with `AGENT_ROOT_TEST_REAL_SSHD=1`.
- `lib/test.sh` owns the small assertion vocabulary and a guarded per-suite
  temporary root.

Run everything with:

```bash
test/run
AGENT_ROOT_TEST_REAL_SSHD=1 test/run
```

Local runs invoke ShellCheck when it is installed. Shared CI sets
`AGENT_ROOT_SKIP_SHELLCHECK=1` for the behavioral matrix because its separate
required inventory job performs the same pinned lint once. Both read the
`program` records in `.github/shellcheck-files.txt`, so the inventory is the
single list of shell programs to update when adding one.

Keep fixtures generic and public: documentation addresses such as `192.0.2.7`,
`.example` and `.invalid` names, and synthetic keys rather than real hosts or
credentials.
