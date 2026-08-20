// Ledge — small icon button used for the per-file and header actions.

import QtQuick
import qs.Commons

Rectangle {
    id: button

    property alias icon: label.text
    property string tooltip: ""
    // Which side of the button the tooltip is placed on: "bottom", "top",
    // "left" or "right". These buttons sit close to the edges of a fixed-size
    // layer-shell surface, so the caller picks the side that keeps the tooltip
    // inside the panel — there is nowhere for it to overflow to.
    property string tooltipEdge: "bottom"
    property var theme: null
    property bool danger: false
    // Latched on: the button stands for something that is currently showing,
    // so it keeps the hover treatment while that lasts.
    property bool active: false

    signal clicked()

    implicitWidth: Style.space(26)
    implicitHeight: Style.space(26)
    radius: width / 2
    readonly property bool lit: mouse.containsMouse || button.active

    color: button.lit
           ? (button.danger ? Qt.rgba(1, 0.3, 0.3, 0.22) : theme.raisedHover)
           : "transparent"

    Behavior on color {
        ColorAnimation { duration: 90 }
    }

    Text {
        id: label
        anchors.centerIn: parent
        font.family: Style.font.family
        font.pixelSize: Style.font.icon
        color: button.active ? theme.accent : (button.lit ? theme.text : theme.muted)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: button.clicked()
    }

    // Tooltip: plain and self-contained so the plugin does not depend on
    // internal shell UI components.
    Rectangle {
        id: tip

        readonly property bool vertical: button.tooltipEdge === "top" || button.tooltipEdge === "bottom"

        visible: mouse.containsMouse && button.tooltip !== ""
        anchors.horizontalCenter: tip.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: tip.vertical ? undefined : parent.verticalCenter
        anchors.bottom: button.tooltipEdge === "top" ? parent.top : undefined
        anchors.top: button.tooltipEdge === "bottom" ? parent.bottom : undefined
        anchors.right: button.tooltipEdge === "left" ? parent.left : undefined
        anchors.left: button.tooltipEdge === "right" ? parent.right : undefined
        anchors.margins: Style.spacing.sm
        width: tooltipText.implicitWidth + Style.space(12)
        height: tooltipText.implicitHeight + Style.space(8)
        radius: Math.min(theme.radius, Style.space(6))
        color: theme.tooltipSurface
        border.width: 1
        border.color: theme.tooltipBorder
        z: 100

        Text {
            id: tooltipText
            anchors.centerIn: parent
            text: button.tooltip
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            color: theme.tooltipForeground
        }
    }
}
