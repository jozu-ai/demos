# Jozu Demos
Like it says on the tin, this is where we keep artifacts and assets for our demos.

CLI demos are stored in Demo Magic so they can be replayed anytime with the associated `.sh` file. They're also recorded as Asciinema casts. Other demos are recorded with ScreenFlow and stored in .mp4

## Demo List

### KitOps CLI: Pack and Push
Location: `/cli-demos/wine-project`

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

