// Ledge — one file on the ledge.
//
// Press and move to drag the file out into any other window (native XDG drag,
// text/uri-list). Click to copy it to the clipboard as a file, which is the
// fallback path for apps and compositors where dragging out does not land.

import QtQuick
import qs.Commons
import "LedgeModel.js" as Model

Rectangle {
    id: chip

    property var theme: null
    property string fontFamily: Style.font.family
    property string path: ""
    property string fileName: ""
    property string icon: ""
    property string ext: ""
    property bool isImage: false
    property bool selected: false
    // How many chips are selected in total, so a selected chip can say what it
    // is part of. Zero when nothing is selected.
    property int selectionCount: 0
    // The files this chip would drag: itself, or the whole selection when it is
    // part of one.
    property var dragPaths: [chip.path]

    readonly property string uri: Model.urlFromPath(path)

    signal copyFileRequested()
    signal copyPathRequested()
    signal openRequested()
    signal removeRequested()
    signal selectToggleRequested()
    signal selectRangeRequested(bool additive)
    signal dragStarted()
    signal dragFinished()
    // Note there is no "the drop was taken" signal: under Wayland there is no
    // way to know. See Drag.onDragFinished below.

    implicitHeight: Style.space(60)
    radius: theme.radius
    color: chip.selected ? theme.accentSoft : (hover.hovered ? theme.raisedHover : theme.raised)
    border.width: 1
    border.color: chip.selected ? theme.accent : (hover.hovered ? theme.border : "transparent")

    Behavior on color {
        ColorAnimation { duration: 90 }
    }

    // What the cursor carries: a picture of the chip's own thumbnail, grabbed
    // at icon size. Handing Qt the file url instead would drag a full 4K
    // screenshot across the screen — `imageSourceSize` bounds that, but the
    // grab also covers the file types that have no image at all, so every drag
    // looks the same.
    property url dragImage: ""

    function refreshDragImage() {
        thumbBox.grabToImage(function (result) {
            chip.dragImage = result.url
        }, Qt.size(Style.space(48), Style.space(48)))
    }

    // Off, a drag out can only ever be a copy — the target is not offered
    // anything else. On, the target picks, which is the only way a move can
    // happen: with `text/uri-list` it is the receiving application that does
    // the moving. Ledge never deletes a file itself either way.
    property bool allowMove: false
    readonly property int dragActions: chip.allowMove ? (Qt.CopyAction | Qt.MoveAction)
                                                      : Qt.CopyAction

    // Native drag-out. mimeData/imageSource are only used by Drag.Automatic.
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: chip.dragActions
    // Copy stays the proposal even when a move is allowed, so a target that
    // takes the suggestion rather than deciding for itself leaves files alone.
    Drag.proposedAction: Qt.CopyAction
    Drag.mimeData: ({
        "text/uri-list": Model.uriList(chip.dragPaths),
        "text/plain": chip.dragPaths.join("\n")
    })
    Drag.imageSource: chip.dragImage !== "" ? chip.dragImage : (chip.isImage ? chip.uri : "")
    Drag.imageSourceSize: Qt.size(Style.space(48), Style.space(48))

    // The action reported here is not usable as a signal. On Hyprland with
    // Qt 6.11 it comes back as Qt.IgnoreAction (0) for *every* drag, including
    // drops that a file manager accepted and then moved the file out of. So
    // this is a log line and nothing else — what actually happened to the
    // files is settled afterwards by looking at the files themselves
    // (`settleAfterDrag` in BarWidget.qml).
    Drag.onDragFinished: action => {
        console.log("omarchy-ledge: dragged out", chip.dragPaths.length,
                    "file(s), reported action=" + action + " (not trusted)")
    }

    // Qt refuses to start an automatic drag on an attached object that is not
    // already marked active ("startDrag() drag must be active" — and it warns
    // rather than throwing, so without the log this looks like nothing at all
    // happening). Marking it active does not itself start anything for
    // Drag.Automatic; startDrag() does, and blocks until the drop lands or is
    // cancelled. Clearing active afterwards leaves the chip ready for the next
    // press.
    function beginDrag() {
        chip.dragStarted()
        chip.Drag.active = true
        chip.Drag.startDrag(chip.dragActions)
        if (chip.Drag.active)
            chip.Drag.active = false
        chip.dragFinished()
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.OpenHandCursor
        // Grabbing is asynchronous, and a drag has to start inside the mouse
        // event that triggered it (Wayland wants that input serial), so the
        // picture is taken while the pointer is still on its way in.
        onHoveredChanged: if (hovered) chip.refreshDragImage()
    }

    MouseArea {
        id: body
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        // The list must not steal the press: dragging a file out is the whole
        // point of the ledge, scrolling is done with the wheel.
        preventStealing: true

        property point pressPoint: Qt.point(0, 0)
        property bool dragging: false

        onPressed: mouse => {
            pressPoint = Qt.point(mouse.x, mouse.y)
            dragging = false
        }

        onPositionChanged: mouse => {
            if (!pressed || dragging)
                return
            const dx = mouse.x - pressPoint.x
            const dy = mouse.y - pressPoint.y
            if (Math.sqrt(dx * dx + dy * dy) < 10)
                return
            // Stays true until the next press so the release that ends a drag
            // is not mistaken for a click.
            dragging = true
            chip.beginDrag()
        }

        onClicked: mouse => {
            if (dragging)
                return
            // Shift takes the run up to here, ctrl adds and removes one, and
            // the two together add the run to what is already marked. A plain
            // click drops the selection and copies the one file — the gesture
            // the ledge had before selection existed.
            if (mouse.modifiers & Qt.ShiftModifier)
                chip.selectRangeRequested((mouse.modifiers & Qt.ControlModifier) !== 0)
            else if (mouse.modifiers & Qt.ControlModifier)
                chip.selectToggleRequested()
            else
                chip.copyFileRequested()
        }
    }

    Rectangle {
        id: thumbBox
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(44)
        height: Style.space(44)
        radius: Math.min(theme.radius, Style.space(8))
        clip: true
        color: chip.isImage && thumb.status === Image.Ready ? "transparent" : theme.raised

        Image {
            id: thumb
            anchors.fill: parent
            visible: chip.isImage && status === Image.Ready
            source: chip.isImage ? chip.uri : ""
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Style.space(88)
            sourceSize.height: Style.space(88)
        }

        Text {
            anchors.centerIn: parent
            visible: !thumb.visible
            // A broken image (deleted file) falls back to the generic glyph.
            text: chip.isImage && thumb.status === Image.Error ? "\u{F02EE}" : chip.icon
            font.family: chip.fontFamily
            font.pixelSize: Style.font.displayLarge
            color: theme.muted
        }
    }

    Column {
        anchors.left: thumbBox.right
        anchors.leftMargin: Style.spacing.xl
        anchors.right: actions.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
            width: parent.width
            text: chip.fileName
            elide: Text.ElideMiddle
            color: theme.text
            font.family: chip.fontFamily
            font.pixelSize: Style.font.subtitle
        }

        // Doubles as the discoverability hint: the ways to get files out of the
        // ledge are only obvious once you have been told.
        Text {
            width: parent.width
            // The count belongs in the header, which already says "2 selected".
            // Repeating it per chip reads as a position in a list — "1 of 2" on
            // every chip looks like a bug, not like membership. Each chip only
            // says that it is in, and says what dragging it would take at the
            // moment the pointer is on it and a drag is the next thing to
            // happen.
            text: {
                if (chip.selected) {
                    if (hover.hovered && chip.selectionCount > 1)
                        return "drag takes all " + chip.selectionCount
                    return "selected"
                }
                if (hover.hovered)
                    return "drag · click copies · ctrl-click selects"
                return chip.ext ? chip.ext.toUpperCase() : "FILE"
            }
            elide: Text.ElideRight
            color: theme.muted
            font.family: chip.fontFamily
            font.pixelSize: Style.font.caption
        }
    }

    Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs
        opacity: hover.hovered ? 1 : 0
        enabled: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 90 }
        }

        // Tooltips go to the left: the chip is only 60 px tall and the list
        // clips, so anything above or below the button would be cut off or
        // drawn over the neighbouring chip. To the left it stays inside the
        // chip, next to the file name.
        LedgeIconButton {
            theme: chip.theme
            icon: "\u{F018F}"   // nf-md-content_copy
            tooltip: "Copy path"
            tooltipEdge: "left"
            onClicked: chip.copyPathRequested()
        }

        LedgeIconButton {
            theme: chip.theme
            icon: "\u{F03CC}"   // nf-md-open_in_new
            tooltip: "Open"
            tooltipEdge: "left"
            onClicked: chip.openRequested()
        }

        LedgeIconButton {
            theme: chip.theme
            icon: "\u{F01B4}"   // nf-md-delete
            tooltip: "Remove"
            tooltipEdge: "left"
            danger: true
            onClicked: chip.removeRequested()
        }
    }
}
