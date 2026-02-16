# mac-photo-export

AppleScript for batch exporting photos and videos from macOS Photos.app with stable, deterministic filenames.

## What it does

- Exports selected photos as **JPEG** (quality 80) and videos in their **native format**
- **Live Photos** export both components (JPG + MOV)
- Names files with a stable, sortable pattern: `YYMMDD-HHMM-SS-<ID8>.<ext>`
- Generates a detailed **export report** in the destination folder
- **Rolls back** all created files if an unrecognized file type is encountered

## Requirements

- macOS with Photos.app
- Script Editor or `osascript` / `osacompile`

## Usage

### From Script Editor

1. Open `mac-photo-export.applescript` in Script Editor
2. In Photos.app, select the photos/videos you want to export
3. Run the script
4. Choose a destination folder
5. Wait for the export to complete

### From the command line

```sh
# Compile
osacompile -o mac-photo-export.scpt mac-photo-export.applescript

# Run
osascript mac-photo-export.scpt
```

## Filename format

```
YYMMDD-HHMM-SS-<ID8>.<ext>
```

| Part | Description |
|------|-------------|
| `YYMMDD` | Date (2-digit year, month, day) |
| `HHMM` | Time (hours, minutes) |
| `SS` | Seconds |
| `ID8` | First 8 characters of the MD5 hash of the Photos.app media ID |
| `ext` | `jpg` for photos, native extension for videos (`mov`, `mp4`, etc.) |

If a file already exists at the target path, a `_1`, `_2`, ... suffix is appended.

### Examples

```
250115-1423-07-a3f8b2c1.jpg       # Photo
250115-1423-07-a3f8b2c1.mov       # Live Photo video component
250320-0900-00-d4e5f6a7.mp4       # Video
250320-0900-00-d4e5f6a7_1.mp4     # Collision with same timestamp+hash
```

## File type handling

| Exported file | Action |
|---------------|--------|
| Photo (jpg, heic, png, tiff, etc.) | Converted to JPEG via `sips` (quality 80) |
| Video (mov, mp4, m4v, etc.) | Copied as-is |
| Live Photo | Both JPG and MOV components are exported |
| Sidecar (.aae, .xmp, .plist, etc.) | Silently skipped |
| macOS resource fork (`._*`) | Silently skipped |
| Unknown extension | **Aborts the entire run and rolls back all created files** |

The unknown-extension abort is intentional. It ensures the script never silently mishandles a new file type. The export report captures the exact filename and extension so you can update the script.

## Fallback behavior

If JPEG conversion fails (e.g., unsupported source format for `sips`), the original exported file is copied as-is with a `-orig` suffix:

```
250115-1423-07-a3f8b2c1-orig.heic
```

## Export report

Each run writes a report file to the destination folder:

```
export-report-<uuid>.txt
```

The report includes:
- Item and file counts (delivered, partial, failed, skipped)
- JPG conversion failure statistics
- Per-item log with OK / FALLBACK / FAIL / SKIP status
- Abort details (if applicable)

### Summary dialog example

```
Tous les items ont ete livres (42).
Items en echec: 0 (dont 0 partiels)
Items ignores: 0
Fichiers exportes: 48 (standard: 48, fallback: 0)
Conversions JPG impossibles: 0 ; sauvegardees en originaux: 0
Erreurs (evenements): 0
Rapport: /Users/you/Export/export-report-abc123.txt
```

## Supported extensions

**Photo**: jpg, jpeg, heic, heif, png, tiff, tif, bmp, gif, webp, raw, cr2, nef, arw, dng

**Video**: mov, mp4, m4v, avi, mkv, 3gp, mts, m2ts, wmv, webm

**Sidecar** (skipped): aae, xmp, json, plist, xml, thm, dop, ds_store

## License

MIT
