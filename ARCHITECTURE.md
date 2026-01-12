# Frienance — Architecture and Run Guide ✅

## Overview
Frienance is a Flutter app with a focused receipt-processing pipeline. It combines a Flutter UI for uploading and visualizing receipts, an image-processing pipeline (OpenCV via `opencv_dart`) for cleaning and cropping receipt images, a parser for extracting structured information (market, date, items, sum), and an optional LLM-based service (`GeminiService`) for advanced extraction or verification.

---

## High-level components 🔧
- **UI (Flutter)**
  - Entry: `lib/main.dart` → `MyApp`, `MyHomePage`
  - Screens: `lib/src/screens/*` (notably `receipt_conversion_screen.dart`) provide upload and visualization UI
  - Templates / components under `lib/src/templates` and `lib/src/components`

- **Image preprocessing and recognition**
  - Core: `lib/services/parser/receipt_recognizer.dart`
  - Key responsibilities: import assets (`preworkImage`), copy images to cache, find images, apply OpenCV pipeline (grayscale, blur, dilation, contour detection, perspective transform, normalization), and save processed steps to `cache` for inspection.

- **Parsing & Extraction**
  - Model: `lib/services/parser/receipt.dart` (Receipt object, parsing logic: `parseMarket`, `parseDate`, `parseItems`, `parseSum`)
  - Utilities: `lib/services/parser/parse.dart` (batch processing, stats), `lib/services/parser/config.dart` (read/write parser config `config.json`), and `lib/cache/config.json` (default tuning for parsing regex/key lists)

- **LLM / External Service**
  - `lib/services/gemini_service.dart` — sends images and prompt to Gemini/Google Generative AI. Requires `GEMINI_API_KEY` environment variable.

- **CLI / Batch Runner**
  - `lib/services/runner.dart` — helper for running batch pre-processing outside Flutter (Dart script). Also `preworkImage()` is used to import asset images.

---

## Data flow (image → structured output) 🔁
1. Add images to `assets/images/` and ensure they're listed in `pubspec.yaml`.
2. App startup or CLI `preworkImage()` copies assets into application documents cache (e.g., `${appDocs}/cache/1_source_img`).
3. `ReceiptRecognizer` finds images and runs the OpenCV pipeline:
   - Resize (base ratio targets 1024 px height)
   - Grayscale → Blur → Morphology (dilate/close) → Canny → Contour detection
   - Contour approx → Perspective warp → Normalization & percentile-based contrast clipping
   - Save intermediate images and final processed image to cache (`2_temp_img`) for debugging
4. Parser (`Receipt`) tokenizes OCR lines (OCR step is separate; if using LLM-based extraction, `GeminiService` may accept image data and return JSON). The built-in parser expects textual lines (e.g., from OCR) to exist for parsing.

---

## Where to look for results 🧭
- Processed images: application documents directory under `cache/` (e.g. `/.../cache/2_temp_img/`)
- Parser JSON outputs: created alongside source files if `resultsAsJson` is enabled (via parse utilities)
- Stats: `stats.csv` (written by `parse.dart`)

---

## How to launch (development & CLI) ▶️
### Flutter app (development)
- Ensure Flutter is installed and dependencies are fetched:
  - flutter pub get
- Run on device/emulator:
  - `flutter run` (default device)
  - Or specify device: `flutter run -d <deviceId>`
- The app UI uses `ReceiptConversionScreen` for manual upload and step-by-step visualization.

### CLI / Batch processing (Dart)
- You can run the pre-processing script directly:
  - `dart run lib/services/runner.dart`
  - This runs `preworkImage()` and copies asset images into cache and begins processing via `ReceiptRecognizer`

### Environment variables
- For Gemini/LLM usage, set:
  - `export GEMINI_API_KEY=your_api_key`

---

## Tuning parameters & performance tips ⚙️
### Parser tuning (file: `lib/cache/config.json`)
- `total_terms`, `ignore_keys`, `sum_format`, `item_format`, `date_format` control fuzzy matching and regex extraction.
- Edit `lib/cache/config.json` or pass a different `config.json` to `readConfig()` to customize behavior per region/store.

### Image pipeline parameters (in `ReceiptRecognizer`)
- Resize target: currently uses `resizeRatio = 1024 / image.shape[0]` (control target by changing `1024`)
- Gaussian blur kernel: `(5, 5)` — smaller = less smoothing
- Morphological kernels: `(9, 9)` used for dilation/closing — adjust to match receipt text density
- Canny thresholds: `50` and `125` — tune for edge detection robustness
- Percentile clipping (contrast stretch): uses 4.5 and 95 percentiles — change `percentile` thresholds in `processImage()` to control contrast range
- Save intermediate steps (helper `saveProcessingStep`) to inspect and iterate quickly

### Performance & platform notes
- `opencv_dart` depends on native OpenCV; ensure OpenCV is installed on target platform and the build supports `opencv_dart`.
- On mobile, CPU-bound image processing is expensive; consider using isolates or native plugins for heavy loads.
- Use `kDebugMode` prints for quick diagnostics, but remove/disable verbose logging in production.

---

## Troubleshooting & tips 🛠️
- If no images are found: ensure assets are declared in `pubspec.yaml` and `preworkImage()` can access `AssetManifest.json`.
- If receipt not detected: inspect saved intermediate images in `cache/` to see which stage lost the receipt contour.
- If Gemini response can't be parsed: check that the returned text is valid JSON — Gemini helper strips Markdown fences before decoding.
- For regex tuning, test patterns via small scripts using `parse.dart` utilities and `Receipt` on sample lines.

---

## Next steps / Suggested improvements 💡
- Add an explicit OCR stage (Tesseract or cloud OCR) and integrate textual output into `Receipt` parsing.
- Parameterize pipeline settings into a `processing_config.json` so non-developers can tune thresholds without editing code.
- Add unit/integration tests for parsing (some tests are in `receipt-parser/tests/`) and image pipeline.

---

If you'd like, I can: add a `PROCESSING_CONFIG.md` and/or expose the main tunable parameters as a single JSON file in `lib/cache/` and wire a simple UI to tweak them and re-run processing. ✅
