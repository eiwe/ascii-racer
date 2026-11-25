#!/usr/bin/env python3
"""Builds the game's sound files from the raw downloads (kept out of the repo).

    tools/prepare_audio.py <raw dir> [--out assets/audio] [--standins <dir>]
    tools/prepare_audio.py --beeps [--out assets/audio]

<raw dir> is the sourcing folder's `raw/` (see assets/audio/CREDITS.md for where
each file came from). Writes assets/audio/sfx/*.ogg and assets/audio/sounds.cfg,
the table that tells the game which file plays which role. The start
lights' two beeps are synthesised tones (a beep is a tone); --beeps writes
only those (and their table entries). With --standins it
instead writes synthetic test tones and a matching table into <dir> (for
measuring the engine's pitch handling; never shipped).

Needs ffmpeg and numpy. Every step is printed: source range, measured pitch,
loudness before and after.
"""
import argparse
import os
import re
import subprocess
import sys

import numpy as np

SR = 48000

# Engine loops: [role, source file, start s, length s, expected firing Hz].
# The firing frequency of a 4-cylinder is rpm / 30; the table stores rpm.
ENGINE = [
    ["engine_idle", "engine/opel-astra-1.6-16v_qubodup/freesound-147243_qubodup_Car-Engine-Ignition-Running-and-Turn-Off_preview-hq.ogg", 12.0, 4.0, 27.0],
    ["engine_mid", "engine/opel-astra-1.6-16v_qubodup/freesound-147243_qubodup_Car-Engine-Ignition-Running-and-Turn-Off_preview-hq.ogg", 54.0, 4.0, 76.5],
    ["engine_high", "engine/opel-astra-1.6-16v_qubodup/opengameart_car-engine-loop-96khz-4s/extracted/engine-loop/engine-loop-1.wav", 0.0, 4.0, 87.2],
]
# Other loops: [role, source, start s, length s].
LOOPS = [
    ["tyre_squeal", "tyres/opengameart_car-tire-squeal-skid-loop_tires_squal_loop.wav", 0.0, 3.0],
    ["tyre_skid", "tyres/bigsoundbank-2371_Screeching-Tires-4.wav", 2.1, 3.9],
    ["nitro_sustain", "nitro/archive-org_Red_Library_Air_Industry_R17-01-Pressurized-Air.wav", 1.0, 6.0],
]
# One-shots: [role, source, start s, length s, fade-out s].
SHOTS = [
    ["land", "chassis/freesound-636496_j_soundeffects_Soft-Impact-Foley-on-Hood-of-1990-Volvo-240-Sedan_preview-hq.ogg", 2.90, 0.70, 0.35],
    ["kerb", "chassis/freesound-800679_kd33n_Tiresbouncing-over-sewer-cover_preview-hq.ogg", 0.40, 0.48, 0.2],
    ["impact_solid", "impacts/archive-org_SSE_Library_METAL_METLCrsh-Two-cars-crash-foley-good-metallic-bump-CS-USC.wav", 0.0, 1.2, 0.5],
    ["impact_cone", "impacts/kenney_impact-sounds/x/Audio/impactSoft_medium_001.ogg", 0.0, 0.6, 0.15],
    ["nitro_ignite", "nitro/archive-org_SSE_Library_AIR_AIRBrst-Carbon-dioxide-fire-extinguisher-long-blast-CS-USC.wav", 0.30, 1.1, 0.6],
]
LOOP_LUFS = -20.0
SHOT_PEAK_DB = -3.0
XFADE = 0.04 # loop seam crossfade (s)


def decode(path, channels=None):
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ar", str(SR)]
    if channels:
        cmd += ["-ac", str(channels)]
    cmd.append("-")
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    ch = channels or int(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels", "-of", "csv=p=0", path],
        capture_output=True, text=True, check=True).stdout.strip())
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, ch).copy()


def encode(x, path, quality):
    ch = x.shape[1]
    p = subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "-",
        "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", path], input=x.astype(np.float32).tobytes(), check=True)


def lufs(x):
    p = subprocess.run(["ffmpeg", "-v", "info", "-f", "f32le", "-ar", str(SR), "-ac", str(x.shape[1]), "-i", "-", "-af", "ebur128", "-f", "null", "-"],
        input=x.astype(np.float32).tobytes(), capture_output=True)
    m = re.findall(r"I:\s+(-?[0-9.]+) LUFS", p.stderr.decode())
    return float(m[-1]) if m else float("nan")


def db(v):
    return 20.0 * np.log10(max(v, 1e-12))


