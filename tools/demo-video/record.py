#!/usr/bin/env python3
"""Film a scripted session of the real app in the Simulator, against the real server.

    record.py <plan> <out_dir>

Writes <out_dir>/raw.mp4 (simctl recordVideo) and <out_dir>/events.json: a timestamped log of
every tap/swipe/type, plus `idle` spans (UI settling, compressible) and `wait` spans (renders,
which the editor cuts down to a second of the scan animation). Times are seconds since the
recording's first frame.
"""
import json
import os
import re
import subprocess
import sys
import time

AXE = os.path.expanduser("~/.nvm/versions/node/v22.22.2/lib/node_modules/xcodebuildmcp/bundled/axe")
UDID = os.environ.get("SIM_UDID", "364925EE-28C3-4016-A3EF-DA136F7BE42F")
BUNDLE = "com.clothingonu.app"

# Photo picker grid (iPhone 17 Pro points). Index 0 = newest. The grid's top moves with the
# height of the "Private Access" banner, so it's found from a screenshot at pick time.
PICKER_COLS = [67, 201, 335]
PICKER_ROW_H = 134
SCALE = 3  # pixels per point


def picker_grid_top():
    """Scan a pixel column at the left screen edge: the sheet background is flat until the first
    photo tile starts. Returns the grid's top in points."""
    shot = "/tmp/clothingonu-picker.png"
    subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", "--type=png", shot], capture_output=True, check=True)
    out = subprocess.run(["magick", shot, "-crop", f"1x{874 * SCALE}+{6 * SCALE}+0", "-depth", "8", "txt:-"],
                         capture_output=True, text=True, check=True).stdout
    rows = []
    for line in out.splitlines()[1:]:
        m = re.match(r"0,(\d+): \((\d+),(\d+),(\d+)", line)
        if m:
            rows.append((int(m.group(1)), tuple(int(v) for v in m.group(2, 3, 4))))
    start = 200 * SCALE                      # below the Photos/Collections header
    bg = dict(rows)[start]
    for y, c in rows:
        if y <= start:
            continue
        if sum(abs(a - b) for a, b in zip(c, bg)) > 40:
            # Require it to stay different for a few points (not a hairline).
            ahead = [dict(rows).get(y + k * SCALE) for k in range(1, 6)]
            if all(a and sum(abs(p - q) for p, q in zip(a, bg)) > 25 for a in ahead):
                return y / SCALE
    raise RuntimeError("couldn't find the photo grid in the picker")


