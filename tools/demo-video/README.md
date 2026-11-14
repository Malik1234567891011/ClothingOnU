# Demo videos

These scripts film the real app in the Simulator against the real server, then cut each recording into a vertical 1080×1920 video:
- render waits removed
- tap ripples drawn where the taps happened
- a headline per beat
- an ElevenLabs v3 voiceover and ElevenLabs music

```sh
./prep_sim.sh dark <media oldest→newest...>   # wipe the Simulator, load exactly these photos
python3 record.py v1_full ../../testdata/videos/v1     # film (writes raw.mp4 + events.json)
python3 edit.py v1_full ../../testdata/videos/v1 out.mp4  # cut, voice, music, compose
```

- **Plans** (what gets tapped) live in `record.py`. **Scripts** (voice lines, headlines, music prompts) live in `scripts.py`.
- **Timing.** The edit is timed around the voice. A beat is never shorter than its line: the editor keeps more of the scan animation, then holds the last frame. Squeezing TTS to fit makes it sound robotic.
- **Photo picker.** The picker grid's position is found from a screenshot at pick time, because the "Private Access" banner's height varies.
- **Cost.** Each film costs real renders, about $0.71 for a new person (model + one look) or $0.57 per extra look. The ElevenLabs key is read from `~/seedance-plotbreak/.env.local`.
- **Outputs.** Videos go to `testdata/` (gitignored). They show real people's faces and are for internal demos only.
