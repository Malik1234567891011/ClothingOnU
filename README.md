# ClothingOnU (app name: OnU)

See clothes on **you** before you buy them. Screenshot anything from any store and OnU shows it on your body, from the front, ¾, side and back.

```
ios/      SwiftUI app (iOS 26, Swift 6, XcodeGen)
server/   Render API on Vercel: holds the model key, builds prompts, calls Gemini
docs/     RESEARCH.md (why it's built this way), EVAL.md (real-model test results)
```

## How it works

1. **One-time setup (4 screens).**
   - A looping demo.
   - Height and build.
   - Guided photos: front (required), face and side (recommended), back (optional). Every photo is checked on device with Vision ("your feet are cut off") before it's used.
   - The server turns the photos into your **model**: you, in a plain grey tee, black trousers and white sneakers, in a neutral studio. You confirm it looks like you.
2. **Fitting room.** It shows your model full screen with pins on your head, jacket, top, bottoms, shoes and extras. The pins are placed on your body by Vision.
   - Tap a pin and pick a screenshot.
   - Optionally crop it to the exact item. This fixes pages that show several colours.
   - Optionally add a note ("leave it unzipped, hood up"); one-tap chips suggest notes for the items you've picked.
   - Press **Try it on**. A render takes about 20–25 s.
3. **Every angle.** Drag across the photo, or tap ¾ / Side / Back. The other angles render in parallel, anchored on the front result so the outfit stays consistent. Press and hold the photo to compare with your plain model.
4. **Looks.** Every try-on is saved on the device with all its angles. You can bring any look back and change it.

### Why not a 3D model?
Reconstructing your body in 3D is doable. Simulating an arbitrary garment from one 2D screenshot onto it is not, at photoreal quality: there's no pattern, no fabric data and no back of the garment. So the app generates real views of you from each angle instead, which is what answers "does this colour suit me / how does it look from behind". Full reasoning is in [docs/RESEARCH.md](docs/RESEARCH.md).

### The engine
- **Model.** Google Gemini **Nano Banana Pro** (`gemini-3-pro-image`) at 2K, 3:4. It takes up to 5 person images and 6 object images plus instructions, which maps directly onto your photos, the garments and the note.
- **Fallback.** One retry, then **Nano Banana 2.1**. Safety blocks are never retried.
- **Prompts** live in `server/lib/prompts.ts`:
  - every image is labelled with what it is and what to use it for
  - identity and body are locked ("do not slim or idealise")
  - screenshots are de-cluttered (ignore the UI and other colourways)
  - the user's note is fenced as styling-only
- **Cost.** About $0.134 per image. A full look (front + 3 angles) is about $0.54; the one-time model is about $0.13.

## Run it

### Server
```sh
cd server
npm install
cp .env.example .env.local    # set GEMINI_API_KEY (+ APP_TOKEN to require auth)
npm test                      # 10 unit tests (no network)
npm run typecheck
npm run dev                   # http://localhost:8787/api/render
npm run eval -- drake         # real end-to-end renders; needs testdata/ (gitignored)
```

Deployed at `https://clothingonu.vercel.app` (Vercel project `clothingonu`, root directory `server`). **Pushing to `main` deploys it.** `GEMINI_API_KEY` and `APP_TOKEN` are set as Vercel env vars.

### iOS
```sh
cd ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # set APP_TOKEN (same as the server's)
xcodegen generate
open ClothingOnU.xcodeproj                                    # run the ClothingOnU scheme
```
To point the app at a local server, set `API_BASE_URL = http:/$()/localhost:8787` in `Secrets.xcconfig`.

Tests: `xcodebuild test -scheme ClothingOnU -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` (18 Swift Testing tests).

Debug-only launch hooks:
- `-resetLibrary YES` wipes local data.
- env `CLOTHINGONU_SEED=<dir>` pre-fills the profile and photos.

## Privacy
- Photos, your model and your looks stay on the phone, with file protection on.
- Images go to the server only for the request that needs them. The server is stateless: it never stores images and logs only timing and shape.
- Google processes the images to generate the result. Outputs carry Google's SynthID watermark.

## Known limits / next steps
- **Vision in the Simulator.** Body-pose detection doesn't run in the Simulator, so photo checks and pin placement fall back gracefully there. They work on a device.
- **App auth.** `APP_TOKEN` ships inside the app, which is a speed bump, not real auth. Before a public launch, add App Attest/DeviceCheck plus per-user quotas, because every render costs money.
- **Speed.** Renders take about 20–25 s. Rendering the angles in the background as soon as the front finishes would make turning feel instant, at about 3× the cost per look.
- **Links.** Only screenshots are supported today. Product links would need scraping per store.
