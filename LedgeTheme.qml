// Ledge — theme adapter.
//
// Every colour comes from Omarchy's own theme singleton, so the ledge restyles
// itself the moment the user switches theme and looks first-party in all of
// them. Each role is guarded: if a future shell release renames a colour, the
// ledge degrades to a sane neighbour instead of rendering black-on-black.

import QtQuick
import qs.Commons

QtObject {
    id: theme

    readonly property color surface: Color.popups && Color.popups.background ? Color.popups.background : Color.background
    readonly property color text: Color.popups && Color.popups.text ? Color.popups.text : Color.foreground
    readonly property color border: Color.popups && Color.popups.border ? Color.popups.border : Color.muted
    readonly property color muted: Color.muted ? Color.muted : Color.foreground
    readonly property color accent: Color.accent ? Color.accent : Color.foreground

    // Derived roles. Alpha keeps them correct in both light and dark themes.
    readonly property color raised: Qt.rgba(text.r, text.g, text.b, 0.06)
    readonly property color raisedHover: Qt.rgba(text.r, text.g, text.b, 0.12)
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.18)

    // Geometry follows the shell's own tokens, so the ledge is as round (or
    // as square) and as dense as the rest of the desktop.
    readonly property int radius: Math.min(Style.cornerRadius, Style.space(10))
    readonly property int spacing: Style.spacing.lg
    readonly property int padding: Style.spacing.popupPadding

    // Icons are Nerd Font glyphs and rely on the shell's default font, which
    // Omarchy already sets to a patched font for its own bar icons.
}
