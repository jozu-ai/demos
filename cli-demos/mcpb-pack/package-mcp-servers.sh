#!/usr/bin/env bash
#
# Package the reference MCP servers from modelcontextprotocol/servers as
# ModelKits that AgentGuard can consume from an agent definition as
#
#     - name: filesystem
#       type: mcp
#       source:
#         modelkit: mcp/filesystem:2026.8.31
#
# For each server the script produces one self-contained MCPB bundle
# (manifest.json + everything the server needs at runtime) and wraps it in a
# ModelKit whose Kitfile carries it under `mcpServers:`.
#
# ONE SERVER PER MODELKIT. agentdef.LoadMCPBFromDir takes the *first* .mcpb it
# finds in the unpacked kit and unpacks it in place, so a kit carrying two
# bundles would have one of them picked arbitrarily. Seven servers, seven kits.
#
# What the bundles must satisfy, and why the build looks the way it does:
#
#   * The guest has Node 22 and python3, but no `uv`. Python servers are
#     therefore packaged as `type: python` with every dependency vendored into
#     the bundle and reached through PYTHONPATH, never as `type: uv`.
#   * You build on macOS/arm64; the bundle runs on Debian trixie / linux-arm64
#     (python3 3.13, glibc 2.41). Python wheels are resolved for that target
#     explicitly rather than for the build host.
#   * The installed bundle is read-only to the process that runs it, so nothing
#     may write beside its own code. That is why `memory` is pointed at the
#     tmpfs home instead of its default file next to dist/.
#
set -euo pipefail

# Upstream pin. Tag 2026.8.31, resolved 2026-09-08 to commit
# a40bc270fb5ece62673f8a1196f57116d885c5eb. A tag rather than main so two runs
# of this script a month apart produce the same bundles.
UPSTREAM_REPO="https://github.com/modelcontextprotocol/servers.git"
UPSTREAM_REF="2026.8.31"

# The guest runtime the bundles have to load on. Used to resolve Python wheels
# for the target instead of the build host, and to tell a correctly
# cross-built native module from one that leaked in from macOS.
GUEST_PY_VERSION="3.13"
GUEST_PY_ABI="cp313"
GUEST_PLATFORMS=(manylinux2014_aarch64 manylinux_2_28_aarch64)
GUEST_ELF_MARKER="ELF 64-bit LSB shared object, ARM aarch64"

# agentdef.LoadMCPBFromDir refuses a .mcpb with more entries than this
# (agentguard's pkg/agentdef/mcpb.go: maxExtractEntries). Bundles over it still pack, but
# the host rejects them at `agentguard run` time, so say so loudly. The
# reference servers run 1000-2600 entries once their dependencies are
# vendored, well inside this.
MCPB_MAX_ENTRIES=50000

# How the bundle is carried in the ModelKit. Two shapes, and only one of them
# is consumable by the AgentGuard in this repo today:
#
#   mcpb  A single <server>.mcpb under `mcpServers:`, per JZ-SPEC-MCPB-PKG-001
#         §7.1, which is what the `kit` CLI emits and what the spec describes.
#         This is the default. It needs kitops v1.15.0 or later on the host
#         side: that is the first release whose unpack planner emits a step for
#         an mcpServers entry, so the bundle layer reaches agentdef.Pull rather
#         than being skipped.
#
#   code  Bundle contents unpacked at the kit root: manifest.json beside dist/,
#         node_modules/ or lib/, listed under `code:`. LoadMCPBFromDir finds the
#         manifest directly without opening a zip. Same shape as
#         agentguard's docs/demos/cosign-verification/mcp. Use it against an AgentGuard
#         built against kitops older than v1.15.0, where the layer is dropped.
CARRY=mcpb

ALL_SERVERS=(filesystem memory sequentialthinking everything git fetch time)

OUT_DIR=""
TAG_PREFIX="mcp"
VERSION_OVERRIDE=""
DO_PUSH=0
KEEP=0
SERVERS=()