def firing_hz(x, expect):
    """Engine firing frequency near `expect` (within +-25 %): the harmonic
    product of the spectrum's partials at f, 2f, 3f (robust to the crank
    sub-harmonic), refined by parabolic interpolation."""
    m = x.mean(axis=1)
    m = m - m.mean()
    n = 1 << int(np.ceil(np.log2(len(m) * 4)))
    spec = np.abs(np.fft.rfft(m * np.hanning(len(m)), n))
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    best, best_f = -1.0, expect
    for f in np.linspace(expect * 0.75, expect * 1.25, 2000):
        s = 0.0
        for h in (1, 2, 3):
            s += np.log(1e-9 + np.interp(f * h, freqs, spec))
        if s > best:
            best, best_f = s, f
    return best_f


def make_loop(x, length, period=None):
    """`length` s of x made seamless: the XFADE after the cut is faded into the
    start (equal power). With a period, the length is a whole number of them."""
    n = int(round(length * SR))
    if period:
        n = int(round(round(n / (period * SR)) * period * SR))
    f = int(XFADE * SR)
    if len(x) < n + f:
        # A source that is itself a loop (the engine-high file): tile it once.
        x = np.concatenate([x, x])
    body = x[:n].copy()
    tail = x[n:n + f]
    t = np.linspace(0.0, 1.0, f)[:, None]
    body[:f] = body[:f] * np.sin(t * np.pi / 2) + tail * np.cos(t * np.pi / 2)
    return body


# Start-light beeps: [role, frequency Hz, length s, level dBFS peak, game gain dB].
BEEPS = [
    ["start_beep", 880.0, 0.16, -6.0, -8.0],
    ["start_go", 1320.0, 0.55, -5.0, -6.0],
]


def beep(freq, length, peak_db):
    """A soft-edged tone with a little second and third harmonic (less
    piercing than a pure sine), a 5 ms attack and an exponential tail."""
    t = np.arange(int(length * SR)) / SR
    x = np.sin(2 * np.pi * freq * t) + 0.18 * np.sin(4 * np.pi * freq * t) + 0.06 * np.sin(6 * np.pi * freq * t)
    env = np.minimum(t / 0.005, 1.0) * np.exp(-t / (length * 0.45))
    env *= np.minimum((length - t) / 0.02, 1.0)
    x = x * env
    return (x / np.abs(x).max() * 10 ** (peak_db / 20))[:, None]


