#!/bin/sh
# Readable italic text in muxterm (MustardOS_RemoteAI).
# Author: Patryk Strzelecki
#
# Claude Code prints some text in italic (SGR 3, e.g. the "recap" lines). muxterm has no italic font, so SDL_ttf
# slants the regular glyphs, which is barely readable on the small console screen. muxterm uses an explicit font
# file for a style when term_font_path_italic / term_font_path_bold_italic are set in its config (and then skips the
# synthetic slant), so we point them at a real, designed italic: fonts/JetBrainsMono-MediumItalic.ttf (OFL), the
# italic of muOS's own terminal font. Without that file the regular font is used (italic shown upright).
# Usage: muxterm-italic.sh <muxterm .conf>   (called by the apps' mux_launch.sh before muxterm starts)
CONF="$1"
[ -n "$CONF" ] || exit 0
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$(dirname "$CONF")"
[ -f "$CONF" ] || echo "# muxterm.conf" > "$CONF"

FONT="$DIR/fonts/JetBrainsMono-MediumItalic.ttf"
if [ ! -f "$FONT" ]; then
    # fallback: the regular font (term_font_path from this config if set, else muxterm's default)
    FONT="$(sed -n 's/^[[:space:]]*term_font_path[[:space:]]*=[[:space:]]*//p' "$CONF" | tail -n 1 | tr -d '\r')"
    [ -f "$FONT" ] || FONT=/opt/muos/share/font/muterm.ttf
    [ -f "$FONT" ] || exit 0
fi

TMP="$CONF.italic.$$"
grep -v -e '^[[:space:]]*term_font_path_italic[[:space:]]*=' -e '^[[:space:]]*term_font_path_bold_italic[[:space:]]*=' \
    -e '^# MustardOS_RemoteAI: ' "$CONF" > "$TMP"
{
    echo "# MustardOS_RemoteAI: italic font (muxterm-italic.sh)"
    echo "term_font_path_italic = $FONT"
    echo "term_font_path_bold_italic = $FONT"
} >> "$TMP"
mv -f "$TMP" "$CONF"