usage() {
    cat <<'EOF'
Usage: ./package-mcp-servers.sh [options] [server ...]

  --ref <git-ref>       upstream modelcontextprotocol/servers ref (default: pinned tag)
  --out <dir>           work directory (default: a temp dir, removed on exit)
  --tag-prefix <prefix> ModelKit tag prefix (default: mcp, i.e. mcp/<server>:<version>)
  --version <v>         override the version for every packaged server
  --carry mcpb|code     how the kit carries the bundle (default: mcpb, the
                        shape the spec describes; code targets an AgentGuard
                        built against kitops older than v1.15.0)
  --push                kit push each kit after packing
  --keep                keep the work directory
  -h, --help            this message

With no server arguments all seven are packaged:
  filesystem memory sequentialthinking everything git fetch time
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ref)        UPSTREAM_REF="$2"; shift 2 ;;
        --out)        OUT_DIR="$2"; shift 2 ;;
        --tag-prefix) TAG_PREFIX="$2"; shift 2 ;;
        --version)    VERSION_OVERRIDE="$2"; shift 2 ;;
        --carry)      CARRY="$2"; shift 2 ;;
        --push)       DO_PUSH=1; shift ;;
        --keep)       KEEP=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)            SERVERS+=("$1"); shift ;;
    esac
done

