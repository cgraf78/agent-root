# Public command

`bin/agent-root` is the repository's only public executable. The stable
command surface is:

```text
agent-root run HOST [--] COMMAND [ARG...]
agent-root run HOST < SCRIPT
agent-root check HOST
agent-root list
agent-root keygen HOST
agent-root enroll HOST > enroll.sh
agent-root revoke HOST > revoke.sh
```

The host config keys, file layout, and security model are documented in the
repository [`README`](../README.md).

Dependency managers such as shdeps normally expose this file through a symlink
in `~/.local/bin`. The launcher resolves every symlink hop without GNU-only
`readlink -f` and reads `lib/agent-root` from that same checkout, so the
target-side files that `enroll` embeds always match the client that generated
them. Consumers should expose `bin/agent-root` directly instead of wrapping it,
so argument quoting and exit statuses stay the same everywhere.

Keep this launcher compatible with Bash 3.2: agents may call it from a stock
macOS shell.
