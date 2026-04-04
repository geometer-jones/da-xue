#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ANDROID_RES = ROOT / "apps/mobile/android/app/src/main/res"
IOS_APPICON = (
    ROOT / "apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
)

BACKGROUND = "#173D33"
FOREGROUND = "#F5F0E6"
IOS_BASE_SIZE = 1024
ANDROID_ADAPTIVE_SIZE = 432

IOS_ICON_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

ANDROID_ICON_SIZES = {
    "mipmap-mdpi/ic_launcher.png": 48,
    "mipmap-hdpi/ic_launcher.png": 72,
    "mipmap-xhdpi/ic_launcher.png": 96,
    "mipmap-xxhdpi/ic_launcher.png": 144,
    "mipmap-xxxhdpi/ic_launcher.png": 192,
    "mipmap-mdpi/ic_launcher_round.png": 48,
    "mipmap-hdpi/ic_launcher_round.png": 72,
    "mipmap-xhdpi/ic_launcher_round.png": 96,
    "mipmap-xxhdpi/ic_launcher_round.png": 144,
    "mipmap-xxxhdpi/ic_launcher_round.png": 192,
}

FONT_CANDIDATES = (
    Path("/System/Library/Fonts/STHeiti Medium.ttc"),
    Path("/System/Library/Fonts/Hiragino Sans GB.ttc"),
    Path("/System/Library/Fonts/Supplemental/Songti.ttc"),
)


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    raise FileNotFoundError("No usable CJK font found for icon generation.")


def draw_centered_character(
    image: Image.Image,
    *,
    character: str,
    color: str,
    font_size: int,
    vertical_offset: float = 0,
) -> None:
    draw = ImageDraw.Draw(image)
    font = load_font(font_size)
    left, top, right, bottom = draw.textbbox((0, 0), character, font=font)
    text_width = right - left
    text_height = bottom - top
    x = (image.width - text_width) / 2 - left
    y = (image.height - text_height) / 2 - top + vertical_offset
    draw.text((x, y), character, font=font, fill=color)


def build_full_icon(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), BACKGROUND)
    draw_centered_character(
        image,
        character="大",
        color=FOREGROUND,
        font_size=int(size * 0.62),
        vertical_offset=-size * 0.02,
    )
    return image


def build_android_foreground(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_centered_character(
        image,
        character="大",
        color=FOREGROUND,
        font_size=int(size * 0.56),
        vertical_offset=-size * 0.02,
    )
    return image


def write_png(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(path)


def main() -> None:
    ios_master = build_full_icon(IOS_BASE_SIZE)
    for filename, size in IOS_ICON_SIZES.items():
        write_png(ios_master, IOS_APPICON / filename, size)

    android_master = build_full_icon(ANDROID_ADAPTIVE_SIZE)
    for relative_path, size in ANDROID_ICON_SIZES.items():
        write_png(android_master, ANDROID_RES / relative_path, size)

    foreground = build_android_foreground(ANDROID_ADAPTIVE_SIZE)
    write_png(
        foreground,
        ANDROID_RES / "drawable/ic_launcher_foreground.png",
        ANDROID_ADAPTIVE_SIZE,
    )


if __name__ == "__main__":
    main()
