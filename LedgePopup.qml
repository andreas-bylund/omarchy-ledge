// Ledge — the card that hangs off the bar icon.
//
// A layer-shell surface the size of the card itself, placed under (or beside)
// the bar widget that owns it, the way every first-party Omarchy popup sits.
//
// It is deliberately NOT built on qs.Ui.KeyboardPanel, which the first-party
// popups use: that one spreads a screen-wide input region so a click anywhere
// dismisses it. The ledge is a drop target — files arrive by pressing the
// mouse inside *another* window while the ledge is open — and a screen-wide
// overlay would swallow exactly that press. Here the surface is only as big as
// the card, so every click outside it reaches the window underneath and the
// ledge stays put until it is closed on purpose.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
    id: popup

    // The bar item the card is aligned to, and the bar it lives on.
    property Item anchorItem: null
    property QtObject bar: null

    property bool open: false
    property int cardWidth: Style.space(340)
    property int cardHeight: Style.space(320)
    // Distance from the bar, and the smallest gap kept to the screen edges.
    property int gap: Style.gapsOut
    property int screenMargin: Style.gapsOut
    property int padding: Style.spacing.popupPadding
    property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
    // Item that holds the keyboard focus inside the card, so the key handlers
    // fire as soon as the compositor hands this surface the keyboard.
    property Item focusTarget: null

    signal closeRequested()

    // Whether the pointer is on the card. The ledge closes itself when the
    // pointer has left both the card and the bar icon that owns it.
    readonly property bool hovered: cardHover.hovered

    default property alias content: holder.children

    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property string barPos: bar && bar.position ? bar.position : "top"
    readonly property real barW: anchorWindow ? anchorWindow.width : 0
    readonly property real barH: anchorWindow ? anchorWindow.height : 0
    readonly property real screenW: screen ? screen.width : 0
    readonly property real screenH: screen ? screen.height : 0
    readonly property real contentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

    // How tall the card may grow before it would run into the bar or off the
    // screen. `fittedHeight` is what callers bind their content height to.
    readonly property real availableHeight: screenH > 0
        ? Math.max(Style.space(120), screenH - ((barPos === "top" || barPos === "bottom") ? barH + gap + screenMargin : screenMargin * 2))
        : 0

    function fittedHeight(contentHeight, cap) {
        var desired = Math.max(contentInset, (Number(contentHeight) || 0) + contentInset)
        var maxHeight = availableHeight > 0 ? availableHeight : desired
        if (cap !== undefined && Number(cap) > 0)
            maxHeight = Math.min(maxHeight, Number(cap))
        return Math.round(Math.min(desired, maxHeight))
    }

    // --- placement ----------------------------------------------------------

    // mapToItem is a one-shot; the watcher re-evaluates it whenever anything
    // between the bar surface and the icon moves or resizes (widgets coming
    // and going, the clock getting wider, the bar changing side).
    TransformWatcher {
        id: anchorWatcher
        a: popup.anchorWindow ? popup.anchorWindow.contentItem : null
        b: popup.anchorItem
    }

    readonly property point anchorPos: {
        anchorWatcher.transform  // reactive dependency
        if (!anchorItem || !anchorWindow)
            return Qt.point(0, 0)
        return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
    }

    // Along the bar we follow the icon; away from the bar we measure from the
    // bar surface itself, because the icon's mapped position carries the bar's
    // internal centering with it.
    readonly property point cardOrigin: {
        if (!anchorItem || !anchorWindow)
            return Qt.point(screenMargin, screenMargin)
        var x = 0
        var y = 0
        if (barPos === "bottom") {
            x = anchorPos.x + anchorItem.width / 2 - cardWidth / 2
            y = screenH - barH - cardHeight - gap
        } else if (barPos === "left") {
            x = barW + gap
            y = anchorPos.y + anchorItem.height / 2 - cardHeight / 2
        } else if (barPos === "right") {
            x = screenW - barW - cardWidth - gap
            y = anchorPos.y + anchorItem.height / 2 - cardHeight / 2
        } else {
            x = anchorPos.x + anchorItem.width / 2 - cardWidth / 2
            y = barH + gap
        }
        x = Math.max(screenMargin, Math.min(x, screenW - cardWidth - screenMargin))
        y = Math.max(screenMargin, Math.min(y, screenH - cardHeight - screenMargin))
        return Qt.point(Math.round(x), Math.round(y))
    }

    // --- surface -------------------------------------------------------------

    screen: anchorWindow ? anchorWindow.screen : null
    // Stays mapped through the fade-out so there is something to animate.
    visible: open || card.opacity > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-ledge"
    WlrLayershell.layer: WlrLayer.Top
    // OnDemand: the compositor hands this surface the keyboard when it is
    // clicked, and never before. The first-party popups get keys immediately by
    // priming with a brief Exclusive phase, but Exclusive also makes Hyprland
    // route *every* pointer event to the surface for as long as it lasts — and
    // this surface exists to sit still while the user drags a file around other
    // windows. Keys are worth less than that, so: click the card and it answers
    // Escape; otherwise it closes with its ✕, its bar icon, or an
    // `omarchy-ledge toggle` keybinding.
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    implicitWidth: cardWidth
    implicitHeight: cardHeight

    // Anchoring two adjacent edges keeps the implicit size and turns the
    // margins into an absolute position on the output.
    anchors {
        top: true
        left: true
    }

    margins {
        top: popup.cardOrigin.y
        left: popup.cardOrigin.x
    }

    onOpenChanged: {
        if (!open || !focusTarget)
            return
        // After the surface has mapped and the children have laid out. Qt needs
        // an item holding focus inside the window, or the key handlers stay
        // silent even once the compositor has handed over the keyboard.
        Qt.callLater(function () {
            if (popup.open && popup.focusTarget)
                popup.focusTarget.forceActiveFocus()
        })
    }

    BorderSurface {
        id: card
        anchors.fill: parent
        color: Color.popups.background
        borderSpec: popup.borderSpec
        padding: popup.padding
        radius: Style.cornerRadius
        opacity: popup.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        // Only tracks the pointer; it takes no events away from the content.
        HoverHandler {
            id: cardHover
        }

        Item {
            id: holder
            anchors.fill: parent
            anchors.topMargin: card.contentTopInset
            anchors.rightMargin: card.contentRightInset
            anchors.bottomMargin: card.contentBottomInset
            anchors.leftMargin: card.contentLeftInset
        }
    }
}
