#!/usr/bin/env python3
"""
Convert comic files (CBZ/CBR/ZIP/RAR/PDF) to PDF for Kindle Scribe Colorsoft.

By default, original images are embedded as-is — no gamma, contrast, or color
changes. Use --optimize to smart-compress oversized files (color PNG → JPEG q90,
grayscale PNG kept as-is).

Outputs are automatically split at 200 MB (Send to Kindle web limit).

Usage:
    ./comic-to-pdf.py mycomic.cbz
    ./comic-to-pdf.py --manga mycomic.cbz
    ./comic-to-pdf.py --contrast 1.15 --manga mycomic.cbz
    ./comic-to-pdf.py --optimize --manga ~/comics/*.cbz
"""

import argparse
import io
import os
import sys
import tempfile
import shutil
import zipfile
import subprocess
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:
    sys.exit("Error: PyMuPDF not installed. Run: pip install PyMuPDF")

try:
    from PIL import Image as PILImage, ImageEnhance
except ImportError:
    PILImage = None
    ImageEnhance = None

# Kindle Scribe Colorsoft: 1980x2640 pixels at 300 PPI
DEVICE_WIDTH = 1980
DEVICE_HEIGHT = 2640
DPI = 300

# PDF page size in points (72 points per inch)
PAGE_W_PT = DEVICE_WIDTH / DPI * 72  # 475.2 pt
PAGE_H_PT = DEVICE_HEIGHT / DPI * 72  # 633.6 pt

# Send to Kindle web upload limit
MAX_PDF_MB = 200

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".tiff", ".tif", ".bmp", ".gif"}


def is_color_image(img_path):
    """Check if an image has actual color content (not just grayscale stored as RGB)."""
    if PILImage is None:
        # Fallback: assume color based on file format
        return Path(img_path).suffix.lower() in (".png", ".webp", ".bmp", ".tiff", ".tif")

    with PILImage.open(img_path) as img:
        if img.mode in ("L", "1", "P"):
            # Check palette images for color
            if img.mode == "P":
                palette = img.getpalette()
                if palette:
                    for i in range(0, len(palette), 3):
                        r, g, b = palette[i], palette[i + 1], palette[i + 2]
                        if r != g or g != b:
                            return True
            return False
        if img.mode in ("RGB", "RGBA"):
            # Sample pixels to detect if it's actually grayscale data in RGB container
            img_small = img.resize((100, 100))
            if img_small.mode == "RGBA":
                img_small = img_small.convert("RGB")
            pixels = list(img_small.getdata())
            for r, g, b in pixels:
                if abs(r - g) > 10 or abs(g - b) > 10 or abs(r - b) > 10:
                    return True
            return False
    return False


def apply_contrast(img_path, contrast, quality=90):
    """Apply contrast adjustment and return image bytes as JPEG.

    contrast: 1.0 = original, >1.0 = more contrast (1.1-1.2 recommended for e-ink).
    """
    if PILImage is None:
        sys.exit("Error: --contrast requires Pillow. Run: pip install Pillow")

    with PILImage.open(img_path) as img:
        if img.mode == "RGBA":
            bg = PILImage.new("RGB", img.size, (255, 255, 255))
            bg.paste(img, mask=img.split()[3])
            img = bg
        elif img.mode not in ("RGB", "L"):
            img = img.convert("RGB")

        enhanced = ImageEnhance.Contrast(img).enhance(contrast)
        buf = io.BytesIO()
        fmt = "JPEG"
        save_kwargs = {"quality": quality, "optimize": True}
        # Keep grayscale as grayscale
        if enhanced.mode == "L":
            enhanced = enhanced.convert("L")
        enhanced.save(buf, format=fmt, **save_kwargs)
        return buf.getvalue()


