# Demo: packaging, signing and verifying an MCP server

Originally built as the companion to the `mcp-packaging` talk
(`mcp-packaging.slides.md`, slide 10, "What you're about to see"), which lives
with the rest of that talk in the `my-notes` repo under
`talks/mcp-packaging/`. That directory keeps a symlink pointing here, so the
talk still runs the demo in place. The demo stands on its own without the
slides.

Builds a real **MCPB bundle** from the `everything` MCP server, packages that
bundle as an OCI artifact with **KitOps**, signs and attests it with **cosign**,
verifies it, then tampers with it and watches verification fail.

**Not to be confused with `cli-demos/mcpb-pack`,** which is a packaging tool: it
turns all seven reference MCP servers into one ModelKit each, for agent
definitions to pull as `type: mcp` modules. This demo packages exactly one
server and spends its time on the trust story instead — signing, attesting,
verifying and tampering.

The point of the demo is the split: **KitOps packages, plain cosign verifies.**
Cosign has never heard of KitOps or Jozu. If verification needed our tool, the
demo would be doing the exact thing the talk argues against.

## Running it

```bash
./setup.sh        # before you go on stage - slow, network-dependent, idempotent
./mcp-trust.sh    # the demo; ENTER advances each command
./reset.sh        # put it back so you can run it again
```

`./mcp-trust.sh -n` runs straight through without waiting, for rehearsal.
`-w2` auto-advances each step after two seconds instead of waiting for ENTER.

## Recording it

```bash
./record-video.sh   # -> mcp-trust-demo.mp4, ~3 minutes, runs the demo for real
```

It resets first, then drives `mcp-trust.sh -w2` through `mcp-trust.tape`, so the
video is the same demo the room sees, just advancing on a timer. Output is
2560x1440 H.264 with a silent audio track, sized for YouTube: 1440p gets VP9
rather than only AVC, which is worth having for text.

**Terminal width is the constraint.** `mcp-trust.sh` disables line wrapping, so
anything wider than the terminal is truncated rather than wrapped. Four commands
carry backslash continuations purely so the recording fits: both `cosign attest`
calls, `cosign verify-attestation`, and the tamper repack. Without them the
widest line is 260 columns and needs a font too small to read on video. With
them the widest is 188 - `cosign tree`'s referrer output, which cannot be
reflowed - and 19px Hack gives 207 columns x 63 rows. Past 20px it clips again.

Even so, 188 columns is a desktop-full-screen video, not a phone one.

Nothing here should need `record-video.sh` in principle - `vhs mcp-trust.tape`
is the whole job. But vhs 0.12.0 with ffmpeg 9 renders every frame and then
silently skips its own encode step, deleting the frames and exiting 0 with no
file written. The script mirrors the frames out of `$TMPDIR` while vhs is still
running and encodes them itself. If a later vhs writes the `.mp4` unaided, the
script can go.

## The flow

1. `mcpb init` — generates `manifest.json` from the server's `package.json`.
   Not hand-written, and neither is the Kitfile in step 3
2. `mcpb pack` — the bundle: manifest, server, and its production dependencies
   (2,560 files, 13.8MB unpacked, 4.2MB packed)
3. `mcpb info` — reports **`WARNING: Not signed`**
4. `npm sbom` — CycloneDX bill of materials, produced by npm itself
5. `./record-build.sh` — emits SLSA v1 provenance for the build that just ran,
   recording the `.mcpb` and the SBOM as its byproducts
6. `kit init` — generates the Kitfile. It recognises the `.mcpb` and emits an
   `mcpServers:` section; you do not hand-write it
7. `kit pack` / `kit push` — one layer, media type
   `application/vnd.kitops.modelkit.mcpb.v1.raw`
8. `kit inspect --remote` — the `mcpServers` section survived into the
   registry, with the bundle's digest. Then `crane` confirms the same bytes
   independently: KitOps says what it recorded, a generic OCI client agrees
9. `cosign sign` + `cosign attest` — signature, then provenance naming the
   upstream repo and commit
10. `cosign verify` + `verify-attestation` — decodes the predicate back to source,
   then `cosign tree` shows signature, provenance and SBOM all hanging off the
   one digest as OCI referrers
11. Tamper, repack, push to the same tag — verification fails

## Requirements

`mcpb`, `kit`, `cosign` (v3+), `docker`, `crane`, `jq`, `npm`. Verified against
mcpb 2.1.2, kit 1.15.0, cosign 3.1.3.

## What is in here

| Path | What it is |
|---|---|
| `server/` | The `everything` MCP server, vendored pre-built from `modelcontextprotocol/servers` @ `d31124c`. **Nothing is cloned or compiled on stage** — `setup.sh` refuses to run without `server/dist`. Only `dist/` and `README.md` are vendored, because that is all the demo reads; the TypeScript sources are not here. Upstream is pinned by `SOURCE_URI` and `SOURCE_COMMIT` in `demo.env` if you need them |
| `bundle/` | MCPB staging: `server/` plus bundled production deps, assembled by `setup.sh`. `manifest.json` is **not** kept here — `mcpb init` creates it live in step 1. Gitignored |
| `package/` | Output: the built `.mcpb` and the `kit init` Kitfile. Created live, gitignored |
| `record-build.sh` | Emits `provenance.json` (SLSA v1, how it was built). The SBOM is generated separately by `npm sbom` in its own demo step; this script only records its digest as a byproduct. Both files gitignored |
| `demo.env` | Shared config (registry port, refs, paths) |
| `keys/` | Generated by `setup.sh`, gitignored |
| `demo-magic.sh` | **Local copy, deliberately divergent from `cli-demos/demo-magic.sh`.** It uses `eval "$@"` where upstream has `eval $@`, so the four backslash-continued commands keep their argument boundaries. Do not dedupe it against the shared copy |
| `.pristine-index.js` | Backup of the bundle entry point taken by `setup.sh`, so `reset.sh` can undo the tamper. Gitignored |

