#!/usr/bin/env python3
"""Measures the game's audio from drive-test recordings (`--dtonly=audio` under
the movie writer). Usage:

    tools/measure_audio.py <dir with run_all/, run_music/, run_sfx/> [--pitch <stand-in run dir>]

Each run dir holds audio.avi (from --write-movie) and the test's
70_audio_segments.csv / 70_audio_frames.csv. run_music and run_sfx are the same
run with --audiomix=music / --audiomix=sfx. Prints per scenario: integrated
loudness and peak of the whole mix, of the music alone and of the car alone,
the music-to-car gap, clipping, and which layers were active; with --pitch, the
engine pitch track against the simulated engine speed.
"""
import argparse, csv, os, re, subprocess, sys
import numpy as np

SR = 48000
FPS = 60.0


def wav(run):
    src = os.path.join(run, "audio.wav")
    if not os.path.exists(src):
        src = os.path.join(run, "audio.avi")
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-vn", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)


def segments(run):
    out = []
    with open(os.path.join(run, "70_audio_segments.csv")) as f:
        for r in csv.DictReader(f):
            if r["scenario"]:
                out.append((r["scenario"], int(r["first_frame"]), int(r["last_frame"])))
    return out


def frames(run):
    with open(os.path.join(run, "70_audio_frames.csv")) as f:
        return list(csv.DictReader(f))


def lufs(x):
    if len(x) < SR * 0.5:
        return float("nan")
    p = subprocess.run(["ffmpeg", "-v", "info", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-af", "ebur128", "-f", "null", "-"],
        input=x.astype(np.float32).tobytes(), capture_output=True)
    m = re.findall(r"I:\s+(-?[0-9.]+) LUFS", p.stderr.decode())
    return float(m[-1]) if m else float("nan")


def db(v):
    return 20 * np.log10(max(v, 1e-9))


def cut(x, a, b):
    return x[int(a / FPS * SR):int(b / FPS * SR)]


def f0_track(x, lo=20.0, hi=200.0, win=0.12, hop=0.04):
    m = x.mean(axis=1)
    n = int(win * SR)
    h = int(hop * SR)
    nfft = 1 << 15
    freqs = np.fft.rfftfreq(nfft, 1 / SR)
    out = []
    cand = np.arange(lo, hi, 0.25)
    for i in range(0, len(m) - n, h):
        s = np.abs(np.fft.rfft(m[i:i + n] * np.hanning(n), nfft))
        if s.max() < 1e-4:
            out.append(np.nan)
            continue
        score = sum(np.log(1e-9 + np.interp(cand * k, freqs, s)) for k in (1, 2, 3, 4))
        out.append(cand[np.argmax(score)])
    return np.array(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--pitch")
    a = ap.parse_args()
    runs = {k: os.path.join(a.dir, "run_" + k) for k in ("all", "music", "sfx")}
    have = {k: os.path.exists(os.path.join(v, "audio.wav")) or os.path.exists(os.path.join(v, "audio.avi")) for k, v in runs.items()}
    xs = {k: wav(v) for k, v in runs.items() if have[k]}
    segs = segments(runs["all"])
    fr = frames(runs["all"])
    by_scn = {}
    for r in fr:
        by_scn.setdefault(r["scenario"], []).append(r)
    print(f"{'scenario':22s} {'mix LUFS':>8s} {'peak':>6s} {'>-1dB':>6s}  {'music':>6s} {'car':>6s} {'gap LU':>6s}  layers")
    for name, a0, b0 in segs:
        row = [f"{name:22s}"]
        x = cut(xs["all"], a0, b0)
        pk = np.abs(x).max() if len(x) else 0
        row += [f"{lufs(x):8.1f}", f"{db(pk):6.1f}", f"{int((np.abs(x) > 10 ** (-1 / 20)).sum()):6d}"]
        lm = lufs(cut(xs["music"], a0, b0)) if "music" in xs else float("nan")
        lc = lufs(cut(xs["sfx"], a0, b0)) if "sfx" in xs else float("nan")
        row += [f"{lm:6.1f}", f"{lc:6.1f}", f"{lc - lm:6.1f}"]
        rs = by_scn.get(name, [])
        lay = []
        if rs:
            g = lambda k: max(float(r[k]) for r in rs)
            gears = sorted(set(int(r["gear"]) for r in rs))
            lay.append(f"rpm {min(float(r['rpm']) for r in rs):.0f}-{g('rpm'):.0f} gears {gears[0]}-{gears[-1]}")
            if g("squeal") > 0.05: lay.append(f"squeal {g('squeal'):.2f}")
            if g("skid") > 0.05: lay.append(f"skid {g('skid'):.2f}")
            if g("nitro") > 0.05: lay.append(f"nitro {g('nitro'):.2f}")
            ev = " ".join(r["events"] for r in rs if r["events"])
            if ev: lay.append("events: " + ev)
            lay.append(f"SFX bus peak {g('sfx_peak_db'):.0f} dB, music bus peak {g('music_peak_db'):.0f} dB")
        print(" ".join(row) + "  " + "; ".join(lay))
    whole = xs["all"]
    print(f"\nwhole recording: {len(whole)/SR:.1f} s, sample peak {db(np.abs(whole).max()):.2f} dBFS, samples above -1 dBFS: {int((np.abs(whole) > 10 ** (-1 / 20)).sum())}, above -0.1 dBFS: {int((np.abs(whole) > 10 ** (-0.1 / 20)).sum())}")
    if a.pitch:
        x = wav(a.pitch)
        segs = segments(a.pitch)
        fr = frames(a.pitch)
        print("\nengine pitch (stand-in tones: output firing frequency x 30 should equal the simulated rpm)")
        for name in ("free_rev", "launch_full_throttle", "coast", "full_throttle_cruise", "nitro"):
            s = [t for t in segs if t[0] == name]
            if not s:
                continue
            _, a0, b0 = s[0]
            tr = f0_track(cut(x, a0, b0)) * 30.0
            rpm = np.array([float(r["rpm"]) for r in fr if r["scenario"] == name])
            t_rpm = np.interp(np.arange(len(tr)) * 0.04 * FPS, np.arange(len(rpm)), rpm)
            ok = ~np.isnan(tr)
            err = np.abs(tr[ok] - t_rpm[ok]) / t_rpm[ok]
            steps = np.abs(np.diff(tr[ok]))
            sim_steps = np.abs(np.diff(t_rpm[ok]))
            # A jump in the output that the simulation does not have.
            unexplained = int(((steps > 250) & (sim_steps < 120)).sum())
            print(f"  {name:22s} tracked {np.nanmin(tr):5.0f}-{np.nanmax(tr):5.0f} rpm vs simulated {rpm.min():5.0f}-{rpm.max():5.0f}; median error {100*np.median(err):.1f}%, 95th pct {100*np.percentile(err,95):.1f}%; largest step per 40 ms {steps.max() if len(steps) else 0:.0f} rpm (simulation {sim_steps.max() if len(sim_steps) else 0:.0f}); jumps the simulation does not have: {unexplained}")
            print("    track every 0.2 s:", " ".join(f"{v:.0f}" for v in tr[::5]))
            print("    sim   every 0.2 s:", " ".join(f"{v:.0f}" for v in t_rpm[::5]))


if __name__ == "__main__":
    main()