def optimize_image(img_path, quality=90):
    """Smart-compress: color PNG → JPEG at given quality. Returns (data, ext)."""
    if PILImage is None:
        sys.exit("Error: --optimize requires Pillow. Run: pip install Pillow")

    suffix = Path(img_path).suffix.lower()

    # JPEG sources: already compressed, embed as-is
    if suffix in (".jpg", ".jpeg"):
        with open(img_path, "rb") as f:
            return f.read(), ".jpeg"

    # PNG/other sources: check if color
    if is_color_image(img_path):
        # Color PNG → JPEG (significant size reduction)
        with PILImage.open(img_path) as img:
            if img.mode == "RGBA":
                # Composite onto white background
                bg = PILImage.new("RGB", img.size, (255, 255, 255))
                bg.paste(img, mask=img.split()[3])
                img = bg
            elif img.mode != "RGB":
                img = img.convert("RGB")
            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=quality, optimize=True)
            return buf.getvalue(), ".jpeg"
    else:
        # Grayscale PNG: keep as PNG (smaller than JPEG for low bit-depth)
        with open(img_path, "rb") as f:
            return f.read(), suffix

    # Fallback
    with open(img_path, "rb") as f:
        return f.read(), suffix


def extract_archive(archive_path, tmp_dir):
    """Extract CBZ/ZIP or CBR/RAR to tmp_dir, return sorted image paths."""
    ext = Path(archive_path).suffix.lower()

    if ext in (".cbz", ".zip"):
        with zipfile.ZipFile(archive_path, "r") as zf:
            zf.extractall(tmp_dir)
    elif ext in (".cbr", ".rar"):
        # Try unrar first (handles all RAR methods), then 7zz/7z as fallback
        extracted = False
        for cmd in ["unrar", "7zz", "7z"]:
            if not shutil.which(cmd):
                continue
            try:
                if cmd == "unrar":
                    subprocess.run([cmd, "x", "-o+", "-y", archive_path, tmp_dir + "/"],
                                   check=True, capture_output=True)
                else:
                    subprocess.run([cmd, "x", "-o" + tmp_dir, "-y", archive_path],
                                   check=True, capture_output=True)
                extracted = True
                break
            except subprocess.CalledProcessError:
                continue
        if not extracted:
            sys.exit("Error: Failed to extract RAR. Install unrar: brew install --cask rar")
    else:
        sys.exit(f"Error: Unsupported format: {ext}")

    # Collect and sort image files
    images = []
    for root, _, files in os.walk(tmp_dir):
        for f in files:
            if Path(f).suffix.lower() in IMAGE_EXTENSIONS and not f.startswith("."):
                images.append(os.path.join(root, f))
    images.sort()
    return images


def image_dimensions(img_path):
    """Get image width and height without loading full image into memory."""
    pix = fitz.Pixmap(img_path)
    w, h = pix.width, pix.height
    pix = None
    return w, h


def fit_rect(img_w, img_h):
    """Calculate centered fit-to-page rectangle for an image."""
    scale = min(PAGE_W_PT / img_w, PAGE_H_PT / img_h)
    fitted_w = img_w * scale
    fitted_h = img_h * scale
    x = (PAGE_W_PT - fitted_w) / 2
    y = (PAGE_H_PT - fitted_h) / 2
    return fitz.Rect(x, y, x + fitted_w, y + fitted_h)


def save_pdf(doc, output_path, manga=False):
    """Save PDF with optional R2L direction, print size info."""
    cat = doc.pdf_catalog()
    if manga:
        doc.xref_set_key(cat, "ViewerPreferences", "<< /Direction /R2L >>")
    doc.save(output_path, deflate=True, garbage=4)
    doc.close()
    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"  OK: {output_path} ({size_mb:.1f} MB)")
    return size_mb