## Why wrap the bundle at all

MCPB is a **format**. OCI is a format **and a distribution protocol**. The
MCPB spec defines a zip and a manifest and deliberately stops there — its
manifest has `repository`, `homepage` and `documentation` fields but no digest
and no download field, and upstream says you install one by opening the file.

That leaves four gaps this demo fills:

- **No content addressing** — a `.mcpb` is fetched by URL, not by digest
- **Nowhere to attach anything** — OCI referrers let signatures and
  attestations hang off an artifact by digest; a `.mcpb` on a GitHub release
  has no defined place for an attestation
- **No registry semantics** — no tag resolution, auth, mirroring or promotion
- **No chokepoint** — no pull protocol means nowhere to force verification

The MCP registry demonstrates the gap rather than closing it: an MCPB entry is
a release URL plus a `fileSha256` carried in registry metadata, and the
registry does not validate that hash.

**The demo proves the bundle survives intact.** One step prints the local
`.mcpb`'s sha256 next to the OCI layer digest — they are identical. Nothing is
transformed or re-wrapped. The bundle just gains an address and somewhere to
hang provenance. If you make one point at the terminal, make that one.

## Provenance and SBOM are different claims

They get conflated, so keep them apart on stage:

- **Provenance** (`https://slsa.dev/provenance/v1`) says *how this was produced*
  — which source commit, which builder, which tool versions.
- **SBOM** (`https://cyclonedx.org/bom`) says *what is inside* — 106 npm
  components with purls. Generated by `npm sbom` as its own visible step, so
  the room sees a standard tool doing it rather than a script of ours.

They answer different questions. "Is log4j in here?" is an SBOM question.
"Who built this and from what?" is a provenance question. You want both, and
`cosign tree` shows both attached to the same immutable digest alongside the
signature — three independent claims, none of which modified the artifact.

That is the sharpest contrast with in-band signing: an `.mcpb` signature has to
rewrite the bundle, so each claim changes the artifact's identity and only a
chain of signers is possible. Here, any number of parties can attach any number
of claim types to one digest, in any order, without touching the bytes.

## Stage notes

**Expect the `Not signed` question.** `mcpb info` says it, and MCPB has its own
`mcpb sign` / `mcpb verify` pair, so someone will ask why we did not just use
it. That question is a gift — it is the talk's thesis in miniature. `mcpb sign`
puts a signature inside the bundle, verifiable by tools that understand MCPB.
Signing at the OCI layer gives provenance that any policy engine, registry or
client can check without knowing what an MCPB is. Same argument as the LSP
marketplaces: per-format signing is not open trust.

**It runs fully offline.** The registry is a local `registry:2` on **port 5001**
(5000 is taken by macOS AirPlay Receiver). Signing uses a local key and an empty
signing config, so no Fulcio and no Rekor. Nothing touches the network once
`setup.sh` has run. `setup.sh` itself needs network the first time, for
`npm install` of the bundled dependencies.

**Two flags are on screen, and both deserve a sentence if asked.**

- `--signing-config keys/offline-signing-config.json` — no transparency log.
- `--insecure-ignore-tlog=true` on verify, which prints a scary warning.

That warning is honest, and the honest answer is the better story: in CI you
would sign keyless via OIDC, the identity would be a real GitHub identity
rather than a key in a folder, and the signature would land in Rekor. That is
also the version worth trusting — a laptop key proves far less. Local keys are
here only so a conference network cannot break the demo.

**The tamper step is the payoff.** It appends a line to `bundle/server/index.js`,
rebuilds the `.mcpb`, repacks and pushes to the *same tag*. Then, in order:

1. `cosign verify` against the **tag** fails with `Error: no signatures found`.
2. `cosign verify` against the **original digest** still passes.

The signature never broke. The tag moved. That is the argument for pinning
digests, and it is the sharpest thirty seconds in the demo — do not rush it.

**If something goes wrong**, `./reset.sh` restores the untampered entry point,
clears `package/`, clears local kit storage and empties the registry. Keys,
bundled dependencies and the registry container survive, so reset is fast.

## Known rough edges

- `mcpb pack` prints all 2,560 bundled files, so the demo pipes it through
  `tail` to show only the Archive Details summary.
- `kit push` needs `--plain-http` for a local registry; cosign auto-detects
  localhost and needs no insecure flags.
- `manifest.json` comes from `mcpb init -y`, so the author is `Unknown Author`.
  Fine for the demo, and arguably a nice detail: it is metadata nobody checks.
- `provenance.json` is generated by `record-build.sh` from observed facts: the
  vendored source commit, the generated manifest's digest, all 106 npm packages
  npm resolved into the bundle (with their published integrity hashes), and the
  mcpb/node versions that did the work. It deliberately omits `startedOn` and
  claims no CI workflow, because the script cannot observe either.
- **The `buildType` is a placeholder.** `JZ-SPEC-ATTESTATION-001` §8 registers
  predicates for import, scan and validity but nothing for a pack-time build,
  and §8 says new types MUST be registered before use. `BUILD_TYPE` in
  `demo.env` is a stand-in for that missing registration — worth naming from
  stage rather than glossing over.
- `SOURCE_COMMIT` lives in `demo.env` because the vendored `server/` carries no
  `.git`. In a real pipeline CI reads it from the checkout it built.
