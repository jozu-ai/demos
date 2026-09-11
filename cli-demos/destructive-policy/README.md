# Destructive operations policy

A Gerty `ToolPolicy` that refuses destructive tool calls. Two policies in one
file, both `Enforce`, so a match denies the call and returns the rule's message
to the agent. Nothing here elicits: the point is refusal, not confirmation.

```bash
kit pack . -t destructive-policy:1.0.0
agentguard policy add destructive-policy:1.0.0
```

## What it refuses

`01-destructive-shell-commands` matches the shell tools of the supported
frameworks plus the conventional MCP shell server names.

| Rule | Refuses | Deliberately allows |
|---|---|---|
| `no-recursive-forced-delete` | `rm -rf`, `-rfv`, `-Rf`, `--recursive --force`, flags apart or reordered | `rm -r`, `rm -f`, `rm file` |
| `no-delete-at-filesystem-root` | `rm -rf /`, anything with `--no-preserve-root` | any path below the root |
| `no-raw-device-writes` | `mkfs*`, `wipefs`, `blkdiscard`, `shred`, `fdisk`, `parted`, `sgdisk`, `dd of=/dev/…` | `dd` between regular files |
| `no-sql-drop-or-truncate` | `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE TABLE`, any case | a column named `drop_log` |
| `no-git-history-destruction` | `push --force`, `push -f`, `reset --hard`, `clean -fd`, `branch -D` | `--force-with-lease`, `reset --soft`, `branch -d`, `clean -n` |
| `no-infrastructure-teardown` | `terraform destroy`, `kubectl delete`, `aws s3 rb/rm` with `--force` or `--recursive` | `terraform plan`, `kubectl get` |

`02-destructive-file-tools` refuses deletion-only MCP tools by name
(`delete_file`, `remove_directory` and similar), because there is no
non-destructive way to call them.

`--force-with-lease` is allowed on purpose. It still rewrites remote history,
but it refuses to overwrite commits the local clone has not seen, so it cannot
silently discard a collaborator's work. Add it to the refusal if that is not
the tradeoff you want.

## Limits worth knowing

These are pattern rules, not parsers. A command assembled from shell variables
slips through, and the shell tool names are the supported frameworks plus
conventional MCP names, so a framework with a differently named shell tool
needs adding to `match.tool.names`.

For MCP servers, add `spec.match.tool.servers` with the declared module name
from the agent definition to scope a rule to one module. Server and tool names
AND together, each ORing within its own list, so a rule naming both binds one
server's tools and cannot catch a same-named tool on a different server.

## Adapting it

`assert` holds what is **allowed**, so a refusal reads as a chain of negations
and an unconditional refusal reads as `assert: "false"`. Every argument access
is guarded with `!("arg" in tool.arguments) || …`, because reading an argument
the tool did not send is a CEL error, which denies: an unguarded rule refuses
unrelated tools rather than ignoring them. No rule references `request.*`, since
the agent hook posts only the tool call.

Regexes are RE2, which has no lookahead, so exemptions are written as extra
clauses rather than `(?!…)`.
