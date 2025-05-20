# Jozu Demos
Like it says on the tin, this is where we keep artifacts and assets for our demos. 

CLI demos for KitOps use Demo-Magic to automate the command line execution, and Asciinema to record and playback the output.

Other demos are available as MP4 files.

## KitOps Demos

There are two demos for KitOps:
1. **Pack and push** (`/cli-demos/pack-and-push`): shows packing the wine predictor ML model, training data, MLflow experiments, Jupyter notebook, and docs into a ModelKit, then pushing it to the local and a remote registry. It is good for showing the all-in-one packaging of ModelKits.
2. **Pull and dev** (`/cli-demos/pull-and-dev`): shows pulling a fine-tuned LLM and both full and filtered unpacking.

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