def create_pdfs(image_paths, output_base, manga=False, optimize=False, quality=90,
                contrast=1.0, max_mb=MAX_PDF_MB):
    """Create one or more PDFs from images, splitting at max_mb.

    Returns list of output paths.
    """
    outputs = []
    doc = fitz.open()
    current_size = 0
    part = 1
    pages_in_part = 0
    use_contrast = contrast != 1.0

    for img_path in image_paths:
        img_w, img_h = image_dimensions(img_path)
        rect = fit_rect(img_w, img_h)
        page = doc.new_page(width=PAGE_W_PT, height=PAGE_H_PT)

        if use_contrast:
            img_data = apply_contrast(img_path, contrast, quality=quality)
            page.insert_image(rect, stream=img_data)
            img_size = len(img_data)
        elif optimize:
            img_data, _ = optimize_image(img_path, quality=quality)
            page.insert_image(rect, stream=img_data)
            img_size = len(img_data)
        else:
            page.insert_image(rect, filename=img_path)
            img_size = os.path.getsize(img_path)

        current_size += img_size
        pages_in_part += 1

        # Check if we should split (estimate: raw image sizes ≈ PDF size)
        # Only split if we have at least a few pages in the current part
        if max_mb > 0 and pages_in_part >= 5 and current_size > max_mb * 1024 * 1024 * 0.9:
            path = _part_path(output_base, part)
            save_pdf(doc, path, manga=manga)
            outputs.append(path)
            doc = fitz.open()
            current_size = 0
            pages_in_part = 0
            part += 1

    # Save remaining pages
    if doc.page_count > 0:
        if part == 1:
            # Single file, no part suffix
            path = output_base + ".pdf"
        else:
            path = _part_path(output_base, part)
        save_pdf(doc, path, manga=manga)
        outputs.append(path)
    else:
        doc.close()

    return outputs


def _part_path(base, part_num):
    return f"{base} - Part {part_num:02d}.pdf"


def convert_one(input_path, manga=False, optimize=False, quality=90, contrast=1.0,
                max_mb=MAX_PDF_MB):
    """Convert a single comic file to PDF(s)."""
    input_path = os.path.abspath(input_path)
    output_base = os.path.splitext(input_path)[0]

    print(f"--- Converting: {os.path.basename(input_path)} ---")

    if os.path.isdir(input_path):
        images = []
        for f in sorted(os.listdir(input_path)):
            if Path(f).suffix.lower() in IMAGE_EXTENSIONS:
                images.append(os.path.join(input_path, f))
        if not images:
            print(f"  SKIP: No images found in {input_path}", file=sys.stderr)
            return False
        create_pdfs(images, output_base, manga=manga, optimize=optimize,
                    quality=quality, contrast=contrast, max_mb=max_mb)
        return True

    # Archive file
    with tempfile.TemporaryDirectory(prefix="comic-pdf-") as tmp_dir:
        images = extract_archive(input_path, tmp_dir)
        if not images:
            print(f"  SKIP: No images found in {input_path}", file=sys.stderr)
            return False
        create_pdfs(images, output_base, manga=manga, optimize=optimize,
                    quality=quality, contrast=contrast, max_mb=max_mb)
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Convert comics to PDF for Kindle Scribe Colorsoft")
    parser.add_argument("inputs", nargs="+", help="Comic files or directories")
    parser.add_argument("-m", "--manga", action="store_true",
                        help="Manga mode (right-to-left reading)")
    parser.add_argument("-o", "--optimize", action="store_true",
                        help="Smart compress: color PNG → JPEG, keep grayscale PNG")
    parser.add_argument("-q", "--quality", type=int, default=90,
                        help="JPEG quality when using --optimize or --contrast (default: 90)")
    parser.add_argument("-c", "--contrast", type=float, default=1.0,
                        help="Contrast adjustment: 1.0=original, 1.1-1.2=recommended for e-ink (default: 1.0)")
    parser.add_argument("--max-mb", type=int, default=MAX_PDF_MB,
                        help=f"Split PDFs at this size in MB (default: {MAX_PDF_MB}, 0=no split)")
    args = parser.parse_args()

    succeeded = failed = 0
    for path in args.inputs:
        try:
            if convert_one(path, manga=args.manga, optimize=args.optimize,
                           quality=args.quality, contrast=args.contrast,
                           max_mb=args.max_mb):
                succeeded += 1
            else:
                failed += 1
        except Exception as e:
            print(f"  FAILED: {e}", file=sys.stderr)
            failed += 1

    print(f"\n=== Summary ===")
    print(f"Total: {succeeded + failed}  Succeeded: {succeeded}  Failed: {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
