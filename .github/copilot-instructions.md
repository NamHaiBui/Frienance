# Frienance Copilot Instructions

## Project Overview
Frienance is a Flutter app for receipt processing and financial analysis. It combines image processing (OpenCV), OCR/text extraction (Google ML Kit), optional LLM integration (Google Gemini), and a custom receipt parser to extract structured data from receipt images.

## Architecture & Data Flow

### Core Pipeline (Image → Structured Data)
1. **Image Input** → Images placed in `assets/images/` or uploaded via UI
2. **Copy to Cache** → `ReceiptRecognizer` copies to `${appDocs}/cache/1_source_img`
3. **OpenCV Processing** → Receipt detection, perspective correction, normalization (saves intermediate steps to `2_temp_img/`)
4. **Text Extraction** → `Enhancer` (in `text_extraction.dart`) uses Google ML Kit for OCR
5. **Parsing** → `Receipt` class extracts market, date, items, sum using fuzzy matching and regex
6. **Optional LLM** → `GeminiService` can verify/enhance extraction (requires `GEMINI_API_KEY`)

### Key Components
- **Image Processing**: `lib/services/receipt_parser/receipt_recognizer.dart` (mobile) and `object_extraction.dart` (CLI/batch)
- **Text Extraction**: `lib/services/receipt_parser/text_extraction.dart` (`Enhancer` class with Google ML Kit)
- **Parser**: `lib/services/receipt_parser/receipt.dart` + `lib/cache/config.json` for market-specific rules
- **Config System**: `object_config.dart` provides `ObjectView` for type-safe JSON config access
- **UI**: `lib/main.dart` → `DissectApp` → `DissectHomePage` (shows purpose-based spending visualization)

## Critical Workflows

### Running the App
```bash
flutter pub get
flutter run -d <deviceId>              # Specify device
flutter run -d emulator-5554           # Android emulator example
```

### Batch Processing (CLI)
```bash
dart run lib/services/runner.dart      # Runs preworkImage() and processes assets
```

### Environment Setup
```bash
export GEMINI_API_KEY=your_api_key     # Only needed for LLM-based extraction
```

### Debugging Image Processing
- Intermediate images saved to application documents cache: `${appDocs}/cache/2_temp_img/`
- On mobile, use `path_provider` to locate cache: `getTemporaryDirectory()` or `getApplicationDocumentsDirectory()`
- Use Flutter DevTools or `adb` to pull files from device for inspection

## Project-Specific Conventions

### Dual Implementation Pattern
**Critical**: This codebase has TWO `ReceiptRecognizer` implementations:
- `receipt_recognizer.dart` → Mobile/Flutter (uses `path_provider`, writes to temp directory)
- `object_extraction.dart` → CLI/batch (uses `Directory.current.path`, outputs to `assets/images/`)

When modifying image processing logic, **update BOTH files** or consider consolidating.

### Config-Driven Parsing
- Parser behavior controlled by `lib/cache/config.json` (not `pubspec.yaml`)
- Market-specific rules: `"ignore_keys_metro": [...]`, `"sum_keys_metro": [...]`
- To add new market: add to `"markets"` map with fuzzy spelling variations
- To tune extraction: modify regex patterns (`date_format`, `sum_format`, `item_format`)

### Image Processing Tuning
Key parameters in `ReceiptRecognizer.processImage()`:
```dart
resizeRatio = 1024 / image.shape[0]          // Target height: 1024px
gaussianBlur(image, (5, 5), 0)               // Kernel size controls smoothing
cv2.getStructuringElement((9, 9))            // Morphology kernel for dilation
cv2.Canny(blurred, 50, 125)                  // Edge detection thresholds
percentile(4.5) / percentile(95)             // Contrast clipping range
```
Adjust these when receipts aren't detected or text is lost during normalization.

### Flutter Design System
- Design tokens in `lib/main.dart`: `UIConfig` class defines spacing (`gapXS` to `gapXL`), radii, colors
- Always use `UIConfig` constants instead of hardcoded values
- Current theme: Material 3 with "high-end, focus-oriented" aesthetic

## Common Tasks

