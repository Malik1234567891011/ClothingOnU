"""Scripts for each demo video: voice, music, and per-beat line + headline.

Beat names match the `beat` marks logged by record.py. "On-You" is spelled phonetically in
voice lines so the voice doesn't read "OnU" as letters; captions use the real name.
"""

CHRIS = "iP95p4xoKVk53GoZ742B"    # charming, down-to-earth (m)
JESSICA = "cgSgspJ2msm6clMCkdW9"  # playful, warm (f)
LAURA = "FGY2WhTYpPnrIDTdsKH5"    # social-media enthusiast (f)
BRIAN = "nPczCjzI2devNBz1zQrb"    # deep, resonant (m)
WILL = "bIHbv24MWmeRgasZH58o"     # relaxed optimist (m)

POP = ("Warm minimal electronic pop instrumental for a premium fashion app demo. Soft plucked synths, airy pads, "
       "light four-on-the-floor kick, finger snaps, optimistic, clean mix, 112 bpm, no vocals.")

VIDEOS = {
    # 1. The full tour: onboarding to turnaround.
    "v1_full": {
        "voice": CHRIS,
        "music": POP,
        "beats": [
            {"beat": "intro", "caption": "Will it look good on you?",
             "vo": "Ever bought something online… and it looked totally different on you?"},
            {"beat": "body", "caption": "Your height & build", "vo": "On-You fixes that. Tell it your height and build,"},
            {"beat": "photos", "caption": "A couple of photos. Once.", "vo": "add a couple of photos, just once,"},
            {"beat": "model", "caption": "Meet your model", "vo": "and it builds a model of… you."},
            {"beat": "accept", "min": 1.2},
            {"beat": "add", "caption": "Screenshot anything", "vo": "Now screenshot anything, from any store, and drop it right on."},
            {"beat": "note", "caption": "Style it your way", "vo": "Want it styled a certain way? Just say so."},
            {"beat": "tryon", "caption": "That's you.", "vo": "Hit try it on… and that's you. Wearing it."},
            {"beat": "angles", "caption": "Every angle", "vo": "Spin around. Check the side… and the back."},
            {"beat": "compare", "caption": "Before & after", "vo": "Before… and after. See it on you, before you buy it."},
        ],
    },
    # 2. One jacket, one instruction.
    "v2_hood": {
        "voice": JESSICA,
        "music": ("Playful lo-fi house instrumental, bright Rhodes chords, soft vinyl texture, bouncy bass, "
                  "relaxed and stylish, 118 bpm, no vocals."),
        "beats": [
            {"beat": "start", "caption": "Found a jacket?", "vo": "Found a jacket you love?"},
            {"beat": "add", "caption": "Drop it on", "vo": "Screenshot it, and drop it on your model."},
            {"beat": "note", "caption": "“Put the hood up”", "vo": "Then tell it how you'd wear it. Hood up."},
            {"beat": "tryon", "caption": "There you are.", "vo": "A few seconds later… there you are."},
            {"beat": "angles", "caption": "Every angle", "vo": "Side. Back. Every angle, before you check out."},
        ],
        "tagline": "Try it on before you check out.",
    },
    # 3. Mix stores: a sweater from one, jeans from another.
    "v3_zendaya": {
        "voice": LAURA,
        "music": ("Upbeat glossy pop instrumental for a fashion haul video, punchy claps, shimmering synth arps, "
                  "confident and fun, 120 bpm, no vocals."),
        "beats": [
            {"beat": "intro", "caption": "Sound familiar?",
             "vo": "How many times have you returned something… that just didn't look right on you?"},
            {"beat": "body", "caption": "Your size, not a model's", "vo": "On-You shows it on your body first."},
            {"beat": "photos", "caption": "Two photos, one time", "vo": "Two photos. One time."},
            {"beat": "model", "caption": "Your model", "vo": "And your model's ready."},
            {"beat": "accept", "min": 1.0},
            {"beat": "add", "caption": "Mix any stores", "vo": "Now add anything. A sweater from one store, jeans from another."},
            {"beat": "note", "caption": "“Sleeves pushed up”", "vo": "Sleeves pushed up? Sure."},
            {"beat": "tryon", "caption": "On you.", "vo": "And just like that… it's on you."},
            {"beat": "angles", "caption": "Front, side, back", "vo": "Front, side, back. All of it."},
            {"beat": "compare", "caption": "Hold for before", "vo": "Hold to see the before. Try before you buy, for real."},
        ],
    },
    # 4. Your body, not a model's.
    "v4_mustard": {
        "voice": BRIAN,
        "music": ("Smooth confident hip-hop instrumental, warm bass, crisp drums, mellow keys, premium and laid back, "
                  "90 bpm, no vocals."),
        "beats": [
            {"beat": "intro", "caption": "Not a model's body.",
             "vo": "Most try-on apps show clothes on a model's body. Not yours."},
            {"beat": "body", "caption": "Your real build", "vo": "On-You starts with your real height and build."},
            {"beat": "photos", "caption": "A couple of photos", "vo": "A couple of photos,"},
            {"beat": "model", "caption": "Your actual shape", "vo": "and that's your model. Your actual shape."},
            {"beat": "accept", "min": 1.0},
            {"beat": "add", "caption": "Add the fit", "vo": "Add a sweater… and some sneakers."},
            {"beat": "tryon", "caption": "How it really fits", "vo": "And see how they really fit. On you."},
            {"beat": "angles", "caption": "Every side", "vo": "From every side."},
            {"beat": "compare", "caption": "Nothing slimmed", "vo": "Nothing slimmed. Nothing faked. Just you, in the clothes."},
        ],
        "tagline": "Your body. Your fit.",
    },
    # 5. 15-second teaser, music only, cut from the v1 recording.
    "v5_teaser": {
        "voice": CHRIS,
        "music": ("Energetic stylish electronic pop instrumental, punchy kick, bright synth stabs, catchy hook, "
                  "builds fast, 124 bpm, no vocals."),
        "music_volume": 0.9,
        "beats": [
            {"beat": "add", "caption": "Screenshot it.", "seconds": 3.4, "skip": 10.0},
            {"beat": "note", "caption": "Say how you'd wear it.", "seconds": 2.6},
            {"beat": "tryon", "caption": "See it on you.", "seconds": 3.2},
            {"beat": "angles", "caption": "From every angle.", "seconds": 3.6},
        ],
    },
    # 6. Which colour?
    "v6_colours": {
        "voice": WILL,
        "music": ("Chill optimistic indie electronic instrumental, soft guitar plucks, warm pads, gentle beat, "
                  "100 bpm, no vocals."),
        "beats": [
            {"beat": "start", "caption": "Black or brown?", "vo": "Can't decide between two colours?"},
            {"beat": "black", "caption": "Try the black", "vo": "Try the black one on first…"},
            {"beat": "brown", "caption": "Then the brown", "vo": "then the brown."},
            {"beat": "compare", "caption": "Keep the one that's you",
             "vo": "Flip between your looks, and keep the one that's actually you."},
        ],
        "tagline": "See it on you before you buy it.",
    },
}