class Recorder:
    def __init__(self, out_dir):
        self.out_dir = out_dir
        os.makedirs(out_dir, exist_ok=True)
        self.events = []
        self.proc = None
        self.t0 = None

    # -- recording -------------------------------------------------------------------------
    def start(self):
        raw = os.path.join(self.out_dir, "raw.mp4")
        if os.path.exists(raw):
            os.remove(raw)
        self.proc = subprocess.Popen(
            ["xcrun", "simctl", "io", UDID, "recordVideo", "--codec=h264", "--force", raw],
            stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True)
        # simctl prints "Recording started" once frames are flowing; that's t=0.
        for line in self.proc.stderr:
            if "Recording started" in line:
                break
        self.t0 = time.time()

    def stop(self):
        self.proc.send_signal(subprocess.signal.SIGINT)
        self.proc.wait(timeout=30)
        with open(os.path.join(self.out_dir, "events.json"), "w") as f:
            json.dump({"duration": self.now(), "events": self.events}, f, indent=1)

    def now(self):
        return round(time.time() - self.t0, 3)

    def log(self, **e):
        e.setdefault("t", self.now())
        self.events.append(e)
        return e

    # -- actions ---------------------------------------------------------------------------
    def _axe(self, *args):
        r = subprocess.run([AXE, *args, "--udid", UDID], capture_output=True, text=True)
        out = r.stdout + r.stderr
        if r.returncode != 0:
            raise RuntimeError(f"axe {' '.join(args)} failed: {out.strip()[:200]}")
        return out

    def idle(self, secs, keep=None):
        """Wait for the UI. `keep` = how much of it survives the edit (default: all if short)."""
        start = self.now()
        time.sleep(secs)
        self.log(type="idle", start=start, end=self.now(), keep=keep if keep is not None else min(secs, 0.8))

    def tap(self, x, y, settle=0.9):
        self.log(type="tap", x=x, y=y)
        self._axe("tap", "-x", str(x), "-y", str(y))
        self.idle(settle)

    def tap_id(self, ident, settle=0.9, retries=6):
        for attempt in range(retries):
            t = self.now()
            try:
                out = self._axe("tap", "--id", ident)
            except RuntimeError:
                if attempt == retries - 1:
                    raise
                time.sleep(0.6)
                continue
            m = re.search(r"\(([\d.]+), ([\d.]+)\)", out)
            self.log(type="tap", t=t, x=float(m.group(1)), y=float(m.group(2)), id=ident)
            self.idle(settle)
            return

    def tap_label(self, label, settle=0.9, retries=6):
        for attempt in range(retries):
            t = self.now()
            try:
                out = self._axe("tap", "--label", label)
                break
            except RuntimeError:
                if attempt == retries - 1:
                    raise
                time.sleep(0.5)
        m = re.search(r"\(([\d.]+), ([\d.]+)\)", out)
        self.log(type="tap", t=t, x=float(m.group(1)), y=float(m.group(2)), label=label)
        self.idle(settle)

    def pick(self, index, settle=2.4):
        """Choose a photo in the system picker (index 0 = newest in the library)."""
        for attempt in range(12):            # the picker can still be loading
            try:
                top = picker_grid_top()
                break
            except (RuntimeError, KeyError):
                time.sleep(0.5)
        else:
            raise RuntimeError("photo picker never showed its grid")
        x = PICKER_COLS[index % 3]
        y = top + PICKER_ROW_H / 2 + PICKER_ROW_H * (index // 3)
        self.tap(x, round(y), settle=settle)

    def swipe(self, x1, y1, x2, y2, duration=0.5, settle=0.9):
        self.log(type="swipe", x=x1, y=y1, x2=x2, y2=y2, duration=duration)
        self._axe("swipe", "--start-x", str(x1), "--start-y", str(y1), "--end-x", str(x2), "--end-y", str(y2),
                  "--duration", str(duration))
        self.idle(settle)

    def hold(self, x, y, secs):
        self.log(type="hold", x=x, y=y, duration=secs)
        self._axe("touch", "-x", str(x), "-y", str(y), "--down")
        time.sleep(secs)
        self._axe("touch", "-x", str(x), "-y", str(y), "--up")
        self.idle(0.6)

    def type(self, text, settle=0.6):
        """Type in word-sized chunks so it reads like a person typing."""
        self.log(type="type", text=text)
        for chunk in re.findall(r"\S+\s*", text):
            self._axe("type", chunk)
            time.sleep(0.12)
        self.idle(settle)

    def key_return(self):
        self._axe("key", "40")  # HID usage for Return
        self.idle(0.7)

    def beat(self, name):
        self.log(type="beat", name=name)

    # -- render waits ----------------------------------------------------------------------
    def _count(self, folder):
        data = subprocess.run(["xcrun", "simctl", "get_app_container", UDID, BUNDLE, "data"],
                              capture_output=True, text=True).stdout.strip()
        path = os.path.join(data, "Library/Application Support/ClothingOnU", folder)
        return len([f for f in os.listdir(path) if f.endswith(".jpg")]) if os.path.isdir(path) else 0

    def wait_files(self, folder, target, label, timeout=240):
        """Block until `folder` holds `target` JPEGs: the render landed. Logged as a cuttable wait."""
        start = self.now()
        deadline = time.time() + timeout
        while self._count(folder) < target:
            if time.time() > deadline:
                raise TimeoutError(f"{label}: still waiting after {timeout}s")
            time.sleep(0.25)
        self.log(type="wait", label=label, start=start, end=self.now())
        self.idle(1.2, keep=1.2)  # let the reveal animation play
        return self.now()

    def looks(self):
        return self._count("looks")


def launch(reset=True):
    subprocess.run(["xcrun", "simctl", "terminate", UDID, BUNDLE], capture_output=True)
    args = ["xcrun", "simctl", "launch", UDID, BUNDLE] + (["-resetLibrary", "YES"] if reset else [])
    subprocess.run(args, capture_output=True, check=True)
    time.sleep(3.5)


# ======================================================================================
# Plans. Each assumes prep_sim.sh loaded the listed media (oldest -> newest).
# ======================================================================================

def onboarding(r, front_idx, face_idx, build=None, height_scroll=0):
    r.beat("intro")
    r.idle(4.5, keep=4.5)                      # let the demo animation play
    r.tap_id("onboarding.start", settle=1.2)
    r.beat("body")
    if height_scroll:
        r.swipe(201, 330, 201, 330 - height_scroll, duration=0.6, settle=0.8)
    if build:
        r.tap_id(f"build.{build}", settle=0.9)
    r.tap_id("body.continue", settle=1.2)
    r.beat("photos")
    r.tap_id("photo.front", settle=1.0)
    r.tap_label("Choose from library", settle=2.6)
    r.pick(front_idx, settle=2.0)
    r.tap_id("photo.face", settle=1.0)
    r.tap_label("Choose from library", settle=2.6)
    r.pick(face_idx, settle=2.0)
    r.beat("model")
    r.tap_id("photos.continue", settle=0.5)
    r.wait_files("avatar", 1, "avatar")
    r.idle(1.8, keep=1.8)                      # "Is this you?"
    r.beat("accept")
    r.tap_id("avatar.accept", settle=1.8)


def add_garment(r, pin, picker_idx, crop=None):
    for attempt in range(3):
        r.tap_id(f"pin.{pin}", settle=1.0)
        try:
            r.tap_label("Choose from library", settle=2.6, retries=4)
            break
        except RuntimeError:
            if attempt == 2:
                raise
    r.pick(picker_idx, settle=2.2)
    if crop:
        r.swipe(*crop, duration=0.8, settle=0.8)
    r.tap(353, 100, settle=1.4)                # "Add"


def note(r, text):
    r.tap_id("note.toggle", settle=0.8)
    r.type(text)
    r.key_return()


def try_on(r):
    before = r.looks()
    r.tap_id("tryon.button", settle=0.3)
    r.wait_files("looks", before + 1, "tryon")
    return before


def turnaround(r, before):
    r.wait_files("looks", before + 4, "angles")
    for _ in range(3):
        r.swipe(300, 330, 218, 331, duration=0.45, settle=1.3)
    r.idle(0.8, keep=0.8)
    r.swipe(90, 330, 330, 331, duration=0.5, settle=1.3)   # back to the front


def v1_full(r):
    """Drake: full onboarding → jacket (cropped) + jeans + note → try on → turnaround → compare.
    Media: jeans, arc, drake_face, drake_front  => newest-first 0 front, 1 face, 2 arc, 3 jeans."""
    launch()
    r.start()
    onboarding(r, front_idx=0, face_idx=1)
    r.beat("add")
    add_garment(r, "outer", 2, crop=(386, 598, 140, 572))
    add_garment(r, "bottom", 3)
    r.beat("note")
    note(r, "leave the jacket unzipped with a white tee under")
    r.beat("tryon")
    before = try_on(r)
    r.idle(2.0, keep=2.0)
    r.beat("angles")
    turnaround(r, before)
    r.beat("compare")
    r.hold(201, 360, 1.8)
    r.idle(1.0, keep=1.0)
    r.stop()


def v2_hood(r):
    """Drake's existing model: jacket only, 'hood up'. Run after v1 (same library, no reset)."""
    launch(reset=False)
    # Off camera: clear the outfit left over from v1.
    subprocess.run([AXE, "tap", "--label", "More", "--udid", UDID], capture_output=True)
    time.sleep(1.0)
    subprocess.run([AXE, "tap", "--label", "Clear outfit", "--udid", UDID], capture_output=True)
    time.sleep(1.0)
    # "Clear outfit" is disabled when the outfit is already empty, leaving the menu open: dismiss it.
    subprocess.run([AXE, "tap", "-x", "40", "-y", "93", "--udid", UDID], capture_output=True)
    time.sleep(2.0)
    r.start()
    r.beat("start")
    r.idle(1.5, keep=1.5)
    r.beat("add")
    add_garment(r, "outer", 2, crop=(386, 598, 140, 572))
    r.beat("note")
    note(r, "put the hood up")
    r.beat("tryon")
    before = try_on(r)
    r.idle(1.5, keep=1.5)
    r.beat("angles")
    turnaround(r, before)
    r.stop()


def v_persona(front_idx, face_idx, build, garments, note_text=None, height_scroll=0):
    """Generic: onboarding for a new persona, then garments [(pin, picker_idx, crop)], try on, turn."""
    def plan(r):
        launch()
        r.start()
        onboarding(r, front_idx, face_idx, build=build, height_scroll=height_scroll)
        r.beat("add")
        for pin, idx, crop in garments:
            add_garment(r, pin, idx, crop)
        if note_text:
            r.beat("note")
            note(r, note_text)
        r.beat("tryon")
        before = try_on(r)
        r.idle(1.8, keep=1.8)
        r.beat("angles")
        turnaround(r, before)
        r.beat("compare")
        r.hold(201, 360, 1.8)
        r.idle(1.0, keep=1.0)
        r.stop()
    return plan


def v6_colours(r):
    """Drake's model: black stripes, then brown stripes; compare in Looks.
    Run after adding [black_crop, brown_crop] to the library => 0 brown, 1 black."""
    launch(reset=False)
    subprocess.run([AXE, "tap", "--label", "More", "--udid", UDID], capture_output=True)
    time.sleep(1.0)
    subprocess.run([AXE, "tap", "--label", "Clear outfit", "--udid", UDID], capture_output=True)
    time.sleep(1.0)
    # "Clear outfit" is disabled when the outfit is already empty, leaving the menu open: dismiss it.
    subprocess.run([AXE, "tap", "-x", "40", "-y", "93", "--udid", UDID], capture_output=True)
    time.sleep(2.0)
    r.start()
    r.beat("start")
    r.idle(1.2, keep=1.2)
    r.beat("black")
    add_garment(r, "top", 1)
    before = try_on(r)
    r.idle(1.8, keep=1.8)
    r.beat("brown")
    add_garment(r, "top", 0)
    r.tap_id("tryon.button", settle=0.3)
    r.wait_files("looks", before + 5, "tryon2")   # +4 from the first look's angles, +1 front
    r.idle(1.8, keep=1.8)
    r.beat("compare")
    r.tap_id("looks.button", settle=2.2)
    r.idle(1.5, keep=1.5)
    r.tap(296, 640, settle=1.6)                   # the black look (second card)
    r.idle(1.0, keep=1.0)
    r.stop()


PLANS = {
    "v1_full": v1_full,
    "v2_hood": v2_hood,
    # Zendaya. Media: jeans, sweater_black_crop, zendaya_face, zendaya_front => 0 front, 1 face, 2 sweater, 3 jeans
    "v3_zendaya": v_persona(0, 1, "slim", [("top", 2, None), ("bottom", 3, None)], "sleeves pushed up", height_scroll=70),
    # Mustard. Media: vans, sweater_black_crop, mustard_face, mustard_front => 0 front, 1 face, 2 sweater, 3 vans
    "v4_mustard": v_persona(0, 1, "plus", [("top", 2, None), ("shoes", 3, None)], height_scroll=140),
    "v6_colours": v6_colours,
}

if __name__ == "__main__":
    plan, out = sys.argv[1], sys.argv[2]
    rec = Recorder(out)
    try:
        PLANS[plan](rec)
    except Exception:
        if rec.proc and rec.proc.poll() is None:
            rec.stop()
        raise
    print(f"recorded {plan}: {rec.events[-1]['t'] if rec.events else 0:.1f}s, {len(rec.events)} events -> {out}")
