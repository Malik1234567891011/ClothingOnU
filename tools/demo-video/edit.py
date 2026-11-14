#!/usr/bin/env python3
"""Turn a raw Simulator recording + event log into a finished vertical demo video.

    edit.py <video_name> <recording_dir> <out.mp4>

Pipeline:
  1. Cut: render waits shrink to ~1.8 s of the scan animation; idle UI time shrinks to `keep`.
  2. Voice: one ElevenLabs v3 take of the whole script (natural flow), split per line using
     the character timestamps. Each beat is at least as long as its line: if the cut footage is
     shorter, we keep more of the scan animation, then hold the last frame. The edit is timed
     around the voice, never the other way round (squeezing TTS makes it sound robotic).
  3. Picture: tap ripples where the taps happened, phone with rounded corners on a brand
     background, one headline per beat, an end card.
  4. Sound: ElevenLabs music bed, ducked under the voice, loudness-normalised to -14 LUFS.
"""
import base64
import hashlib
import json
import os
import subprocess
import sys
import urllib.request

from scripts import VIDEOS

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_SERIF = "/System/Library/Fonts/NewYork.ttf"
FONT_SANS = "/System/Library/Fonts/SFNS.ttf"
W, H = 1080, 1920                 # output canvas
PHONE_W = 760                     # working width of the screen recording
SIM_POINTS_W = 402                # iPhone 17 Pro width in points
PT = PHONE_W / SIM_POINTS_W       # points -> working pixels
PHONE_H_OUT = 1560                # phone height on the canvas
PHONE_Y = 300
FPS = 30
BG = "#F4F1EC"
INK = "#1B1A19"