def write_beeps(out, table_lines):
    sfx = os.path.join(out, "sfx")
    os.makedirs(sfx, exist_ok=True)
    for role, f, l, pk, g in BEEPS:
        encode(beep(f, l, pk), os.path.join(sfx, role + ".ogg"), 6)
        print(f"{role}: synthesised {f:.0f} Hz tone, {l:.2f} s, peak {pk:.1f} dBFS")
        table_lines += [f"[{role}]", f'file="sfx/{role}.ogg"', f"gain_db={g:.1f}", ""]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw", nargs="?")
    ap.add_argument("--beeps", action="store_true")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio"))
    ap.add_argument("--standins")
    a = ap.parse_args()
    if a.standins:
        return standins(a.standins)
    if a.beeps:
        # Only the beeps: write them and add their sections to the table if missing.
        lines = []
        write_beeps(a.out, lines)
        path = os.path.join(a.out, "sounds.cfg")
        table = open(path).read() if os.path.exists(path) else ""
        for role, _f, _l, _p, g in BEEPS:
            if f"[{role}]" not in table:
                table = table.rstrip("\n") + "\n\n" + "\n".join([f"[{role}]", f'file="sfx/{role}.ogg"', f"gain_db={g:.1f}"]) + "\n"
        open(path, "w").write(table)
        print("updated", path)
        return
    if not a.raw:
        ap.error("raw dir needed")
    sfx = os.path.join(a.out, "sfx")
    os.makedirs(sfx, exist_ok=True)
    table = ["; Which file plays which role (see game/audio/sound_table.gd). Written by",
        "; tools/prepare_audio.py; gains are the game's balance on top of the files'",
        "; own normalised levels. Engine loops: rpm = the engine speed the loop was",
        "; recorded at (firing frequency x 30 for this 4-cylinder).", ""]
    for i, (role, src, start, length, expect) in enumerate(ENGINE):
        x = decode(os.path.join(a.raw, src))
        seg = x[int(start * SR):int((start + length + 1.0) * SR)]
        f0 = firing_hz(seg[:int(length * SR)], expect)
        loop = make_loop(seg, length, 1.0 / f0)
        l0 = lufs(loop)
        loop *= 10 ** ((LOOP_LUFS - l0) / 20)
        out = os.path.join(sfx, role + ".ogg")
        encode(loop, out, 7)
        rpm = f0 * 30.0
        print(f"{role}: {src} {start:.2f}+{len(loop)/SR:.3f} s, firing {f0:.2f} Hz = {rpm:.0f} rpm, {l0:.1f} -> {lufs(loop):.1f} LUFS, peak {db(np.abs(loop).max()):.1f} dBFS")
        table += [f"[engine_loop_{i}]", f'file="sfx/{role}.ogg"', f"rpm={rpm:.0f}", "gain_db=0.0", ""]
    for role, src, start, length in LOOPS:
        x = decode(os.path.join(a.raw, src))
        seg = x[int(start * SR):int((start + length + 1.0) * SR)]
        loop = make_loop(seg, length)
        l0 = lufs(loop)
        loop *= 10 ** ((LOOP_LUFS - l0) / 20)
        encode(loop, os.path.join(sfx, role + ".ogg"), 7)
        print(f"{role}: {src} {start:.2f}+{len(loop)/SR:.3f} s loop, {l0:.1f} -> {lufs(loop):.1f} LUFS, peak {db(np.abs(loop).max()):.1f} dBFS")
        table += [f"[{role}]", f'file="sfx/{role}.ogg"', "gain_db=0.0", ""]
    for role, src, start, length, fade in SHOTS:
        x = decode(os.path.join(a.raw, src))
        seg = x[int(start * SR):int((start + length) * SR)].copy()
        fi = int(0.003 * SR)
        seg[:fi] *= np.linspace(0, 1, fi)[:, None]
        fo = int(fade * SR)
        seg[-fo:] *= (np.cos(np.linspace(0, np.pi / 2, fo)) ** 2)[:, None]
        pk = np.abs(seg).max()
        seg *= 10 ** (SHOT_PEAK_DB / 20) / max(pk, 1e-9)
        encode(seg, os.path.join(sfx, role + ".ogg"), 6)
        print(f"{role}: {src} {start:.2f}+{length:.2f} s, peak {db(pk):.1f} -> {SHOT_PEAK_DB:.1f} dBFS")
        table += [f"[{role}]", f'file="sfx/{role}.ogg"', "gain_db=0.0", ""]
    write_beeps(a.out, table)
    table += ["[music_menu]", 'file="music/menu.mp3"', "xfade_at=68.0", "xfade=1.0", "gain_db=0.0", "",
        "[music_race]", 'file="music/race.mp3"', "xfade_at=192.5", "xfade=2.0", "gain_db=0.0", ""]
    with open(os.path.join(a.out, "sounds.cfg"), "w") as f:
        f.write("\n".join(table))
    print("wrote", os.path.join(a.out, "sounds.cfg"))


def standins(d):
    """Synthetic stand-ins: harmonic tones at exactly the table's engine rpm, so
    the output pitch can be tracked; plain noise / tones for the rest."""
    os.makedirs(d, exist_ok=True)
    rng = np.random.default_rng(1)
    table = ["; synthetic stand-ins (not shipped)", ""]
    for i, rpm in enumerate([810, 2290, 2616]):
        f0 = rpm / 30.0
        n = int(round(round(2.0 * f0) / f0 * SR))
        t = np.arange(n) / SR
        x = sum(np.sin(2 * np.pi * f0 * h * t) / h for h in (1, 2, 3, 4))
        x = (x / np.abs(x).max() * 0.3)[:, None]
        encode(x, os.path.join(d, f"engine_{i}.ogg"), 7)
        table += [f"[engine_loop_{i}]", f'file="engine_{i}.ogg"', f"rpm={rpm}", "gain_db=0.0", ""]
    for role, f in [("tyre_squeal", 1800.0), ("tyre_skid", 1400.0), ("nitro_sustain", 0.0)]:
        t = np.arange(2 * SR) / SR
        x = np.sin(2 * np.pi * f * t) * 0.2 if f > 0 else rng.normal(0, 0.1, len(t))
        encode(x[:, None], os.path.join(d, role + ".ogg"), 7)
        table += [f"[{role}]", f'file="{role}.ogg"', "gain_db=0.0", ""]
    for role, f in [("land", 70.0), ("kerb", 300.0), ("impact_solid", 150.0), ("impact_cone", 900.0), ("nitro_ignite", 0.0)]:
        t = np.arange(int(0.4 * SR)) / SR
        env = np.exp(-t * 12)
        x = (np.sin(2 * np.pi * f * t) if f > 0 else rng.normal(0, 0.5, len(t))) * env * 0.7
        encode(x[:, None], os.path.join(d, role + ".ogg"), 6)
        table += [f"[{role}]", f'file="{role}.ogg"', "gain_db=0.0", ""]
    with open(os.path.join(d, "sounds.cfg"), "w") as f:
        f.write("\n".join(table))
    print("wrote stand-ins to", d)


if __name__ == "__main__":
    main()
