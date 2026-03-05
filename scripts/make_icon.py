#!/usr/bin/env python3
"""
Generate Oral Scribe app icon from the Pixabay microphone photo.
Source: https://pixabay.com/photos/stux-microphone-1074362/
License: Pixabay Content License (free for commercial use)
         https://pixabay.com/service/license-summary/

Usage: python3 scripts/make_icon.py
Requires: pip install Pillow numpy
"""

import numpy as np
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR   = Path(__file__).parent
SOURCE_IMAGE = Path.home() / "Downloads" / "stux-microphone-1074362_1280.jpg"
ICONSET_DIR  = SCRIPT_DIR / "../OralScribe/Resources/Assets.xcassets/AppIcon.appiconset"

ICON_SIZES   = [16, 32, 64, 128, 256, 512, 1024]
MASTER_SIZE  = 1024
BORDER_WIDTH = 42          # px at 1024
CORNER_RATIO = 0.2237      # macOS Big Sur corner radius


# ── Helpers ──────────────────────────────────────────────────────────────────

def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (size - 1, size - 1)], radius=radius, fill=255)
    return mask


def wood_grain_texture(size: int, seed: int = 7) -> Image.Image:
    """
    Procedural wood grain via fractal turbulence.

    The grain runs horizontally (like a sawn plank face).
    Multiple octaves of sine-wave distortion make the lines organic and uneven.
    Colours mapped to a rich walnut palette: light honey → dark chocolate.
    A lacquer sheen highlight completes the effect.
    """
    rng = np.random.default_rng(seed)

    xs = np.linspace(0.0, 1.0, size)
    ys = np.linspace(0.0, 1.0, size)
    xv, yv = np.meshgrid(xs, ys)

    # ── Fractal turbulence (multiple sine octaves) ────────────────────────
    # Each octave uses a different frequency and random phase offset so the
    # grain looks organic rather than mechanically regular.
    turbulence = np.zeros((size, size), dtype=np.float64)
    num_octaves = 7
    for i in range(num_octaves):
        scale = 2 ** i
        amp   = 1.0 / scale
        # Random phase offsets per octave give each run a unique pattern
        px = rng.uniform(0, 2 * np.pi)
        py = rng.uniform(0, 2 * np.pi)
        # Mix of x and y frequencies: mainly y-driven for horizontal grain
        turbulence += amp * np.sin(scale * 18.0 * yv + scale * 4.5 * xv + px) \
                         * np.cos(scale *  5.0 * xv + scale * 2.0 * yv + py)

    # ── Primary grain rings ───────────────────────────────────────────────
    # Sine of the perturbed y-axis creates the concentric ring pattern.
    # Higher ring_freq = more, tighter rings.
    ring_freq = 14.0
    perturbed_y = yv + 0.28 * turbulence
    rings = np.sin(ring_freq * 2.0 * np.pi * perturbed_y)

    # ── Fine-grain detail (micro-fibre texture) ───────────────────────────
    fine = np.zeros((size, size), dtype=np.float64)
    for i in range(4):
        scale = 40 * (i + 1)
        px = rng.uniform(0, 2 * np.pi)
        fine += (0.45 ** i) * np.sin(scale * np.pi * (perturbed_y + 0.06 * xv) + px)

    # Combine: main rings dominate, fine grain adds texture
    combined = 0.75 * rings + 0.25 * fine
    # Normalise to [0, 1]
    combined = (combined - combined.min()) / (combined.max() - combined.min())

    # ── Colour map: walnut palette ────────────────────────────────────────
    # light end = warm honey/amber; dark end = rich dark walnut
    # Three-stop gradient for more depth:
    #   0.0 → very dark (heartwood shadow)
    #   0.4 → mid warm brown
    #   1.0 → light honey highlight
    dark  = np.array([52,  28,  10], dtype=np.float64)   # deep walnut
    mid   = np.array([118, 68,  28], dtype=np.float64)   # medium walnut
    light = np.array([192, 138, 72], dtype=np.float64)   # honey/amber

    c = combined[:, :, np.newaxis]   # shape (size, size, 1)
    # Blend dark→mid for lower half, mid→light for upper half
    below = np.clip(c * 2.0, 0, 1)         # 0..1 maps to 0..0.5 of c
    above = np.clip(c * 2.0 - 1.0, 0, 1)  # 0..1 maps to 0.5..1.0 of c
    colours = dark * (1 - below) + mid * below
    colours = colours * (1 - above) + light * above

    # ── Subtle knot simulation ────────────────────────────────────────────
    # A single soft dark swirl off-centre adds realism without distraction.
    kx, ky = 0.72, 0.38   # knot centre (normalised)
    dist   = np.sqrt((xv - kx) ** 2 + (yv - ky) ** 2)
    knot   = np.exp(-dist * 18.0) * 0.45   # gaussian falloff
    colours = colours * (1.0 - knot[:, :, np.newaxis])

    colours = np.clip(colours, 0, 255).astype(np.uint8)

    # ── Lacquer / varnish sheen ───────────────────────────────────────────
    # Bright streak from upper-left simulates overhead light on gloss varnish.
    sheen  = np.clip(0.18 - xv * 0.12 - yv * 0.10, 0, 0.18)
    boost  = (sheen * 180).astype(np.int16)
    colours = np.clip(colours.astype(np.int16) + boost[:, :, np.newaxis], 0, 255).astype(np.uint8)

    # ── Alpha ─────────────────────────────────────────────────────────────
    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    rgba[:, :, :3] = colours
    rgba[:, :, 3]  = 255

    return Image.fromarray(rgba, "RGBA")


