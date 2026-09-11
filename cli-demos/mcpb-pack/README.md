# MCPB packaging demo

Packaging the reference MCP servers as ModelKits.

`./package-mcp-servers.sh` turns the seven reference servers from
[modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers)
into ModelKits an agent definition can pull as `type: mcp` modules with
`source.modelkit`.

```bash
# All seven, into the local kitops store
./package-mcp-servers.sh

# One server, keeping the work directory to inspect the staged bundle
./package-mcp-servers.sh --out /tmp/mcp --keep time
```

| Flag | Default | What it does |
|------|---------|--------------|
| `--ref <git-ref>` | a pinned upstream tag | Which upstream commit or tag to build from |
| `--out <dir>` | a temp dir, removed on exit | Work directory: clone, staging, packed kits |
| `--tag-prefix <prefix>` | `mcp` | Tag prefix, so kits are tagged `mcp/<server>:<version>` |
| `--version <v>` | each server's own version | Overrides the version for every server packaged |
| `--carry mcpb\|code` | `mcpb` | How the kit carries the bundle — see [Carriage](#how-the-bundle-is-carried) |
| `--push` | off | `kit push` each kit after packing |
| `--keep` | off | Keep the work directory |

With no server arguments it packages all seven: `filesystem`, `memory`,
`sequentialthinking`, `everything`, `git`, `fetch`, `time`. The version comes
from each server's own `package.json` or `pyproject.toml`, so the four
TypeScript servers get the monorepo's calendar version and the three Python
ones their independent `0.6.x`.

## What comes out

Per server, one ModelKit carrying one MCPB bundle:

```
mcp/time:0.6.2
├── Kitfile          # code: [manifest.json, lib/]
├── README.md        # the upstream server README, as docs:
├── manifest.json    # the MCPB manifest
└── lib/             # the vendored dependency closure
```

The bundle is self-contained. Nothing is fetched at run time, and nothing on
the guest is expected beyond the interpreter: `node` for the TypeScript
servers, `python3` for the Python ones (plus a `git` binary for the `git`
server, which the rootfs already has).

## How the bundle is carried

There are two ways to put an MCPB bundle in a ModelKit.

**`--carry mcpb` (the default).** A single `<server>.mcpb` under `mcpServers:`,
per JZ-SPEC-MCPB-PKG-001 §7.1. This is the shape the spec describes and what the
`kit` CLI emits. Reading it back needs kitops v1.15.0 or later, which is the
first release whose unpack planner emits a step for an `mcpServers` entry; on an
older kitops the layer is skipped at warn level and `agentdef.Pull` hands back a
directory with no bundle in it.

**`--carry code`.** The bundle's contents go in at the kit root —
`manifest.json` beside `dist/` and `node_modules/`, or beside `lib/` — listed
under `code:`. `LoadMCPBFromDir` checks for a root `manifest.json` first and
returns immediately, so nothing is zipped. Same shape as agentguard's
`docs/demos/cosign-verification/mcp`. Use it when the AgentGuard that will
consume the kit was built against a kitops older than v1.15.0.

Either way the bundle stays under the host's extraction limits
(agentguard's [`pkg/agentdef/mcpb.go`](https://github.com/jozu-ai/agentguard/blob/main/pkg/agentdef/mcpb.go)): these servers run 1000 to 2600 zip entries once their
dependency trees are vendored, against a ceiling of 50000 entries and 2 GB
extracted. The script warns per bundle if one ever exceeds them.

## One server per ModelKit

`agentdef.LoadMCPBFromDir` takes the **first** `.mcpb` it finds in the unpacked
kit and unpacks it in place. A kit carrying two bundles would have one of them
picked arbitrarily and the other silently ignored, so the script never puts
more than one server in a kit. Seven servers, seven kits, seven module entries
in the agent definition.

## Runtime constraints the packaging works around

**No `uv` in the guest.** `server.type: uv` passes manifest validation but the
rootfs has no `uv` binary, so a `uv`-typed server would fail at spawn. Python
servers are packaged as `type: python` with their entire dependency closure
vendored under `lib/` and reached through `PYTHONPATH=${__dirname}/lib`.

**The bundle is read-only.** It is installed root:mcp 0750 and run as a
different uid, so a server that writes beside its own code fails. Caches are
fine — the launcher redirects `UV_*`, `PYTHONPYCACHEPREFIX` and
`npm_config_cache` under a tmpfs home — but data is not. `memory` is the one
server this bites: its `MEMORY_FILE_PATH` defaults to a file next to `dist/`.
It cannot simply be pointed at the tmpfs home either, because `${HOME}` is not
a placeholder the host resolves — `ResolveCommand`'s `runtimePlaceholders`
allows `${workspace}` and nothing else, and any other unsubstituted `${…}` is a
hard error. So `memory` declares a required `memory_file_path` user_config and
the agent definition points it into the workspace.

**You build on macOS/arm64, the bundle runs on linux/arm64.** Pure JS and pure
Python cross fine. Python's dependency closure does not: `pydantic-core`,
`rpds`, `cryptography` and `cffi` ship compiled extension modules with no
pure-Python fallback. The script therefore resolves wheels for the guest
explicitly — `--platform manylinux_2_28_aarch64 --python-version 3.13 --abi
cp313 --only-binary=:all:` — rather than for the build host, and then checks
every `*.so` / `*.dylib` / `*.node` in the staged bundle with `file(1)`.
Anything that is not an aarch64 ELF shared object fails that server and the
run continues with the others. **If the guest's `python3` minor version
changes, `GUEST_PY_VERSION` and `GUEST_PY_ABI` at the top of the script must
change with it** — cp313 extension modules will not load on any other CPython.

## Referencing a packaged server

```yaml
apiVersion: agentguard.jozu.dev/v1
kind: AgentDefinition
metadata:
  name: research-agent
spec:
  framework: claude-code
  includes:
    - name: filesystem
      type: mcp
      source:
        modelkit: mcp/filesystem:2026.8.31
      config:
        allowed_directory: ${workspace}

    - name: memory
      type: mcp
      source:
        modelkit: mcp/memory:2026.8.31
      config:
        memory_file_path: ${workspace}/.mcp-memory.json

    - name: time
      type: mcp
      source:
        modelkit: mcp/time:0.6.2
```

`config:` supplies the manifest's `user_config` values. Keys are matched by
name and substituted into `mcp_config` wherever `${user_config.<key>}` appears.
Two servers declare one, both required: `filesystem`'s `allowed_directory`, the
single directory the server will read or write, and `memory`'s
`memory_file_path`. `${workspace}` is left alone by the host and resolved to the
guest's workspace path at init, so it is the value to build both from. Omitting
a required key is not silent — `ResolveCommand` fails the run with
`unresolved placeholders: ${user_config.…}`.

`git` deliberately declares no `user_config`. Upstream takes an optional
`--repository` default, but `mcp_config.args` is a fixed list and an
unsubstituted `${user_config.*}` is a hard error in `ResolveCommand`, so an
optional value cannot be referenced from args at all. Every tool the server
exposes takes its repository path per call, so omitting the flag costs a
default, not a capability.

The script prints this snippet for whatever it just packaged, tags and all.

## Pointing it at a registry

The default `--tag-prefix mcp` produces `mcp/<server>:<version>`, a local ref
that resolves from the kitops store with no network call. Give the prefix a
registry host and the same tags become pushable:

```bash
./package-mcp-servers.sh --tag-prefix jozu.ml/myorg --push
# -> jozu.ml/myorg/filesystem:2026.8.31, ...
```

Remember that artifact admission applies to the result. By default only
`jozu.ml` is trusted; local refs need an `ArtifactPolicy` that matches
`artifact.registry == "localhost"`, and are blocked outright when cosign keys
are configured without one. See the agent-definition section of agentguard's
[README](https://github.com/jozu-ai/agentguard/blob/main/README.md#agent-definitions).
