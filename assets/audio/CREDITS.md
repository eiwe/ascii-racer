# Audio credits

Every sound file shipped in `assets/audio/`, where it came from and under what
licence. The game-ready files in `sfx/` are cut, looped, levelled and encoded
from the originals by `tools/prepare_audio.py`, which records the exact source
ranges; the originals are not in the repository. "Modified" below means
trimmed, looped (crossfaded seam) and level-normalised, and re-encoded as Ogg
Vorbis.

Files marked **preview** were made from Freesound's public lossy (Ogg) preview
of the recording, because the original needs a Freesound login. They should be
rebuilt from the originals when someone with an account downloads them (same
script, same source ranges).

## Music

| File | What | Source |
|---|---|---|
| `music/menu.mp3` | Title / demo reel music ("Ascii racing menu") | Supplied by the project owner. Copied with the audio stream unchanged and all tags and cover art removed. |
| `music/race.mp3` | Race music ("Pixel Velocity") | Supplied by the project owner. Copied the same way. |

## Engine

| File | What | Source, author, licence |
|---|---|---|
| `sfx/engine_idle.ogg` | Engine at idle (~770 rpm), 4 s loop | **preview.** "Car Engine Ignition Running and Turn Off" by qubodup, https://freesound.org/s/147243/ (Opel Astra 1.6 16V). CC BY 4.0. Cut from 12-16 s, modified. |
| `sfx/engine_mid.ogg` | Engine held near 2,300 rpm, 4 s loop | **preview.** Same recording, cut from 54-58 s, modified. CC BY 4.0. |
| `sfx/engine_high.ogg` | Engine near 2,600 rpm, 4 s loop | "Car Engine Loop 96kHz, 4s" by qubodup, https://opengameart.org/content/car-engine-loop-96khz-4s (the 24-bit / 96 kHz `engine-loop-1.wav`). CC BY 3.0. Modified (seam crossfaded, levelled). |

Required attributions:

- "Car Engine Ignition Running and Turn Off" by qubodup — https://freesound.org/s/147243/ — License: Attribution 4.0 (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). Trimmed, looped and levelled.
- "Car Engine Loop 96kHz, 4s" by qubodup — https://opengameart.org/content/car-engine-loop-96khz-4s — CC BY 3.0 (http://creativecommons.org/licenses/by/3.0/). Seam crossfaded and levelled.

## Tyres

| File | What | Source, author, licence |
|---|---|---|
| `sfx/tyre_squeal.ogg` | Tyre squeal loop (grip limit) | "Car tire squeal skid loop" by audible-edge (Tom Haigh), loop edit by qubodup, https://opengameart.org/content/car-tire-squeal-skid-loop. CC BY 3.0. Levelled. |
| `sfx/tyre_skid.ogg` | Long skid loop (handbrake drift) | "Screeching Tires 4" by Dorian CLAIR, BigSoundBank, https://bigsoundbank.com/screeching-tires-4-s2371.html. CC0. Cut from 2.1-6.0 s and looped. |

Required attribution:

- "Car tire squeal skid loop" by audible-edge (Tom Haigh), loop edit by qubodup — https://opengameart.org/content/car-tire-squeal-skid-loop — CC BY 3.0 (http://creativecommons.org/licenses/by/3.0/). Levelled.

Courtesy credit (CC0): Additional sounds: Dorian CLAIR - BigSoundBank.com.

## Chassis, impacts

| File | What | Source, author, licence |
|---|---|---|
| `sfx/land.ogg` | Landing thump | **preview.** "Soft Impact Foley on Hood of 1990 Volvo 240 Sedan" by j_soundeffects, https://freesound.org/s/636496/. CC BY 4.0. Cut from 2.90-3.60 s, faded, levelled. |
| `sfx/kerb.ogg` | Kerb / bump knock | **preview.** "Tiresbouncing over sewer cover" by kd33n, https://freesound.org/s/800679/. CC0. Cut from 0.40-0.88 s. |
| `sfx/impact_solid.ogg` | Hitting a wall or a tree | "METLCrsh_Two cars crash foley; good metallic bump" (USC Cinema / Sunset Editorial sound effects collection), via the Internet Archive, https://archive.org/details/SSE_Library_METAL. CC0. First 1.2 s, faded. |
| `sfx/impact_cone.ogg` | Hitting a cone | `impactSoft_medium_001.ogg` from Kenney "Impact Sounds", https://kenney.nl/assets/impact-sounds. CC0. |

Required attribution:

- "Soft Impact Foley on Hood of 1990 Volvo 240 Sedan" by j_soundeffects — https://freesound.org/s/636496/ — License: Attribution 4.0 (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). Trimmed and levelled.

## Nitro

| File | What | Source, author, licence |
|---|---|---|
| `sfx/nitro_ignite.ogg` | Burst when the nitro lights | "AIRBrst_Carbon dioxide fire extinguisher; long blast" (USC Cinema / Sunset Editorial collection), via the Internet Archive, https://archive.org/details/SSE_Library_AIR. CC0. Cut from 0.30-1.40 s, faded. |
| `sfx/nitro_sustain.ogg` | Hiss while burning | "R17-01-Pressurized Air" (Red Library), via the Internet Archive, https://archive.org/details/Red_Library_Air_Industry. CC0. Cut from 1.0-7.0 s and looped. |

Provenance note for the Internet Archive items (from the sourcing notes): the
items state CC0 in their licence field and describe the content as sound
effects from the USC Cinema and/or Sunset Editorial collection; the chain from
the original recordists to the CC0 dedication is not documented on the item
pages.