def add_wood_border(photo: Image.Image, size: int, border: int) -> Image.Image:
    """
    Composite: wood-grain background → inset photo → rounded mask.
    Adds a thin inner bevel and a soft shadow between wood and photo.
    """
    radius       = int(size * CORNER_RATIO)
    inner_size   = size - border * 2
    inner_radius = max(4, radius - border)

    # 1. Wood grain layer (full size, rounded mask applied)
    wood = wood_grain_texture(size)
    wood_mask = rounded_mask(size, radius)
    wood.putalpha(wood_mask)

    # 2. Inset shadow on the wood so the photo looks recessed into the frame
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    inset = border - 5
    shadow_draw.rounded_rectangle(
        [(inset, inset), (size - inset - 1, size - inset - 1)],
        radius=inner_radius + 5,
        fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=8))
    wood = Image.alpha_composite(wood, shadow)

    # 3. Photo with its own inner rounded mask
    photo_resized = photo.resize((inner_size, inner_size), Image.LANCZOS)
    photo_mask    = rounded_mask(inner_size, inner_radius)
    photo_layer   = Image.new("RGBA", (inner_size, inner_size), (0, 0, 0, 0))
    photo_layer.paste(photo_resized, mask=photo_mask)

    # 4. Paste photo centred onto wood
    result = wood.copy()
    result.paste(photo_layer, (border, border), mask=photo_layer)

    # 5. Inner bevel: a thin bright ring just inside the wood edge
    #    (mimics the routed/bevelled inner lip of a real picture frame)
    bevel = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bevel_draw = ImageDraw.Draw(bevel)
    b = border - 2
    bevel_draw.rounded_rectangle(
        [(b, b), (size - b - 1, size - b - 1)],
        radius=inner_radius + 2,
        outline=(255, 220, 160, 80),   # warm highlight
        width=2,
    )
    result = Image.alpha_composite(result, bevel)

    return result


# ── Main ─────────────────────────────────────────────────────────────────────

def make_icon():
    src = Image.open(SOURCE_IMAGE).convert("RGBA")
    _w, h = src.size   # 1280 × 853

    sq   = h       # 853 — full height → square crop
    left = 300     # offset so mic is centred with some waveform on the left
    crop = src.crop((left, 0, left + sq, sq))

    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    for size in ICON_SIZES:
        border = max(1, int(BORDER_WIDTH * size / MASTER_SIZE))
        photo  = crop.resize((size, size), Image.LANCZOS)
        icon   = add_wood_border(photo, size, border)
        out    = ICONSET_DIR / f"icon_{size}x{size}.png"
        icon.save(out, "PNG", optimize=True)
        print(f"  {size}x{size} → {out.name}")

    print("\nDone.")


if __name__ == "__main__":
    make_icon()
