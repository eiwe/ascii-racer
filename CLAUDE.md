# ASCII Racer — project instructions

Godot 4.7 project (Forward+, Jolt, GDScript with tabs and static types). `README.md` explains the layout, the renderer pipeline, controls and the test modes; read it before changing things.

## Running and testing

- Run: `godot --path .` (main scene `game/game.tscn`). It opens on the demo reel; add `-- --play` to start on the grid. Renderer demo: `godot --path . res://demo/demo.tscn`.
- `--headless` does not render. Anything that checks output needs a real window; make every run self-quitting and wrap it in `timeout`.
- The game has sound and the owner hears every run. Pass `--audio-driver Dummy` (before `--path`) on any scripted run that does not need real audio output.
- Handling changes: run the drive test and compare numbers before and after. `godot --path . --fixed-fps 120 -- --drivetest=<dir> [--preset=<name>] [--dtonly=a,b]`.
- Demo reel changes (driver, shots, logo, start/return): `godot --path . -- --attracttest=<dir>` checks the flow with injected input; `godot --path . --fixed-fps 60 -- --attractshots=<dir>` saves frames to look at.
- Renderer or lighting changes: run the demo capture and compare images. `godot --path . res://demo/demo.tscn -- --capture=<dir>`. Files are named `<zoom>_<squeeze>_<n>_<mode>.png`; the classic mode (`*_3_classic.png`, key 3) must stay byte-identical unless the change is meant to alter the look.
- Sound changes: the mix cannot be judged in a scripted run, so measure it. Record with `--dtonly=audio` under the movie writer and run `tools/measure_audio.py`; rebuild effect files only with `tools/prepare_audio.py`, and keep `assets/audio/CREDITS.md` in step with what ships.
- Write test output to a scratch directory, never into the repo, and never write the real `user://car_tuning.cfg` or `user://audio_settings.cfg` (the pause menu's volumes and opponent level; pass `-- --audiosettings=<scratch file>`).
- The owner may be playing a game window while you work. Before opening a test window, check for it and wait: list `pgrep -x godot` and read each `/proc/<pid>/cmdline`. Do not use `pgrep -f '<pattern>'` from inside a `bash -c` script: it matches the script's own command line.
- Test windows: Hyprland workspace 5 is floating, so windows there keep the size they are given (the monitor is 3440x1440); that is the way to get true 16:9, 16:10 or 21:9 windows. Start the run as usual (so `timeout` and the exit code still work), then move it with `hyprctl dispatch movetoworkspacesilent 5,pid:<godot pid>` once `hyprctl clients -j` lists that pid, and size it with `--resolution WxH` or `hyprctl dispatch resizewindowpixel exact W H,pid:<pid>`. Do not edit the owner's Hyprland config or switch their visible workspace.
- Web build (Compatibility renderer, WebGL 2): develop it on the desktop with `godot --rendering-method gl_compatibility ...`, which is the renderer the browser gets. Compare the demo capture in both renderers (`--capture` with and without it; `--rawmodes` adds the raw 3D frame per mode). Everything web-specific is behind a renderer check (`AsciiRenderer.compat`, `Lighting.compat`, `OS.has_feature("web")`), so the Forward+ capture must not change. Export with `godot --headless --path . --export-release "Web" build/web/index.html` (then check `git diff -- '*.import'`) and serve it with `tools/serve_web.sh`.

## Things that have gone wrong before

- A headless `godot --import` once re-imported `assets/kenney_toy-car-kit/Textures/colormap.png` as VRAM-compressed, which changed every model's colours. Its `.import` must stay lossless (`compress/mode=0`, `detect_3d/compress_to=0`). Check `git diff -- '*.import'` after any headless run.
- The default look (`AsciiSettings` defaults, lighting mode 1 "sunset", track colours) was chosen by the owner. Do not change it as a side effect of other work. Sunset became the default by the owner's choice; "classic" (mode 3) is no longer the default but stays the byte-identity reference.
- Hiding scenery so the camera can see the car reads as a rendering bug. Brief occlusion is acceptable; for longer occlusion use the halo (`game/halo_occluder.gd`): give the occluding meshes the halo material and they get a round opening around the car.
- `RenderingServer.global_shader_parameter_get()` is editor-only; calling it at runtime raises an error that aborts the calling function.
- `Viewport.debug_draw = DEBUG_DRAW_LIGHTING` works from source but does nothing in an exported release build.
- A camera's cull mask also culls lights and shadow casters, not just meshes.
- Files that are not Godot resources (such as `assets/audio/sounds.cfg`) are left out of exports unless they are in the preset's include filter. The first audio export was silent for this reason.
- The Compatibility renderer (web build) has no normal buffer (`hint_normal_roughness_texture` does not compile there), so its g-buffer comes from per-mesh twins (`gbuffer_twin.gdshader`; meshes whose shader discards fragments need a matching twin shader, registered in `AsciiRenderer.gbuffer_twin_shaders`, as the halo is). It also adds its separate light passes (lights with shadows) in sRGB space, so lit areas come out too bright; `Lighting.COMPAT_ENERGY` compensates per mode. Colour adjustments, zero-strength glow and `use_hdr_2d` do not change that.
- Quit through the game's own paths (they stop all sound first). Godot's `--quit-after` can end the program mid-playback and print leak warnings; use the game's `-- --quitafter=<seconds>` instead.

## README media

The hero animation and logo still at the top of the README are recorded from the game by `tools/make_hero.sh` (needs a display and ffmpeg). Re-run it and commit `docs/images/hero.gif` and `docs/images/logo.png` whenever the logo or the opening of the reel changes. It also writes `build/hero/ascii-racer-reel.mp4`, which is not committed; attach it to the release with `gh release upload v<version> build/hero/ascii-racer-reel.mp4`.

## Releases

When asked for a release, use the script; do not export by hand.

```sh
tools/release.sh <version>             # build and package all four targets (Windows, Linux, macOS, web), no publishing
tools/release.sh <version> --publish   # also commit the version bump, tag v<version>, push, create the GitHub release
```

It builds Windows, Linux, macOS and the web build from this machine, smoke-tests the Linux build (a window opens briefly), packages into `build/release/<version>/` with checksums, and with `--publish` creates the GitHub release with all four downloads attached. A missing or incomplete web export stops the script.

- Before publishing, write the release notes to `docs/releases/<version>.md` and commit them; the script uses that file, or GitHub's generated notes if it is missing.
- `--publish` needs a clean working tree and refuses to reuse an existing tag.
- Publishing is outward-facing: only pass `--publish` when the owner has asked for the release to go out.
- The macOS build cannot be run on this machine (the owner tests it on a Mac) and is not notarised; mention the first-launch approval step in the notes.