if [[ ${#SERVERS[@]} -eq 0 ]]; then
    SERVERS=("${ALL_SERVERS[@]}")
fi

for s in "${SERVERS[@]}"; do
    found=0
    for known in "${ALL_SERVERS[@]}"; do
        [[ "$s" == "$known" ]] && found=1
    done
    if [[ $found -eq 0 ]]; then
        echo "unknown server: $s (known: ${ALL_SERVERS[*]})" >&2
        exit 2
    fi
done

if [[ "$CARRY" != "code" && "$CARRY" != "mcpb" ]]; then
    echo "--carry must be 'code' or 'mcpb', got: $CARRY" >&2
    exit 2
fi

for tool in git npm node python3 kit; do
    command -v "$tool" >/dev/null 2>&1 || { echo "required tool not on PATH: $tool" >&2; exit 2; }
done

if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/package-mcp-servers.XXXXXX")"
    [[ $KEEP -eq 1 ]] || trap 'rm -rf "$OUT_DIR"' EXIT
fi
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

CLONE_DIR="$OUT_DIR/servers"
KITS_DIR="$OUT_DIR/kits"
mkdir -p "$KITS_DIR"

log()  { printf '  %s\n' "$*"; }
warn() { printf '  WARNING: %s\n' "$*" >&2; }
fail() { printf '  FAILED: %s\n' "$*" >&2; }

# ── upstream ──────────────────────────────────────────────────────────────────

fetch_upstream() {
    if [[ -d "$CLONE_DIR/.git" ]]; then
        log "reusing clone at $CLONE_DIR"
        return
    fi
    echo "==> Cloning $UPSTREAM_REPO at $UPSTREAM_REF"
    # One shallow clone for all seven servers. --branch takes a tag too.
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$CLONE_DIR"
    log "commit $(git -C "$CLONE_DIR" rev-parse HEAD)"
}

server_kind() {
    local dir="$CLONE_DIR/src/$1"
    if   [[ -f "$dir/package.json"   ]]; then echo node
    elif [[ -f "$dir/pyproject.toml" ]]; then echo python
    else echo unknown
    fi
}

server_version() {
    local server="$1" kind="$2" dir="$CLONE_DIR/src/$1"
    if [[ -n "$VERSION_OVERRIDE" ]]; then
        echo "$VERSION_OVERRIDE"
        return
    fi
    case "$kind" in
        node)   node -p "require('$dir/package.json').version" ;;
        # First `version = "..."` in pyproject.toml is the [project] one in
        # every server here; avoids depending on a TOML parser.
        python) sed -n 's/^version[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "$dir/pyproject.toml" | head -1 ;;
    esac
}

# ── staging ───────────────────────────────────────────────────────────────────

# Node: build with dev deps in the checkout (the per-server tsconfig extends the
# repo root one, so it has to build in place), then resolve production-only
# dependencies in a scratch directory. Resolving them in the checkout would give
# us the monorepo's hoisted workspace tree, which carries every server's deps.
stage_node() {
    local server="$1" stage="$2"
    local src="$CLONE_DIR/src/$server"
    local prod="$OUT_DIR/prod/$server"

    log "npm install (with dev deps, for tsc)"
    (cd "$src" && npm install --no-audit --no-fund --loglevel=error >/dev/null)
    log "npm run build"
    (cd "$src" && npm run build >/dev/null)
    [[ -d "$src/dist" ]] || { fail "$server: build produced no dist/"; return 1; }

    log "resolving production dependencies"
    rm -rf "$prod"
    mkdir -p "$prod"
    # Drop scripts so npm's `prepare` does not try to rebuild here, and drop
    # devDependencies so nothing pulls a toolchain into the bundle.
    node -e '
        const fs = require("fs");
        const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        delete p.scripts;
        delete p.devDependencies;
        fs.writeFileSync(process.argv[2], JSON.stringify(p, null, 2));
    ' "$src/package.json" "$prod/package.json"
    # --ignore-scripts: no dependency install hook runs on the build host, and
    # nothing gets a chance to compile a macOS native module into the bundle.
    (cd "$prod" && npm install --omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error >/dev/null)

    cp -R "$src/dist" "$stage/dist"
    cp "$prod/package.json" "$stage/package.json"
    [[ -d "$prod/node_modules" ]] && cp -R "$prod/node_modules" "$stage/node_modules"
    return 0
}

# Python: no uv in the guest, so the server and its whole dependency closure are
# vendored under lib/ and reached with PYTHONPATH. Wheels are resolved for the
# guest interpreter, not this machine's.
stage_python() {
    local server="$1" stage="$2"
    local src="$CLONE_DIR/src/$server"
    local wheels="$OUT_DIR/wheels/$server"

    rm -rf "$wheels"
    mkdir -p "$wheels" "$stage/lib"

    # The server itself is pure Python but built by hatchling, so it cannot come
    # from --only-binary; build its wheel first and install that.
    log "building wheel for $server"
    python3 -m pip wheel --no-deps --wheel-dir "$wheels" "$src" \
        --quiet --disable-pip-version-check

    local platform_args=()
    for p in "${GUEST_PLATFORMS[@]}"; do platform_args+=(--platform "$p"); done

    log "installing dependency closure for linux/$GUEST_PY_ABI"
    python3 -m pip install --target "$stage/lib" \
        "${platform_args[@]}" \
        --python-version "$GUEST_PY_VERSION" --abi "$GUEST_PY_ABI" --implementation cp \
        --only-binary=:all: --no-compile --upgrade \
        --quiet --disable-pip-version-check --no-warn-conflicts \
        "$wheels"/*.whl

    # Console scripts carry this machine's python shebang and nothing runs them;
    # __pycache__ would be stale bytecode for the wrong interpreter. .dist-info
    # stays: importlib.metadata reads it at runtime.
    rm -rf "$stage/lib/bin"
    find "$stage/lib" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
    return 0
}

# ── manifests ─────────────────────────────────────────────────────────────────

# One entry per server. Each writes a complete MCPB 0.3 manifest to stdout.
write_manifest() {
    local server="$1" version="$2"
    local author='"author": { "name": "Model Context Protocol", "url": "https://github.com/modelcontextprotocol/servers" }'

    case "$server" in
    filesystem)
        cat <<EOF
{
  "manifest_version": "0.3",
  "name": "filesystem",
  "version": "$version",
  "description": "Read, write and search files under one directory the operator names",
  $author,
  "user_config": {
    "allowed_directory": {
      "type": "directory",
      "title": "Allowed directory",
      "description": "The one directory this server may read or write. Everything outside it is refused by the server itself. Usually \${workspace}.",
      "required": true
    }
  },
  "server": {
    "type": "node",
    "entry_point": "dist/index.js",
    "mcp_config": {
      "command": "node",
      "args": ["\${__dirname}/dist/index.js", "\${user_config.allowed_directory}"]
    }
  }
}
EOF
        ;;
    memory)
        # The server writes its graph to MEMORY_FILE_PATH, which defaults to a
        # file beside dist/ -- unwritable, since the installed bundle is
        # read-only. It has to be pointed somewhere writable, and ${HOME} is not
        # an option: ResolveCommand's runtimePlaceholders allows ${workspace}
        # and nothing else, so a manifest naming ${HOME} fails host-side
        # validation before the guest ever sees it. Hence a required
        # user_config the agent definition points into the workspace.
        cat <<EOF
{
  "manifest_version": "0.3",
  "name": "memory",
  "version": "$version",
  "description": "Knowledge-graph memory over a JSON file the operator names",
  $author,
  "user_config": {
    "memory_file_path": {
      "type": "file",
      "title": "Memory file",
      "description": "Where the knowledge graph is written. Must be writable at run time, so somewhere under \${workspace}; the installed bundle itself is read-only.",
      "required": true
    }
  },
  "server": {
    "type": "node",
    "entry_point": "dist/index.js",
    "mcp_config": {
      "command": "node",
      "args": ["\${__dirname}/dist/index.js"],
      "env": {
        "MEMORY_FILE_PATH": "\${user_config.memory_file_path}"
      }
    }
  }
}
EOF
        ;;
    sequentialthinking)
        cat <<EOF
{
  "manifest_version": "0.3",
  "name": "sequentialthinking",
  "version": "$version",
  "description": "Structured step-by-step reasoning as a tool; keeps no state outside the process",
  $author,
  "server": {
    "type": "node",
    "entry_point": "dist/index.js",
    "mcp_config": {
      "command": "node",
      "args": ["\${__dirname}/dist/index.js"]
    }
  }
}
EOF
        ;;
    everything)
        cat <<EOF
{
  "manifest_version": "0.3",
  "name": "everything",
  "version": "$version",
  "description": "Reference server exercising every MCP feature; useful for testing a client",
  $author,
  "server": {
    "type": "node",
    "entry_point": "dist/index.js",
    "mcp_config": {
      "command": "node",
      "args": ["\${__dirname}/dist/index.js", "stdio"]
    }
  }
}
EOF
        ;;
    git)
        # No --repository flag. It is optional upstream, but mcp_config.args is a
        # fixed list and an unset \${user_config.*} placeholder is a hard error in
        # ResolveCommand, so an optional value cannot be referenced from args.
        # Every tool this server exposes takes repo_path per call, so omitting the
        # flag costs a default, not a capability.
        cat <<EOF
{
  "manifest_version": "0.3",
  "name": "git",
  "version": "$version",
  "description": "Read, search and manipulate Git repositories; each tool call names its own repository path",
  $author,
  "server": {
    "type": "python",
    "entry_point": "lib/mcp_server_git/__main__.py",
    "mcp_config": {
      "command": "python3",
      "args": ["-m", "mcp_server_git"],
      "env": {
        "PYTHONPATH": "\${__dirname}/lib"
      }
    }
  }
}
EOF
        ;;
    fetch)
        cat <<EOF
{
  "manifest_version": "0.3",
  "name": "fetch",
  "version": "$version",
  "description": "Fetch a URL and convert the response to markdown for the model to read",
  $author,
  "server": {
    "type": "python",
    "entry_point": "lib/mcp_server_fetch/__main__.py",
    "mcp_config": {
      "command": "python3",
      "args": ["-m", "mcp_server_fetch"],
      "env": {
        "PYTHONPATH": "\${__dirname}/lib"
      }
    }
  }
}
EOF
        ;;
    time)
        cat <<EOF
{
  "manifest_version": "0.3",
  "name": "time",
  "version": "$version",
  "description": "Current time and timezone conversion",
  $author,
  "server": {
    "type": "python",
    "entry_point": "lib/mcp_server_time/__main__.py",
    "mcp_config": {
      "command": "python3",
      "args": ["-m", "mcp_server_time"],
      "env": {
        "PYTHONPATH": "\${__dirname}/lib"
      }
    }
  }
}
EOF
        ;;
    esac
}

# Which servers declare user_config, for the snippet printed at the end.
server_config_snippet() {
    # shellcheck disable=SC2016  # ${workspace} is a guest-side placeholder, not a shell variable
    case "$1" in
        filesystem) printf '        config:\n          allowed_directory: ${workspace}\n' ;;
        memory)     printf '        config:\n          memory_file_path: ${workspace}/.mcp-memory.json\n' ;;
        *)          : ;;
    esac
}

# ── checks ────────────────────────────────────────────────────────────────────

# A bundle built here runs on linux/arm64. Anything Mach-O, or ELF for another
# architecture, is a build that reached for the host toolchain and will not
# load in the guest.
check_portability() {
    local server="$1" stage="$2" bad=0 native=0
    while IFS= read -r f; do
        native=$((native + 1))
        local desc
        desc="$(file -b "$f")"
        case "$desc" in
            *"$GUEST_ELF_MARKER"*) ;;
            *) fail "$server: non-portable native artifact ${f#"$stage"/}: $desc"; bad=1 ;;
        esac
    done < <(find "$stage" \( -name '*.node' -o -name '*.so' -o -name '*.dylib' \) -type f)

    if [[ $bad -eq 1 ]]; then
        return 1
    fi
    # Reported rather than silent: pydantic-core, rpds and cryptography have no
    # pure-Python build, so a Python bundle always carries some. They are only
    # correct because pip resolved them for the guest ABI, which makes them
    # worth naming in the log when the guest interpreter changes.
    if [[ $native -gt 0 ]]; then
        log "$native native module(s), all $GUEST_PY_ABI/aarch64 ELF"
    fi
    return 0
}

# Counted on the packed bundle, not the staging directory: mcpb pack drops
# files of its own, and the number the host guard compares against is the zip's.
check_entry_count() {
    local server="$1" bundle="$2" n
    n="$(python3 -c 'import sys, zipfile; print(len(zipfile.ZipFile(sys.argv[1]).infolist()))' "$bundle")"
    if [[ "$n" -gt "$MCPB_MAX_ENTRIES" ]]; then
        warn "$server: $n zip entries exceeds maxExtractEntries=$MCPB_MAX_ENTRIES in agentguard's pkg/agentdef/mcpb.go; the host refuses to unpack this kit at run time"
    fi
    echo "$n"
}

# ── packing ───────────────────────────────────────────────────────────────────

pack_bundle() {
    local stage="$1" bundle="$2"
    if command -v mcpb >/dev/null 2>&1; then
        mcpb pack "$stage" "$bundle" >/dev/null
    else
        # mcpb pack is just a zip with manifest.json at the root.
        (cd "$stage" && zip -qr "$bundle" .)
    fi
}

write_kitfile() {
    local server="$1" version="$2" description="$3" kitdir="$4" has_readme="$5"
    {
        cat <<EOF
manifestVersion: "1.0.0"
package:
  name: mcp-$server
  version: "$version"
  description: "$description"
  authors:
    - Model Context Protocol
EOF
        if [[ "$CARRY" == "mcpb" ]]; then
            cat <<EOF
mcpServers:
  - name: $server
    path: $server.mcpb
    description: "$description"
EOF
        else
            # Whatever the stage put at the kit root, minus the README, which is
            # listed under docs: below.
            echo "code:"
            for entry in "$kitdir"/*; do
                local base
                base="$(basename "$entry")"
                case "$base" in
                    Kitfile|README.md) continue ;;
                esac
                if [[ -d "$entry" ]]; then
                    echo "  - path: $base/"
                else
                    echo "  - path: $base"
                fi
            done
        fi
        if [[ "$has_readme" == "yes" ]]; then
            cat <<EOF
docs:
  - path: README.md
    description: "Upstream README for $server at $UPSTREAM_REF"
EOF
        fi
    } > "$kitdir/Kitfile"
}

# ── main ──────────────────────────────────────────────────────────────────────

fetch_upstream

SUMMARY=()
FAILURES=()

package_one() {
    local server="$1"
    local kind version stage kitdir bundle entries size tag

    kind="$(server_kind "$server")"
    if [[ "$kind" == "unknown" ]]; then
        fail "$server: no package.json or pyproject.toml in src/$server"
        return 1
    fi
    version="$(server_version "$server" "$kind")"
    if [[ -z "$version" ]]; then
        fail "$server: could not determine a version"
        return 1
    fi
    tag="$TAG_PREFIX/$server:$version"

    stage="$OUT_DIR/stage/$server"
    kitdir="$KITS_DIR/$server"
    rm -rf "$stage" "$kitdir"
    mkdir -p "$stage" "$kitdir"

    echo "==> $server ($kind $version)"
    case "$kind" in
        node)   stage_node   "$server" "$stage" || return 1 ;;
        python) stage_python "$server" "$stage" || return 1 ;;
    esac

    write_manifest "$server" "$version" > "$stage/manifest.json"
    if command -v mcpb >/dev/null 2>&1; then
        mcpb validate "$stage/manifest.json" >/dev/null || { fail "$server: manifest failed mcpb validate"; return 1; }
    fi

    check_portability "$server" "$stage" || return 1

    if [[ "$CARRY" == "mcpb" ]]; then
        bundle="$kitdir/$server.mcpb"
        pack_bundle "$stage" "$bundle"
        size="$(du -h "$bundle" | cut -f1 | tr -d ' ')"
        entries="$(check_entry_count "$server" "$bundle")"
        log "packed $bundle ($size, $entries entries)"
    else
        cp -R "$stage/." "$kitdir/"
        size="$(du -sh "$stage" | cut -f1 | tr -d ' ')"
        entries="$(find "$stage" -type f | wc -l | tr -d ' ')"
        log "staged $entries files into the kit ($size)"
    fi

    local has_readme=no
    if [[ -f "$CLONE_DIR/src/$server/README.md" ]]; then
        cp "$CLONE_DIR/src/$server/README.md" "$kitdir/README.md"
        has_readme=yes
    fi
    write_kitfile "$server" "$version" \
        "MCP reference server '$server' from modelcontextprotocol/servers@$UPSTREAM_REF" \
        "$kitdir" "$has_readme"

    kit pack "$kitdir" -t "$tag" >/dev/null || { fail "$server: kit pack"; return 1; }
    log "kit pack $tag"

    if [[ $DO_PUSH -eq 1 ]]; then
        kit push "$tag" || { fail "$server: kit push"; return 1; }
        log "kit push $tag"
    fi

    SUMMARY+=("$server|$kind|$version|$tag|$entries|$size")
    return 0
}

for server in "${SERVERS[@]}"; do
    # One bad server must not take the others down with it.
    if ! package_one "$server"; then
        FAILURES+=("$server")
    fi
done

# bash 3.2 with `set -u` treats an empty array expansion as unbound, so every
# loop over these arrays is guarded by its length.
echo
if [[ ${#SUMMARY[@]} -gt 0 ]]; then
    printf '%-20s %-7s %-12s %-36s %8s %7s\n' SERVER KIND VERSION TAG FILES SIZE
    printf '%.0s-' $(seq 1 92); echo
    for row in "${SUMMARY[@]}"; do
        IFS='|' read -r s k v t e z <<< "$row"
        printf '%-20s %-7s %-12s %-36s %8s %7s\n' "$s" "$k" "$v" "$t" "$e" "$z"
    done
    echo
    echo "Reference them from an agent definition like this:"
    echo
    echo "  spec:"
    echo "    includes:"
    for row in "${SUMMARY[@]}"; do
        IFS='|' read -r s _ _ t _ _ <<< "$row"
        echo "      - name: $s"
        echo "        type: mcp"
        echo "        source:"
        echo "          modelkit: $t"
        server_config_snippet "$s"
    done
fi

if [[ $KEEP -eq 1 ]]; then
    echo
    echo "Work directory kept at $OUT_DIR"
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "FAILED: ${FAILURES[*]}" >&2
    exit 1
fi