### Adding New Receipt Market
1. Add to `lib/cache/config.json` → `"markets"` with fuzzy spellings:
   ```json
   "target": ["target", "target store", "tgt"]
   ```
2. Add market-specific keys if needed:
   ```json
   "sum_keys_target": ["total", "grand total"],
   "ignore_keys_target": ["coupon", "reward"]
   ```
3. Parser automatically uses market-specific config when market is detected

### Improving OCR Accuracy
1. Check intermediate images in `cache/2_temp_img/` (look for `*_4_morph_close.jpg`, `*_8_final.jpg`)
2. If text is blurry: reduce Gaussian blur kernel in `processImage()`
3. If receipt not detected: lower Canny thresholds or adjust morphology kernel
4. If contrast is poor: modify percentile clipping values
5. For small text: increase `resizeRatio` target (e.g., 2048 instead of 1024)

### Integrating LLM Extraction
- `GeminiService` is referenced but implementation in `lib/services/llm_delegation/` is empty (placeholder)
- To implement: create service that sends processed image + prompt to Gemini API
- Expected flow: Image → OCR fallback → LLM verification → JSON output
- Gemini responses should be stripped of Markdown fences before JSON parsing

## Testing & Validation

### Manual Testing
1. Add test receipt images to `assets/images/`
2. Update `pubspec.yaml` if using new subdirectories
3. Run batch processor: `dart run lib/services/runner.dart`
4. Inspect outputs in `cache/2_temp_img/` and verify JSON extraction

### Debugging Receipt Detection Failures
- Enable debug mode: Check `kDebugMode` constant (based on `dart.vm.product`)
- Review saved intermediate images (grayscale, edges, contours, perspective warp)
- Common issues:
  - No contour detected → adjust morphology or Canny thresholds
  - Wrong contour selected → tune contour approximation epsilon
  - Receipt too dark/light → modify percentile clipping

## Integration Points

### External Dependencies
- **OpenCV**: Native via `opencv_dart` (requires OpenCV installed on target platform)
- **Google ML Kit**: OCR engine (Android/iOS only, not available on desktop)
- **Google Gemini**: Optional LLM (REST API, requires API key)
- **Path Provider**: Cross-platform cache directory resolution

### Platform-Specific Considerations
- **Mobile**: Use `receipt_recognizer.dart` with `path_provider`
- **Desktop/CLI**: Use `object_extraction.dart` with `Directory.current.path`
- **OCR**: Google ML Kit only works on mobile; desktop OCR requires alternative solution

## Anti-Patterns to Avoid

❌ **Don't** hardcode cache paths (use `path_provider` on mobile, `Directory.current.path` for CLI)  
❌ **Don't** edit `pubspec.yaml` for parser config (use `lib/cache/config.json`)  
❌ **Don't** assume single `ReceiptRecognizer` implementation (check context: mobile vs CLI)  
❌ **Don't** modify image processing in only one file (sync changes between dual implementations)  
❌ **Don't** use generic logging (use `kDebugMode` guards: `if (kDebugMode) print(...)`)

## Quick Reference

### Key Files
- Parser logic: [lib/services/receipt_parser/receipt.dart](lib/services/receipt_parser/receipt.dart)
- Mobile image processing: [lib/services/receipt_parser/receipt_recognizer.dart](lib/services/receipt_parser/receipt_recognizer.dart)
- CLI image processing: [lib/services/receipt_parser/object_extraction.dart](lib/services/receipt_parser/object_extraction.dart)
- OCR: [lib/services/receipt_parser/text_extraction.dart](lib/services/receipt_parser/text_extraction.dart)
- Config schema: [lib/services/receipt_parser/object_config.dart](lib/services/receipt_parser/object_config.dart)
- Parser rules: [lib/cache/config.json](lib/cache/config.json)

### Extension Methods
- `PercentileExt` on `List<num>` in [lib/utils/mat_extensions.dart](lib/utils/mat_extensions.dart) for percentile calculations

### Analysis Options
- Lints: `flutter_lints ^5.0.0` (configured in [analysis_options.yaml](analysis_options.yaml))
