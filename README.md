# Jozu Demos
Like it says on the tin, this is where we keep artifacts and assets for our demos.

**CLI demos** are stored in Demo Magic so they can be replayed anytime with the associated `.sh` file. Just run the script and hit <enter> to advance to the next action.

In case you don't have an internet connection or other technical issues each demo is also recorded with Asciinema casts. Instructions for running those are below.

## Demo List

### KitOps CLI: Pack and Push
Location: `/cli-demos/pack-and-push`

**Annotated Version**
This is good if you're not able to speak to the demo as it runs.

Play the annotated demo recording:
```
cd /cli-demos/wine-project
asciinema play wine-pack-annotated.cast
```

Running it yourself (semi-interactive):
```
/cli-demos/wine-project/wine-pack-annotated.sh
```

**Non-Annotated Version**
Ideal for demoing live so you can explain things and go at your own pace.

Running it yourself:
```
/cli-demos/wine-project/wine-pack.sh
```

Play the demo recording:
```
cd /cli-demos/wine-project
asciinema play wine-pack.cast
```

### KitOps CLI: Pull and Dev
Location: `/cli-demos/pull-and-dev`

**Annotated Version**
This is good if you're not able to speak to the demo as it runs.

Play the annotated demo recording:
```
cd /cli-demos/pull-and-dev
asciinema play llm-dev-annotated.cast
```

Running it yourself (semi-interactive):
```
/cli-demos/pull-and-dev/llm-dev-annotated.sh
```

**Non-Annotated Version**
Ideal for demoing live so you can explain things and go at your own pace.

Running it yourself:
```
/cli-demos/pull-and-dev/llm-dev.sh
```

Play the demo recording:
```
cd /cli-demos/pull-and-dev
asciinema play llm-dev.cast
```

