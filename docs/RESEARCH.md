# Research notes (Nov 2026)

What I checked before writing code, and what it decided.

## 1. The try-on engine

There are two families of model.

| Family | Examples | Good at | Can't do |
|---|---|---|---|
| Dedicated try-on | FASHN v1.6 ($0.075), Kling Kolors ($0.07), fal image-apps-v2 ($0.04), Leffa | Keeps the person and the garment print faithful. Fast (5–17 s). | No text instructions. One garment per call. No new camera angles. Kling caps at 768×1024. Leffa "changed her face". |
| Prompt-driven multi-reference image models | Gemini 3 Pro Image "Nano Banana Pro", Nano Banana 2 / 2.1, GPT Image 2.5, FLUX.2 | Several reference images at once, text instructions ("untucked", "hood up"), re-posing and re-viewing a subject | Can drift identity (FLUX.2 changed hair and framing in Fuser's test) |

The product needs three things:

- several garments in one go
- optional instructions ("leave it unzipped with a black tee under")
- side and back views

Only the second family does all three. Fuser's Sep 2026 hands-on test found that GPT Image 2.5 and Nano Banana 2 followed styling instructions and held the face. FASHN was the most literal of the dedicated models, but it ignored styling (it tucked the shirt in).

**Decision: Gemini image models, behind a server-side provider interface.**

- **Nano Banana Pro (`gemini-3-pro-image`)** is the quality model, about $0.134 per 1K/2K image. It takes up to 5 character images, 6 object images and 3 style references. That maps cleanly onto our inputs: the user's photos are the character images and the garment screenshots are the objects. It also thinks before drawing, which helps it follow layering instructions.
- **Nano Banana 2.1 (`gemini-nano-banana-2.1`)** is the cheap, fast fallback, about $0.05 at 2K. It takes 4 character images and 10 object images.
- Every output carries a SynthID watermark, which is fine for a personal try-on.

Sources:
- https://fuser.studio/articles/best-ai-virtual-try-on
- https://fal.ai/learn/tools/best-virtual-try-on-apis-2026
- https://aistudio.google.com/docs/image-generation
- https://aistudio.google.com/docs/pricing

## 2. 3D model vs. images

A real 3D avatar would mean two things:

1. Reconstructing a body mesh from a few photos. That is feasible with SMPL-X fitting or Gaussian avatars.
2. Simulating an arbitrary garment from a single 2D screenshot onto that mesh. That is **not** feasible at photoreal quality today. There is no garment pattern, no fabric parameters and no back of the garment.

Every shipping consumer try-on product gives you either a game-like avatar wearing approximate clothes or 2D generation. Apparel 3D (CLO and similar) needs the brand's own pattern files.

So the 360° experience is done generatively:

- Onboarding captures front, side and back photos, so the model knows the user's real body from each direction.
- After the front render, we generate the same outfit from ¾, side and back. Each view is anchored on the front result so the clothes stay consistent.
- Dragging on the image scrubs between the views with a parallax crossfade, so it feels like turning.

The user can honestly answer "does this look good from behind", which is the actual job.

## 3. Why try-on apps disappoint (reviews and industry pieces)

- **Trust.** Users don't believe the result. *Our answer:* it's your face, from your photos, with a before/after hold-to-compare. We never show a "fit score" we can't back up.
- **The garment looks pasted on** ("a draped rectangle"). *Our answer:* prompt for natural drape, real fabric weight, consistent lighting and proper layering.
- **Body mismatch.** Slimmer or idealised bodies hurt trust and are an ethics problem. *Our answer:* references in fitted clothing, plus height and build passed as explicit constraints: "do not slim, do not idealise".
- **Too few items supported / tied to one store.** *Our answer:* any screenshot from any shop.
- **Bugs and slow support.** *Our answer:* a small surface, done well.

## 4. Onboarding

- The median completion rate falls below about 60% once an onboarding flow passes 5 screens (UXCam via vendor blog). Keep it to **4 screens**:
  1. Demo
  2. Height and build
  3. Photos
  4. Meet-your-model
- Show the value inside 60 seconds. The first screen is a looping demo of a fictional model getting dressed, not a feature list.
- Ask for camera permission **in context**: at the moment the user taps "Take photo", never on launch. The photo library uses `PhotosPicker`, which needs no permission at all.
- Capture apps that work show the **required pose, framing and lighting at the moment of capture**, plus a privacy line. So each photo slot shows a pose silhouette and one-line tips. On-device Vision body-pose detection then **checks every photo** ("your feet are cut off", "two people detected") before anything is uploaded. That makes the photos cheap to fix and saves a bad avatar.
- Build is chosen from tappable cards with neutral wording (Slim, Lean, Average, Athletic, Muscular, Broad, Curvy, Plus). That's faster than a dropdown on a phone, and kinder than "chunky".

## 5. UI direction (iOS 26)

- **Liquid Glass belongs on the navigation and control layer only**: toolbars, floating buttons and the try-on bar. Content stays crisp. Avoid glass on content, avoid stacking glass without a `GlassEffectContainer`, use `.clear` sparingly, and keep tints low-opacity except on the primary action.
- The photo of *you* is the hero. The home screen is a full-bleed portrait, a few hotspot pins and one primary action. No tab bar clutter: looks history is a sheet.
- **What makes apps look bad**, and what we do instead:
  - inconsistent corner radii and spacing → one spacing scale and one radius scale
  - more than 2 type families → system SF Pro plus SF Pro Rounded for numerals only
  - gradients everywhere → a neutral warm-grey canvas and one accent
  - spinners with no context → a "scan" shimmer over your own photo, with progress copy
  - modals stacked on modals
  - tap targets under 44 pt
  - ignoring Dynamic Type and dark mode → support both
  - text over busy images without a scrim → always scrimmed
- **Motion is short and physical**: spring transitions, a wipe reveal of the result, and haptics on success.
