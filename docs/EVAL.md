# Engine evaluation log

`npm run eval -- <case>` (server/scripts/eval.ts) runs the real pipeline: avatar → try-on → side → back.
Test photos and outputs live in `testdata/` (gitignored: they're real people and this repo is public).

Test inputs:
- **People.** Wikimedia Commons, freely licensed:
  - Glenn Francis red-carpet shots (Drake Bell, DJ Mustard)
  - a home "body morphology" set (front + side, fitted tee, face masked)
- **Garments.** Real desktop product-page screenshots with all their clutter:
  - Arc'teryx Beta Jacket: two model photos, 5 colour swatches, a cookie banner
  - Uniqlo Barrel Jeans: four different models, two denim washes
  - Uniqlo striped sweater: black and brown colourways on one page
  - Vans Old Skool (patterned brown)

## 2026-11-14: gemini-3-pro-image, 2K, 3:4

Every call took 20–25 s. No safety blocks, no fallbacks.

| Case | Result |
|---|---|
| Drake Bell: Arc'teryx jacket + Uniqlo jeans, note "leave the jacket unzipped with a plain white t-shirt under" | ✅ Strong likeness. Jacket colour, logo, pit zips, cuffs and hood lining are exact. Unzipped over a white tee as asked. It picked the light wash even though the page also showed dark denim. Side and back views keep the outfit, the person and the framing. |
| Daniel (slim, masked face, front + side photos): jacket, note "put the hood up" | ✅ Hood up and consistent in all three views. Body proportions kept. The face is invented because the reference is masked, so **the app must ask for a clear face photo**. |
| DJ Mustard (plus build): striped sweater + patterned Vans | ✅ Body **not** slimmed. Vans pattern right. ❌ Chose the **brown** sweater although the page had **black** selected. |
| → same, after a prompt rule for the selected colourway | ❌ Still brown. "Color: 09 BLACK" is tiny in the screenshot. |
| → same, screenshot cropped to the black product photo | ✅ Black sweater. Neckline drifted from V to crew (the model in the crop wears a collared shirt under it). |

### Decisions from this round
- The app offers an optional crop for every garment screenshot, with the tip "page shows several colours? crop to the one you want".
- The app strongly asks for a clear face photo in onboarding. Identity comes mostly from the face.
- Pro is fast enough (~22 s) to be the default. The fast model stays as the automatic fallback.

## 2026-11-14: in-app, Simulator against production (clothingonu.vercel.app)

Driven through the real UI: photo picker, pins, crop sheet, note, angle bar, drag and hold.

| Step | Result |
|---|---|
| Onboarding (Drake Bell front + face photo) → model | ✅ ~30 s. Strong likeness. |
| Jacket (cropped) + jeans, note "leave the jacket unzipped with a plain white t-shirt under" | ✅ Matches the note. ¾/side/back rendered in parallel (~25 s). Drag-to-turn and hold-to-compare work. |
| Fresh model, jacket + jeans + Vans, no note | ✅ The jacket stays open over the base grey tee (layering rule). Vans pattern and colour are exact. |

Bugs found this way and fixed (see git log): a stage double-offset while rendering; a Vision failure in the Simulator reported as "no person"; the panel covering the feet; and a production outage when a git push deployed the repo root. Vercel's root directory is now `server`.
