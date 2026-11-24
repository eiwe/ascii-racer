# ASCII Racer — project instructions

Godot 4.7 project (Forward+, Jolt, GDScript with tabs and static types). `README.md` explains the layout, the renderer pipeline, controls and the test modes; read it before changing things.

## Running and testing

- Run: `godot --path .` (main scene `game/game.tscn`). It opens on the demo reel; add `-- --play` to start on the grid. Renderer demo: `godot --path . res://demo/demo.tscn`.
- `--headless` does not render. Anything that checks output needs a real window; make every run self-quitting and wrap it in `timeout`.
- Handling changes: run the drive test and compare numbers before and after. `godot --path . --fixed-fps 120 -- --drivetest=<dir> [--preset=<name>] [--dtonly=a,b]`.
- Demo reel changes (driver, shots, logo, start/return): `godot --path . -- --attracttest=<dir>` checks the flow with injected input; `godot --path . --fixed-fps 60 -- --attractshots=<dir>` saves frames to look at.
- Renderer changes: run the demo capture and compare images. `godot --path . res://demo/demo.tscn -- --capture=<dir>`. Orthographic output is expected to stay byte-identical unless the change is meant to alter the look.
- Write test output to a scratch directory, never into the repo, and never write the real `user://car_tuning.cfg`.

## Things that have gone wrong before

- A headless `godot --import` once re-imported `assets/kenney_toy-car-kit/Textures/colormap.png` as VRAM-compressed, which changed every model's colours. Its `.import` must stay lossless (`compress/mode=0`, `detect_3d/compress_to=0`). Check `git diff -- '*.import'` after any headless run.
- The default look (`AsciiSettings` defaults, lighting, track colours) was chosen by the owner. Do not change it as a side effect of other work.
- Hiding scenery so the camera can see the car reads as a rendering bug. Brief occlusion is acceptable; for longer occlusion use the halo (`game/halo_occluder.gd`): give the occluding meshes the halo material and they get a round opening around the car.
- `RenderingServer.global_shader_parameter_get()` is editor-only; calling it at runtime raises an error that aborts the calling function.

## README media

The hero animation and logo still at the top of the README are recorded from the game by `tools/make_hero.sh` (needs a display and ffmpeg). Re-run it and commit `docs/images/hero.gif` and `docs/images/logo.png` whenever the logo or the opening of the reel changes. It also writes `build/hero/ascii-racer-reel.mp4`, which is not committed; attach it to the release with `gh release upload v<version> build/hero/ascii-racer-reel.mp4`.

## Releases

When asked for a release, use the script; do not export by hand.

```sh
tools/release.sh <version>             # build and package all three platforms, no publishing
tools/release.sh <version> --publish   # also commit the version bump, tag v<version>, push, create the GitHub release
```

It builds Windows, Linux and macOS from this machine, smoke-tests the Linux build (a window opens briefly), packages into `build/release/<version>/` with checksums, and with `--publish` creates the GitHub release with all three downloads attached.

- Before publishing, write the release notes to `docs/releases/<version>.md` and commit them; the script uses that file, or GitHub's generated notes if it is missing.
- `--publish` needs a clean working tree and refuses to reuse an existing tag.
- Publishing is outward-facing: only pass `--publish` when the owner has asked for the release to go out.
- The macOS build cannot be run on this machine (the owner tests it on a Mac) and is not notarised; mention the first-launch approval step in the notes.
