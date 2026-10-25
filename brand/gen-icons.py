#!/usr/bin/env python3
"""Render brand/icon.svg into every icon file that brand/apply.sh installs.

Output layout mirrors the repository paths the files replace, so apply.sh can
copy the whole tree. Rasterizing uses rsvg-convert when available (the nix
derivation) and falls back to the pre-installed Playwright Chromium otherwise.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
ICON_SVG = HERE / "icon.svg"

BG_FILL = "#06341e"
GLYPH_STROKE = "#9bc078"

ANDROID_DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def svg_variants(src: str) -> dict:
    rect = re.search(r"\s*<rect[^>]*/>", src)
    if not rect or GLYPH_STROKE not in src:
        sys.exit("icon.svg no longer matches the expected shape (rect + glyph strokes)")
    glyph_only = src.replace(rect.group(0), "")

    def recolor(svg: str, color: str) -> str:
        return svg.replace(GLYPH_STROKE, color)

    circle = f'<circle cx="20" cy="20" r="20" fill="{BG_FILL}"/>'
    round_bg = src.replace(rect.group(0), "\n  " + circle)
    # Adaptive-icon foreground: the glyph sits inside the 66dp safe zone of a 108dp canvas.
    inner = re.sub(r"<svg[^>]*>", "", glyph_only).replace("</svg>", "")
    foreground = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">'
        f'<g transform="translate(21 21) scale(1.65)">{inner}</g></svg>'
    )
    return {
        "full": src,
        "round": round_bg,
        "foreground": foreground,
        "glyph-white": recolor(glyph_only, "#ffffff"),
        "glyph-dark": recolor(glyph_only, "#1a1a1a"),
    }


class Rasterizer:
    def __init__(self, variants: dict):
        self.variants = variants
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="cashdesk-icons-"))
        self.svg_paths = {}
        for name, svg in variants.items():
            p = self.tmp / f"{name}.svg"
            p.write_text(svg)
            self.svg_paths[name] = p
        self.jobs = []  # (variant, size, out_png)

    def request(self, variant: str, size: int) -> pathlib.Path:
        out = self.tmp / f"{variant}-{size}.png"
        if not out.exists() and (variant, size, out) not in self.jobs:
            self.jobs.append((variant, size, out))
        return out

    def run(self):
        if shutil.which("rsvg-convert"):
            for variant, size, out in self.jobs:
                subprocess.run(
                    ["rsvg-convert", "-w", str(size), "-h", str(size),
                     "-o", str(out), str(self.svg_paths[variant])],
                    check=True,
                )
        else:
            self._run_playwright()
        self.jobs.clear()

    def _run_playwright(self):
        script = r"""
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const jobs = JSON.parse(fs.readFileSync(0, 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const j of jobs) {
    const svg = fs.readFileSync(j.svg, 'utf8').replace('<svg ', `<svg width="${j.size}" height="${j.size}" `);
    await page.setViewportSize({ width: j.size, height: j.size });
    await page.setContent(`<!doctype html><html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await page.screenshot({ path: j.out, omitBackground: true, clip: { x: 0, y: 0, width: j.size, height: j.size } });
  }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
"""
        payload = json.dumps(
            [{"svg": str(self.svg_paths[v]), "size": s, "out": str(o)} for v, s, o in self.jobs]
        )
        subprocess.run(["node", "-e", script], input=payload, text=True, check=True)


def save_png(src: pathlib.Path, dest: pathlib.Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    Image.open(src).convert("RGBA").save(dest, format="PNG", optimize=True)


def save_ico(frames: list, dest: pathlib.Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Pillow drops every size larger than the base image, so lead with the largest frame.
    images = sorted((Image.open(p).convert("RGBA") for p in frames), key=lambda im: -im.size[0])
    # BMP (DIB) frames like upstream's icon.ico: Windows only reliably renders
    # PNG-compressed frames at 256x256, and a PNG-only .ico shows as a blank icon.
    images[0].save(
        dest,
        format="ICO",
        sizes=[im.size for im in images],
        append_images=images[1:],
        bitmap_format="bmp",
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="directory to write the icon tree into")
    args = ap.parse_args()
    out = pathlib.Path(args.out)

    variants = svg_variants(ICON_SVG.read_text())
    rz = Rasterizer(variants)

    pngs = {
        "res/icon.png": ("full", 1024),
        "res/mac-icon.png": ("full", 1024),
        "res/32x32.png": ("full", 32),
        "res/64x64.png": ("full", 64),
        "res/128x128.png": ("full", 128),
        "res/128x128@2x.png": ("full", 256),
        "res/mac-tray-dark-x2.png": ("glyph-dark", 60),
        "res/mac-tray-light-x2.png": ("glyph-white", 48),
    }
    for density, scale in ANDROID_DENSITIES.items():
        base = f"flutter/android/app/src/main/res/mipmap-{density}"
        pngs[f"{base}/ic_launcher.png"] = ("full", int(48 * scale))
        pngs[f"{base}/ic_launcher_round.png"] = ("round", int(48 * scale))
        pngs[f"{base}/ic_launcher_foreground.png"] = ("foreground", int(108 * scale))
        pngs[f"{base}/ic_stat_logo.png"] = ("glyph-white", int(24 * scale))

    icos = {
        "res/icon.ico": [16, 32, 48, 64, 128],
        "res/tray-icon.ico": [16, 32],
        "flutter/windows/runner/resources/app_icon.ico": [16, 24, 32, 48, 64, 128, 256],
    }
    svgs = ["res/logo.svg", "res/scalable.svg", "flutter/assets/icon.svg"]

    requested = {rel: rz.request(v, s) for rel, (v, s) in pngs.items()}
    ico_frames = {rel: [rz.request("full", s) for s in sizes] for rel, sizes in icos.items()}
    rz.run()

    for rel, src in requested.items():
        save_png(src, out / rel)
    for rel, frames in ico_frames.items():
        save_ico(frames, out / rel)
    for rel in svgs:
        dest = out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ICON_SVG, dest)

    shutil.rmtree(rz.tmp, ignore_errors=True)
    print(f"wrote {len(pngs) + len(icos) + len(svgs)} icon files under {out}")


if __name__ == "__main__":
    main()
