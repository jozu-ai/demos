# Jozu Demos
Like it says on the tin, this is where we keep artifacts and assets for our demos. 

CLI demos for KitOps use Demo-Magic to automate the command line execution, and Asciinema to record and playback the output.

Other demos are available as MP4 files.

## KitOps Demos

The KitOps demos:
- **Pack and push** (`/cli-demos/pack-and-push`): shows packing the wine predictor ML model, training data, MLflow experiments, Jupyter notebook, and docs into a ModelKit, then pushing it to the local and a remote registry. It is good for showing the all-in-one packaging of ModelKits.
- **Pull and dev** (`/cli-demos/pull-and-dev`): shows pulling a fine-tuned LLM and both full and filtered unpacking.
- **MCPB packaging** (`/cli-demos/mcpb-pack`): shows an MCP server packaged as a ModelKit carrying one MCPB bundle, so an agent definition can pull it as a `type: mcp` module. Unlike the others it builds its own artifact first, vendoring the server's dependency closure for the guest. Needs Kit v1.15.0 or later to unpack the result.

### Running demos interactively

#### Executing the commands on your machine
You can run the pre-recorded demo interactively so you control when commands are executed. In this case the commands are actually running so ensure that you have connectivity to your registry and that the lastest Kit version is in your PATH.

Navigate to `/cli-demos` and select either the `/pack-and-push` or `pull-and-dev` subdirectories depending on what you want to show.

Once there you should see both normal and annotated script files. You will mostly use the non-annotated scripts. The annotated scripts are generally for recording demos that are not interactive.

To execute the pack-and-push demo locally for example:

```sh
$ ./wine-pack.sh
```

Then hit <enter> to execute the demo when it pauses (typically after each command has run).

#### Playing back a recording (not executed)
You can also play back a recording of the demos for situations where you don't have strong connectivity to the registry or where the Kit CLI isn't available locally.

Navigate to `/cli-demos` and select either the `/pack-and-push` or `pull-and-dev` subdirectories depending on what you want to show.

To playback the pack-and-push demo for example:

```sh
$ asciinema play wine-pack.cast
```

You can hit <space> during the running demo to pause and unpause the recording, but otherwise the demos will run from start to completion.

### Running demos non-interactively (annotated)
If you need to run a demo on a loop or unattended it's best to use the annotated cast files with Asciinema. You can run them through once with the `asciinema play` command, or loop them with `asciinema play -l` command.

For example, to loop the playback of the pack-and-push demo:

```sh
$ asciinema play -l wine-pack-annotated.cast
```

Even in this mode you can still manually pause and unpause the recording using the <space> bar.

## MCP Trust Demo

**MCPB sign and verify** (`/cli-demos/mcpb-trust`): builds a real MCPB bundle from
the `everything` MCP server, packages it as an OCI artifact with KitOps, signs and
attests it with cosign, verifies it, then tampers with it and watches verification
fail.

The point is the split: **KitOps packages, plain cosign verifies.** Cosign has
never heard of KitOps or Jozu, so verification needs none of our tools.

This is the trust counterpart to the MCPB packaging demo in `/cli-demos/mcpb-pack`:
that one packages all seven reference servers for agent definitions to consume,
this one takes a single server and follows the signature end to end.

It does not follow the Asciinema conventions above. It has its own `setup.sh` /
`reset.sh` pair and ships a VHS tape instead of a `.cast` file, recorded to MP4:

```sh
$ cd cli-demos/mcpb-trust
$ ./setup.sh        # before you go on stage - slow, network-dependent, idempotent
$ ./mcp-trust.sh    # the demo; ENTER advances each command
$ ./reset.sh        # put it back so you can run it again
```

`./mcp-trust.sh -n` runs straight through without waiting, for rehearsal. `-w2`
auto-advances every two seconds. `./record-video.sh` produces `mcp-trust-demo.mp4`.

Once `setup.sh` has run the demo is **fully offline** — it signs with a local key
and pushes to a local `registry:2` container on port 5001, so a conference network
cannot break it. It needs `mcpb`, `kit`, `cosign` (v3+), `docker`, `crane`, `jq`
and `npm`.

`cli-demos/mcpb-trust/README.md` carries the full step-by-step flow, the stage
notes and the answers to the questions this demo reliably gets asked. Read it
before presenting.