def sh(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise SystemExit(f"command failed ({r.returncode}): {' '.join(cmd[:6])}...\n{r.stderr[-2000:]}")
    return r


def eleven_key():
    for line in open(os.path.expanduser("~/seedance-plotbreak/.env.local")):
        if line.startswith("ELEVENLABS_API_KEY="):
            return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("ELEVENLABS_API_KEY not found")


def eleven(path, body, accept_json=False):
    req = urllib.request.Request("https://api.elevenlabs.io" + path, data=json.dumps(body).encode(),
                                 headers={"xi-api-key": eleven_key(), "content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        data = r.read()
    return json.loads(data) if accept_json else data


def duration(path):
    return float(sh(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path]).stdout)


# ---------------------------------------------------------------------------------------
# Voice
# ---------------------------------------------------------------------------------------

def voice_lines(spec, work):
    """Return {beat: (wav_path, seconds)} for beats that have a line. Cached by script hash."""
    lines = [(b["beat"], b["vo"]) for b in spec["beats"] if b.get("vo")]
    if not lines:
        return {}
    text = "\n\n".join(t for _, t in lines)
    key = hashlib.sha1((spec["voice"] + text).encode()).hexdigest()[:10]
    take = os.path.join(work, f"vo-{key}.json")
    if not os.path.exists(take):
        d = eleven(f"/v1/text-to-speech/{spec['voice']}/with-timestamps",
                   {"text": text, "model_id": "eleven_v3", "voice_settings": {"stability": 0.5}}, accept_json=True)
        json.dump(d, open(take, "w"))
    d = json.load(open(take))
    mp3 = os.path.join(work, f"vo-{key}.mp3")
    open(mp3, "wb").write(base64.b64decode(d["audio_base64"]))
    starts = d["alignment"]["character_start_times_seconds"]
    ends = d["alignment"]["character_end_times_seconds"]

    out, pos = {}, 0
    for beat, line in lines:
        i = text.index(line, pos)
        j = i + len(line) - 1
        pos = j + 1
        a, b = max(0.0, starts[i] - 0.06), ends[j] + 0.12
        wav = os.path.join(work, f"vo-{key}-{beat}.wav")
        sh(["ffmpeg", "-y", "-v", "error", "-i", mp3, "-ss", f"{a:.3f}", "-to", f"{b:.3f}",
            "-af", "afade=t=in:d=0.03,areverse,afade=t=in:d=0.08,areverse", "-ar", "44100", "-ac", "2", wav])
        out[beat] = (wav, b - a)
    return out


def music(spec, work, seconds):
    key = hashlib.sha1((spec["music"] + str(int(seconds))).encode()).hexdigest()[:10]
    path = os.path.join(work, f"music-{key}.mp3")
    if not os.path.exists(path):
        open(path, "wb").write(eleven("/v1/music", {"prompt": spec["music"], "model_id": "music_v1",
                                                     "music_length_ms": int((seconds + 2) * 1000)}))
    return path


# ---------------------------------------------------------------------------------------
# Timeline
# ---------------------------------------------------------------------------------------

def plan_timeline(spec, events, raw_len, vo):
    """Build output segments: [{'a','b','speed'} | {'freeze_at','dur'}] plus per-beat out ranges."""
    # An action (tap/pick) can itself block while the UI loads (e.g. the photo picker). Anything
    # after the first 0.35 s of an action belongs to the idle that follows it.
    ev = [dict(e) for e in events]
    for prev, cur in zip(ev, ev[1:]):
        if cur["type"] == "idle" and prev["type"] in ("tap", "swipe", "type") and cur["start"] - prev["t"] > 0.35:
            cur["start"] = prev["t"] + 0.35
    # Cuttable spans: [start, end, cut_from, kind]. cut_from = where the cut begins by default.
    cuts = []
    for e in ev:
        if e["type"] == "idle" and e["end"] - e["start"] > e["keep"] + 0.05:
            cuts.append([e["start"] + e["keep"], e["end"], "idle"])
        if e["type"] == "wait" and e["end"] - e["start"] > 2.4:
            cuts.append([e["start"] + 1.8, e["end"] - 0.5, "wait"])

    beat_marks = [e for e in ev if e["type"] == "beat"]
    wanted = {b["beat"]: b for b in spec["beats"]}
    segments, beat_out, t_out = [], {}, 0.0

    for i, bm in enumerate(beat_marks):
        bs = bm["t"]
        be = beat_marks[i + 1]["t"] if i + 1 < len(beat_marks) else raw_len
        b = wanted.get(bm["name"])
        if b is None:      # beat not used in this cut
            continue
        bs += b.get("skip", 0.0)   # start later into the beat (e.g. skip a loading sheet)
        mine = [[max(c[0], bs), min(c[1], be), c[2]] for c in cuts if c[1] > bs and c[0] < be]
        mine = [c for c in mine if c[1] - c[0] > 0.05]
        kept = (be - bs) - sum(c[1] - c[0] for c in mine)

        speed = 1.0
        freeze = 0.0
        if "seconds" in b:  # teaser beats: fixed length, speed up if needed
            target = b["seconds"]
            if kept > target:
                speed = min(kept / target, 3.0)
            else:
                freeze = target - kept
        else:
            need = (vo[b["beat"]][1] + 0.35 + b.get("pad", 0.45)) if b["beat"] in vo else b.get("min", 0)
            deficit = need - kept
            # Give time back from waits first (more scan animation), then idles.
            for kind in ("wait", "idle"):
                for c in mine:
                    if deficit <= 0:
                        break
                    if c[2] == kind:
                        give = min(deficit, c[1] - c[0])
                        c[0] += give
                        deficit -= give
            freeze = max(0.0, deficit)

        beat_start_out = t_out
        cursor = bs
        for c in sorted(mine):
            if c[0] > cursor:
                segments.append({"a": cursor, "b": c[0], "speed": speed})
                t_out += (c[0] - cursor) / speed
            cursor = max(cursor, c[1])
        if be > cursor:
            segments.append({"a": cursor, "b": be, "speed": speed})
            t_out += (be - cursor) / speed
        if freeze > 0.02:
            segments.append({"freeze_at": be - 0.04, "dur": freeze})
            t_out += freeze
        beat_out[b["beat"]] = (beat_start_out, t_out)
    return segments, beat_out, t_out


def raw_to_out(t, segments):
    out = 0.0
    for s in segments:
        if "freeze_at" in s:
            out += s["dur"]
            continue
        if s["a"] <= t <= s["b"]:
            return out + (t - s["a"]) / s["speed"]
        out += (s["b"] - s["a"]) / s["speed"]
    return None


# ---------------------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------------------

def text_png(work, name, text, font, size, color, w, h):
    """Centered single-line text on a transparent canvas (ImageMagick has fonts; this ffmpeg lacks drawtext)."""
    path = os.path.join(work, f"{name}.png")
    sh(["magick", "-size", f"{w}x{h}", "xc:none", "-font", font, "-pointsize", str(size), "-fill", color,
        "-gravity", "center", "-annotate", "+0+0", text, path])
    return path


def make_assets(work):
    ripple = os.path.join(work, "ripple.png")
    if not os.path.exists(ripple):
        sh(["magick", "-size", "84x84", "xc:none", "-fill", "rgba(255,255,255,0.45)", "-stroke", "rgba(255,255,255,0.95)",
            "-strokewidth", "4", "-draw", "circle 42,42 42,6", ripple])
    bg = os.path.join(work, "bg.png")
    if not os.path.exists(bg):
        sh(["magick", "-size", f"{W}x{H}", f"radial-gradient:#FBF9F6-#E9E3DA", bg])
    phone_w = int(round(PHONE_H_OUT * PHONE_W / 1652 / 2) * 2)
    mask = os.path.join(work, "mask.png")
    if not os.path.exists(mask):
        sh(["magick", "-size", f"{phone_w}x{PHONE_H_OUT}", "xc:black", "-fill", "white", "-draw",
            f"roundrectangle 0,0 {phone_w - 1},{PHONE_H_OUT - 1} 62,62", mask])
    shadow = os.path.join(work, "shadow.png")
    if not os.path.exists(shadow):
        sh(["magick", "-size", f"{phone_w + 160}x{PHONE_H_OUT + 160}", "xc:none", "-fill", "rgba(40,30,20,0.38)", "-draw",
            f"roundrectangle 80,96 {phone_w + 79},{PHONE_H_OUT + 95} 62,62", "-blur", "0x26", shadow])
    return ripple, bg, mask, shadow, phone_w


def render(name, rec_dir, out_path):
    spec = VIDEOS[name]
    work = os.path.join(rec_dir, "work")
    os.makedirs(work, exist_ok=True)
    ev = json.load(open(os.path.join(rec_dir, "events.json")))
    raw = os.path.join(rec_dir, "raw.mp4")
    raw_len = duration(raw)

    cfr = os.path.join(work, "cfr.mp4")
    if not os.path.exists(cfr):
        sh(["ffmpeg", "-y", "-v", "error", "-i", raw, "-vf", f"fps={FPS},scale={PHONE_W}:-2:flags=lanczos",
            "-c:v", "libx264", "-crf", "15", "-preset", "fast", "-an", cfr])

    vo = voice_lines(spec, work)
    segments, beat_out, total = plan_timeline(spec, ev["events"], raw_len, vo)
    ripple, bg, mask, shadow, phone_w = make_assets(work)

    # ---- 1. trimmed phone video with tap ripples ----
    f = []
    labels = []
    for k, s in enumerate(segments):
        if "freeze_at" in s:
            f.append(f"[0:v]trim=start={s['freeze_at']:.3f}:duration=0.04,setpts=PTS-STARTPTS,"
                     f"tpad=stop_mode=clone:stop_duration={s['dur']:.3f},trim=duration={s['dur']:.3f}[s{k}]")
        else:
            f.append(f"[0:v]trim=start={s['a']:.3f}:end={s['b']:.3f},setpts=(PTS-STARTPTS)/{s['speed']:.4f}[s{k}]")
        labels.append(f"[s{k}]")
    f.append("".join(labels) + f"concat=n={len(labels)}:v=1:a=0,fps={FPS}[cut]")

    last = "cut"
    n = 0
    for e in ev["events"]:
        if e["type"] not in ("tap", "swipe", "hold"):
            continue
        t = raw_to_out(e["t"], segments)
        if t is None or t > total:
            continue
        d = {"tap": 0.32, "swipe": e.get("duration", 0.5), "hold": e.get("duration", 1.0)}[e["type"]]
        x1, y1 = e["x"] * PT - 42, e["y"] * PT - 42
        if e["type"] == "swipe":
            x2, y2 = e["x2"] * PT - 42, e["y2"] * PT - 42
            xe = f"{x1:.1f}+({x2 - x1:.1f})*(t-{t:.3f})/{d:.3f}"
            ye = f"{y1:.1f}+({y2 - y1:.1f})*(t-{t:.3f})/{d:.3f}"
        else:
            xe, ye = f"{x1:.1f}", f"{y1:.1f}"
        f.append(f"[{last}][1:v]overlay=x='{xe}':y='{ye}':enable='between(t,{t:.3f},{t + d:.3f})'[r{n}]")
        last = f"r{n}"
        n += 1

    # ---- 2. compose on the canvas ----
    f.append(f"[{last}]scale={phone_w}:{PHONE_H_OUT}:flags=lanczos,format=rgba[ph]")
    f.append("[ph][3:v]alphamerge[phr]")
    f.append(f"[2:v]loop=-1:size=1,trim=duration={total:.3f},fps={FPS},setpts=PTS-STARTPTS[bgv]")
    f.append(f"[bgv][4:v]overlay=x={(W - phone_w) // 2 - 80}:y={PHONE_Y - 80}[bgs]")
    f.append(f"[bgs][phr]overlay=x={(W - phone_w) // 2}:y={PHONE_Y}[comp]")
    last = "comp"
    cap_inputs = []   # extra -loop inputs for caption PNGs, indices from 5
    for i, b in enumerate(spec["beats"]):
        if not b.get("caption") or b["beat"] not in beat_out:
            continue
        a, z = beat_out[b["beat"]]
        png = text_png(work, f"cap-{i}", b["caption"], FONT_SERIF, 74, INK, W, 200)
        idx = 5 + len(cap_inputs) // 6   # each caption adds 6 args (-loop 1 -t d -i png)
        cap_inputs += ["-loop", "1", "-t", f"{z - a:.3f}", "-i", png]
        f.append(f"[{idx}:v]format=rgba,fade=t=in:st=0:d=0.25:alpha=1,fade=t=out:st={max(0, z - a - 0.2):.3f}:d=0.2:alpha=1,"
                 f"setpts=PTS+{a:.3f}/TB[cap{i}]")
        f.append(f"[{last}][cap{i}]overlay=x=0:y=110:eof_action=pass[c{i}]")
        last = f"c{i}"
    f.append(f"[{last}]format=yuv420p[vmain]")

    main = os.path.join(work, "main.mp4")
    sh(["ffmpeg", "-y", "-v", "error", "-i", cfr, "-i", ripple, "-i", bg, "-i", os.path.join(work, "mask.png"), "-i", shadow,
        *cap_inputs, "-filter_complex", ";".join(f), "-map", "[vmain]", "-c:v", "libx264", "-crf", "18", "-preset", "medium",
        "-r", str(FPS), main])

    # ---- 3. end card ----
    card = os.path.join(work, "card.mp4")
    card_len = 2.6
    logo = text_png(work, "card-logo", "OnU", FONT_SERIF, 220, INK, W, 300)
    tag = text_png(work, "card-tag", spec.get("tagline", "See it on you before you buy it."), FONT_SANS, 52, "#6E6A65", W, 120)
    sh(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-i", bg, "-loop", "1", "-i", logo, "-loop", "1", "-i", tag,
        "-filter_complex",
        f"[0:v]trim=duration={card_len},fps={FPS}[b];"
        f"[1:v]format=rgba,trim=duration={card_len},fade=t=in:st=0:d=0.4:alpha=1[l];"
        f"[2:v]format=rgba,trim=duration={card_len},fade=t=in:st=0.35:d=0.4:alpha=1[t];"
        f"[b][l]overlay=x=0:y={H // 2 - 300}[bl];[bl][t]overlay=x=0:y={H // 2 + 20},format=yuv420p[v]",
        "-map", "[v]", "-t", str(card_len), "-c:v", "libx264", "-crf", "18", "-r", str(FPS), card])
    video_len = total + card_len

    # ---- 4. audio ----
    inputs, af, vo_labels = [], [], []
    for b in spec["beats"]:
        if b["beat"] in vo and b["beat"] in beat_out:
            wav, _ = vo[b["beat"]]
            start = beat_out[b["beat"]][0] + b.get("lead", 0.35)
            inputs += ["-i", wav]
            idx = len(inputs) // 2 - 1
            ms = int(start * 1000)
            af.append(f"[{idx}:a]adelay={ms}|{ms}[v{idx}]")
            vo_labels.append(f"[v{idx}]")
    mus = music(spec, work, video_len)
    inputs += ["-i", mus]
    mi = len(inputs) // 2 - 1
    fade_at = max(0, video_len - 1.8)
    music_vol = spec.get("music_volume", 0.32 if vo_labels else 0.8)
    af.append(f"[{mi}:a]atrim=0:{video_len:.3f},volume={music_vol},afade=t=in:d=0.6,afade=t=out:st={fade_at:.3f}:d=1.8[m]")
    if vo_labels:
        af.append("".join(vo_labels) + f"amix=inputs={len(vo_labels)}:normalize=0,apad=whole_dur={video_len:.3f},asplit=2[vo1][vo2]")
        af.append("[m][vo1]sidechaincompress=threshold=0.02:ratio=10:attack=15:release=450[md]")
        af.append("[md][vo2]amix=inputs=2:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11[a]")
    else:
        af.append("[m]loudnorm=I=-14:TP=-1.5:LRA=11[a]")
    audio = os.path.join(work, "audio.m4a")
    sh(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", ";".join(af), "-map", "[a]",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100", audio])

    # ---- 5. mux ----
    lst = os.path.join(work, "concat.txt")
    open(lst, "w").write(f"file '{main}'\nfile '{card}'\n")
    sh(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-i", audio, "-map", "0:v", "-map", "1:a",
        "-c:v", "copy", "-c:a", "copy", "-shortest", "-movflags", "+faststart", out_path])
    print(f"{name}: {video_len:.1f}s -> {out_path}")
    for b in spec["beats"]:
        if b["beat"] in beat_out:
            a, z = beat_out[b["beat"]]
            print(f"  {b['beat']:<9} {a:5.1f}-{z:5.1f}s  {b.get('caption', '')}")


if __name__ == "__main__":
    render(sys.argv[1], sys.argv[2], sys.argv[3])
