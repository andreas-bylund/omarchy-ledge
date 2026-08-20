// Ledge — a file ledge that hangs off the Omarchy bar.
//
// One component owns the whole plugin: the bar button (icon plus how many
// files are waiting), the ledge itself (model, persistence, clipboard and
// drag-out), and the card that opens under the button. Keeping button and
// card in one component tree is what lets the card line up with its own icon
// the way first-party Omarchy popups do.
//
// The card does not grab the screen while it is open (see LedgePopup.qml):
// dragging files in means pressing the mouse inside another window, and a
// screen-wide dismissal overlay would eat that press. The ledge closes on
// Escape, on the ✕, or on a second click on its bar icon.
//
// Everything the CLI needs is on the `bylund.ledge` IPC target.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "LedgeModel.js" as Model

Panel {
    id: root

    moduleName: "bylund.ledge"
    // The ledge registers its own target below so the file methods sit next
    // to open/close/toggle and the CLI only ever talks to one target.
    manageIpc: false

    readonly property bool barVertical: bar ? bar.vertical : false
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

    readonly property string homeDir: {
        const home = Quickshell.env ? Quickshell.env("HOME") : ""
        return home ? String(home) : ""
    }
    readonly property string stateHomeDir: {
        const stateHome = Quickshell.env ? Quickshell.env("XDG_STATE_HOME") : ""
        return stateHome ? String(stateHome) : ""
    }
    // Empty when the session has neither variable set. The ledge then keeps its
    // files for as long as the shell runs and simply does not survive a
    // restart, which is better than writing them somewhere shared.
    readonly property string statePath: Model.stateFile(homeDir, stateHomeDir)

    property string toast: ""
    // A drag is hovering the card, and a drag is hovering the bar icon. Two
    // separate targets: the icon is the one you can reach with a file already
    // in your hand.
    property bool dropActive: false
    property bool barDropActive: false
    // True for as long as a chip is being dragged out of the ledge. The drag
    // runs in a nested event loop inside LedgeChip.beginDrag().
    property bool dragOutActive: false

    // Nerd Font glyphs, verified against the font itself (see docs/icons.md).
    // The tray fills up as files land on it, which is the whole state of the
    // plugin readable from the bar at a glance.
    readonly property string glyphLedge: ledgeModel.count > 0
        ? "\u{F1296}"   // nf-md-tray_full
        : "\u{F1294}"   // nf-md-tray
    readonly property string glyphDrop: "\u{F0120}"    // nf-md-tray_arrow_down
    readonly property string glyphCopyAll: "\u{F0222}" // nf-md-file_multiple
    readonly property string glyphTrash: "\u{F01B4}"   // nf-md-delete
    readonly property string glyphClose: "\u{F0156}"   // nf-md-close
    readonly property string glyphSettings: "\u{F0493}" // nf-md-cog

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // One popout at a time, the same rule every first-party bar widget
    // follows: opening the ledge puts away whatever else was hanging off the
    // bar, and opening something else puts the ledge away.
    function syncPopout() {
        if (!bar || !bar.requestPopout)
            return
        if (opened)
            bar.requestPopout(root)
        else if (bar.activePopout === root)
            bar.releasePopout(root)
    }

    // --- closing itself ------------------------------------------------------
    //
    // Now that files can be dropped straight on the bar icon, the card no
    // longer has to stand around waiting to catch them, so it puts itself away
    // once the pointer has moved on.
    //
    // It is done on pointer-leave rather than the outside-click dismissal every
    // other bar popup uses, because that dismissal is a screen-wide input
    // region — and this window is a drag *source*. A surface covering the
    // screen would receive the drop of a chip dragged out of the ledge instead
    // of the application it was aimed at, which breaks the other half of the
    // plugin. Nothing may cover the screen here.
    //
    // The timer is only armed once the pointer has actually been on the ledge:
    // a ledge summoned from the keyboard while the mouse sits somewhere else
    // entirely should wait to be used, not vanish three seconds later.
    //
    // A selection holds it open for as long as it stands. Marking chips is work
    // in progress — the drag they are being lined up for has not happened yet —
    // and closing the card in the middle of it throws that work away. The
    // selection is not hidden state either: the header says "2 selected" and the
    // chips carry it, so a ledge that will not close explains itself.

    property bool pointerHasVisited: false
    // The card shows its settings instead of the file list. Reset on close so
    // the ledge always comes back up showing files.
    property bool settingsOpen: false

    readonly property bool autoCloseWanted: Model.boolSetting(root.setting("autoClose", true), true)
    // Opt-in. Off, chips are only ever offered as a copy, so nothing a target
    // application does can relocate a file.
    readonly property bool moveAllowed: Model.boolSetting(root.setting("allowMove", false), false)
    // The bounds mirror the manifest's schema. Nothing enforces them on the way
    // in — `omarchy bar set` stores whatever it is handed — so a value that is
    // out of range, or not a number at all, is settled here.
    readonly property int autoCloseDelay: Model.intSetting(root.setting("autoCloseSeconds", 3), 3, 1, 15)
    readonly property bool pointerOnLedge: popup.hovered || button.tooltipHovered
    readonly property bool autoCloseArmed: root.opened && root.autoCloseWanted
        && root.pointerHasVisited && !root.pointerOnLedge
        && !root.dragOutActive && !root.barDropActive
        && root.selectionCount === 0 && !root.settingsOpen

    onPointerOnLedgeChanged: if (pointerOnLedge) root.pointerHasVisited = true
    onOpenedChanged: {
        syncPopout()
        if (!opened) {
            root.pointerHasVisited = false
            root.settingsOpen = false
        }
    }
    onAutoCloseArmedChanged: autoCloseArmed ? autoCloseTimer.restart() : autoCloseTimer.stop()

    Timer {
        id: autoCloseTimer
        interval: root.autoCloseDelay * 1000
        onTriggered: if (root.autoCloseArmed) root.close()
    }

    // --- ledge contents ------------------------------------------------------

    ListModel {
        id: ledgeModel
    }

    // --- selection -----------------------------------------------------------
    //
    // Ctrl-click marks chips so a single drag carries several files. The count
    // and the path list are kept as properties rather than computed on demand:
    // ListModel.setProperty does not invalidate a binding that walked the model,
    // so the header and the chips would go stale.

    property int selectionCount: 0
    property var selectedPathList: []
    // Where a Shift-click measures its range from.
    property int selectionAnchor: -1

    function syncSelection() {
        const paths = []
        for (let i = 0; i < ledgeModel.count; i++) {
            if (ledgeModel.get(i).selected)
                paths.push(ledgeModel.get(i).path)
        }
        root.selectedPathList = paths
        root.selectionCount = paths.length
        if (paths.length === 0)
            root.selectionAnchor = -1
    }

    function toggleSelection(index) {
        if (index < 0 || index >= ledgeModel.count)
            return
        ledgeModel.setProperty(index, "selected", !ledgeModel.get(index).selected)
        root.selectionAnchor = index
        syncSelection()
    }

    // Shift takes the run from the anchor to here. The anchor is wherever the
    // selection was last started — a ctrl-click, or the first shift-click when
    // nothing had been marked yet, which is what makes "shift-click the first,
    // shift-click the fifth" select all five. It stays put afterwards, so a
    // second shift-click re-measures the run from the same end rather than from
    // the previous click.
    //
    // Plain shift replaces the run the way a file manager does; ctrl-shift adds
    // it to what is already marked.
    function selectRangeTo(index, additive) {
        if (index < 0 || index >= ledgeModel.count)
            return
        if (root.selectionAnchor === -1)
            root.selectionAnchor = index
        const first = Math.min(root.selectionAnchor, index)
        const last = Math.max(root.selectionAnchor, index)
        for (let i = 0; i < ledgeModel.count; i++) {
            const inRange = i >= first && i <= last
            if (inRange !== (ledgeModel.get(i).selected === true)) {
                if (inRange || !additive)
                    ledgeModel.setProperty(i, "selected", inRange)
            }
        }
        syncSelection()
    }

    function clearSelection() {
        for (let i = 0; i < ledgeModel.count; i++) {
            if (ledgeModel.get(i).selected)
                ledgeModel.setProperty(i, "selected", false)
        }
        syncSelection()
    }

    function removeSelected() {
        for (let i = ledgeModel.count - 1; i >= 0; i--) {
            if (ledgeModel.get(i).selected)
                ledgeModel.remove(i)
        }
        syncSelection()
        persist()
    }

    // Everything the buttons in the header act on: the selection when there is
    // one, the whole ledge otherwise.
    function targetPaths() {
        return root.selectionCount > 0 ? root.selectedPathList : root.allPaths()
    }

    function indexOfPath(path) {
        for (let i = 0; i < ledgeModel.count; i++) {
            if (ledgeModel.get(i).path === path)
                return i
        }
        return -1
    }

    // Adds urls or absolute paths, skipping duplicates. Returns how many were
    // actually added.
    function addPaths(entries) {
        if (!entries || !entries.length)
            return 0
        const items = Model.itemsFromDrop(entries, Date.now())
        let added = 0
        for (const item of items) {
            if (indexOfPath(item.path) !== -1)
                continue
            // The role has to exist from the first append or setProperty()
            // cannot add it later.
            ledgeModel.append(Object.assign({ selected: false }, item))
            added++
        }
        if (added > 0) {
            persist()
            showToast(added === 1 ? "Added 1 file" : "Added " + added + " files")
        } else if (items.length > 0) {
            showToast("Already on the ledge")
        }
        return added
    }

    // A target reported that it moved the files rather than copying them, so
    // the paths these chips carried hold nothing now. Ledge does not delete
    // anything here — it is only dropping references that have gone stale.
    function removePaths(paths) {
        for (const path of paths) {
            const index = indexOfPath(path)
            if (index !== -1)
                ledgeModel.remove(index)
        }
        root.selectionAnchor = -1
        syncSelection()
        persist()
    }

    function removeAt(index) {
        if (index < 0 || index >= ledgeModel.count)
            return
        ledgeModel.remove(index)
        // Everything below the removed chip shifted up, so the anchor no longer
        // points at what it was measured from.
        root.selectionAnchor = -1
        syncSelection()
        persist()
    }

    function allPaths() {
        const paths = []
        for (let i = 0; i < ledgeModel.count; i++)
            paths.push(ledgeModel.get(i).path)
        return paths
    }

    function clearLedge() {
        if (ledgeModel.count === 0)
            return
        ledgeModel.clear()
        syncSelection()
        persist()
        showToast("Ledge cleared")
    }

    // --- clipboard / open ----------------------------------------------------

    // Copying as `text/uri-list` is what most apps read on paste when they
    // accept files, and it is the fallback whenever a drag does not land.
    function copyAsFiles(paths) {
        if (!paths.length)
            return
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy --type text/uri-list', "omarchy-ledge", Model.uriList(paths)])
        showToast(paths.length === 1 ? "File copied — paste it anywhere" : paths.length + " files copied — paste them anywhere")
    }

    function copyPath(path) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "omarchy-ledge", path])
        showToast("Path copied")
    }

    // Settings live next to the widget's id in shell.json, and `omarchy bar
    // set` is the supported way to get them there — it knows the file layout
    // and `--json` keeps the value a real boolean rather than the string
    // "true". The bar patches running widgets when the file changes, so the
    // toggle follows from the value coming back, not from local state.
    function setAllowMove(value) {
        Quickshell.execDetached(["omarchy", "bar", "set", root.moduleName,
                                 "allowMove", value ? "true" : "false", "--json"])
    }

    // What the target did with the files cannot be read off the drag: under
    // Wayland `Drag.onDragFinished` reports Qt.IgnoreAction for every drag,
    // including drops a file manager accepted and then moved the file out of
    // (see docs/drag-and-drop.md). So the ledge settles it by looking at the
    // files afterwards — a path that is gone was moved by whoever took it, and
    // its chip goes with it. Nothing is deleted here; a file that is still
    // there keeps its chip.
    // Paths still waiting to be looked at. Dragging twice inside the settle
    // window queues both sets: they are two lots of chips to settle, not one,
    // and overwriting here used to leave the first drag's chips pointing at
    // files that had already moved.
    property var pendingSettle: []

    function settleAfterDrag(paths) {
        if (!paths || paths.length === 0)
            return
        const queued = root.pendingSettle.slice()
        for (const path of paths) {
            if (queued.indexOf(path) === -1)
                queued.push(path)
        }
        root.pendingSettle = queued
        settleTimer.restart()
    }

    Timer {
        id: settleTimer
        // Enough for a same-filesystem move, which is a rename. A slow
        // cross-filesystem move can still be in flight; that chip is caught by
        // the check that runs after the next drag of it.
        interval: 900
        onTriggered: {
            if (root.pendingSettle.length === 0)
                return
            // The batch before this one is still being looked at, and handing a
            // running Process a new command drops it. Wait a beat instead.
            if (settleProcess.running) {
                settleTimer.restart()
                return
            }
            settleProcess.command = ["sh", "-c",
                'for p in "$@"; do [ -e "$p" ] || printf "%s\\n" "$p"; done',
                "omarchy-ledge"].concat(root.pendingSettle)
            root.pendingSettle = []
            settleProcess.running = true
        }
    }

    Process {
        id: settleProcess
        stdout: StdioCollector { id: settleOutput; waitForEnd: true }
        onExited: {
            const gone = String(settleOutput.text || "").split("\n").filter(p => p !== "")
            if (gone.length === 0)
                return
            console.log("omarchy-ledge: dropping", gone.length,
                        "chip(s) whose file moved away")
            root.removePaths(gone)
        }
    }

    function openPath(path) {
        Quickshell.execDetached(["xdg-open", path])
    }

    // Drags are the one part of this plugin that cannot be unit tested, and
    // what a source actually offers differs per application, so every drag that
    // reaches the ledge says so in the shell log (`quickshell log -f`). It is
    // only ever a line per drag, and it is the first thing to look at when a
    // drop "does nothing".
    function logDrag(where, event) {
        const formats = event.formats ? String(event.formats) : "?"
        const urls = event.hasUrls && event.urls ? event.urls.length : 0
        console.log("omarchy-ledge:", where, "urls=" + urls, "text=" + (event.hasText ? "yes" : "no"), "formats=[" + formats + "]")
    }

    function showToast(text) {
        root.toast = text
        toastTimer.restart()
    }

    Timer {
        id: toastTimer
        interval: 2200
        onTriggered: root.toast = ""
    }

    // --- persistence ---------------------------------------------------------
    //
    // A bar widget lives as long as the bar, so the ledge survives workspace
    // switches and closing the card by itself. The state file only has to
    // carry it across a shell restart.

    function persist() {
        if (!root.statePath)
            return
        const items = []
        for (let i = 0; i < ledgeModel.count; i++) {
            const entry = ledgeModel.get(i)
            items.push({ path: entry.path, addedAt: entry.addedAt })
        }
        stateFile.setText(Model.serialize(items))
    }

    // The state file is read asynchronously, so a file dropped on the bar icon
    // in the first moments of a shell start can arrive before it. Merging
    // rather than replacing is what keeps that drop: clearing here would wipe
    // the file the ledge had just been handed.
    function restore(text) {
        const items = Model.deserialize(text)
        if (!items.length)
            return
        const raced = ledgeModel.count > 0
        const existing = root.allPaths()
        for (const item of items) {
            if (existing.indexOf(item.path) === -1)
                ledgeModel.append(Object.assign({ selected: false }, item))
        }
        syncSelection()
        // Only when the two lists actually met. On an ordinary start the file
        // on disk is already exactly what was just read out of it.
        if (raced)
            persist()
    }

    FileView {
        id: stateFile
        path: root.statePath
        preload: true
        printErrors: false
        onLoaded: root.restore(stateFile.text())
        // A missing file simply means an empty ledge on first run; it is
        // written as soon as something lands on the ledge.
        onLoadFailed: error => {}
    }

    Component.onCompleted: {
        // FileView writes the file but not the directory above it.
        const dir = Model.stateDir(root.homeDir, root.stateHomeDir)
        if (dir)
            Quickshell.execDetached(["mkdir", "-p", dir])
    }

    // --- IPC (what `omarchy-ledge` calls) ------------------------------------

    // Accepts {"paths": [...]} or newline separated paths.
    //
    // The object wrapper is not decoration: an IPC argument that starts with
    // "[" is read as an argument *list* by the shell's IPC layer and splatted
    // across the method's parameters, so a bare JSON array never survives the
    // trip. An object does, and it keeps file names with spaces, commas,
    // quotes or newlines in one piece.
    function addFromArgument(argument) {
        const text = String(argument)
        let entries = null
        try {
            const parsed = JSON.parse(text)
            if (Array.isArray(parsed))
                entries = parsed
            else if (parsed && Array.isArray(parsed.paths))
                entries = parsed.paths
        } catch (e) {
            // Not JSON: treated as plain text below.
        }
        return root.addPaths(entries ? entries : text.split("\n"))
    }

    IpcHandler {
        target: "bylund.ledge"

        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.toggle() }

        // Puts files on the ledge and shows it.
        function add(paths: string): string {
            const added = root.addFromArgument(paths)
            root.open()
            return String(added)
        }

        // Same, but leaves the card closed — the bar count still moves.
        function addQuiet(paths: string): string {
            return String(root.addFromArgument(paths))
        }

        function list(): string { return root.allPaths().join("\n") }
        function count(): string { return String(ledgeModel.count) }
        function clear(): string { root.clearLedge(); return "0" }
    }

    LedgeTheme {
        id: ledgeTheme
    }

    // --- bar button ----------------------------------------------------------

    WidgetButton {
        id: button
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        // An empty ledge is nothing to look at; it brightens the moment
        // something is waiting on it, or while the card is open.
        dimmed: ledgeModel.count === 0 && !root.opened
        tooltipText: ledgeModel.count === 0
            ? "File ledge — drop files here"
            : (ledgeModel.count === 1 ? "File ledge — 1 file" : "File ledge — " + ledgeModel.count + " files")
        fixedWidth: root.barVertical ? -1 : barContent.implicitWidth + Style.space(10)
        fixedHeight: root.barVertical ? Style.bar.iconSlot : -1

        onPressed: function (buttonCode) {
            // Right-click puts the whole ledge on the clipboard in one gesture.
            // It opens the card as well, because the toast in there is the only
            // confirmation that anything happened.
            if (buttonCode === Qt.RightButton) {
                root.copyAsFiles(root.allPaths())
                root.open()
            } else {
                root.toggle()
            }
        }

        Row {
            id: barContent
            anchors.centerIn: parent
            spacing: countLabel.visible ? Style.space(4) : 0

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // While a file hovers the icon it becomes the drop arrow, so
                // the bar answers the drag before it is let go.
                text: root.barDropActive ? root.glyphDrop : root.glyphLedge
                color: root.barDropActive ? button.activeColor : button.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
            }

            Text {
                id: countLabel
                anchors.verticalCenter: parent.verticalCenter
                // A vertical bar has no room for the number; the tooltip and
                // the card still carry it.
                visible: ledgeModel.count > 0 && !root.barVertical
                text: ledgeModel.count
                color: root.barDropActive ? button.activeColor : button.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
            }
        }
    }

    // Dropping straight on the bar icon is the point of the whole plugin: by
    // the time you want a ledge you are already holding the file, with no free
    // hand to open anything. The bar is always on screen and always at the edge
    // you can throw the cursor at, so it is the one target that is reachable
    // mid-drag. The card is for taking files back out.
    DropArea {
        anchors.fill: parent

        onEntered: drag => {
            root.logDrag("bar icon: drag entered", drag)
            if (!drag.hasUrls && !drag.hasText)
                return
            drag.accept(Qt.CopyAction)
            root.barDropActive = true
            springTimer.restart()
        }

        onExited: {
            root.barDropActive = false
            springTimer.stop()
        }

        onDropped: drop => {
            root.logDrag("bar icon: dropped", drop)
            root.barDropActive = false
            springTimer.stop()
            const entries = drop.hasUrls ? drop.urls : String(drop.text).split("\n")
            // A quiet add: the icon fills up and the count moves, which is the
            // feedback you want when you are dropping one file after another.
            // Hovering instead of dropping is what asks for the card (below).
            if (root.addPaths(entries) > 0 || drop.hasUrls)
                drop.accept(Qt.CopyAction)
        }
    }

    // Spring-loading: hold a drag on the icon for a moment and the ledge opens
    // under it, so you can see what is already there — or drop into the list.
    Timer {
        id: springTimer
        interval: 700
        onTriggered: if (root.barDropActive) root.open()
    }

    // --- the card ------------------------------------------------------------

    readonly property int chipHeight: Style.space(60)
    readonly property int chipGap: Style.spacing.lg
    readonly property int listHeight: ledgeModel.count === 0
        ? Style.space(120)
        : ledgeModel.count * chipHeight + (ledgeModel.count - 1) * chipGap

    LedgePopup {
        id: popup

        anchorItem: button
        bar: root.bar
        open: root.opened
        cardWidth: Style.space(340)
        cardHeight: popup.fittedHeight(body.implicitHeight, Style.space(560))
        focusTarget: body
        onCloseRequested: root.close()

        Item {
            id: body
            anchors.fill: parent
            focus: true
            implicitHeight: header.height + Style.spacing.xl
                            + (root.settingsOpen ? settingsView.implicitHeight : root.listHeight)

            Keys.onEscapePressed: root.close()

            // Header --------------------------------------------------------
            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Style.space(28)
                // Above the list, so a tooltip hanging below a header button
                // is not painted over by the file list or the empty state.
                z: 2

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.glyphLedge + "  Ledge"
                    color: ledgeTheme.text
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xxs

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: Style.spacing.md
                        text: root.settingsOpen
                              ? "Settings"
                              : (root.selectionCount > 0
                                 ? root.selectionCount + " selected"
                                 : (ledgeModel.count === 1 ? "1 file" : ledgeModel.count + " files"))
                        color: root.selectionCount > 0 ? ledgeTheme.accent : ledgeTheme.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }

                    // These buttons carry no label, so the tooltip is the only
                    // thing naming them: it hangs below, where there is room
                    // inside the card, instead of above the top edge.
                    LedgeIconButton {
                        theme: ledgeTheme
                        icon: root.glyphCopyAll
                        tooltip: root.selectionCount > 0 ? "Copy selected as files" : "Copy all as files"
                        tooltipEdge: "bottom"
                        // File actions have nothing to act on in the settings
                        // view, and they already step out of the row for an
                        // empty ledge.
                        visible: ledgeModel.count > 0 && !root.settingsOpen
                        onClicked: root.copyAsFiles(root.targetPaths())
                    }

                    LedgeIconButton {
                        theme: ledgeTheme
                        icon: root.glyphTrash
                        tooltip: root.selectionCount > 0 ? "Remove selected" : "Clear ledge"
                        tooltipEdge: "bottom"
                        danger: true
                        visible: ledgeModel.count > 0 && !root.settingsOpen
                        onClicked: root.selectionCount > 0 ? root.removeSelected() : root.clearLedge()
                    }

                    LedgeIconButton {
                        theme: ledgeTheme
                        icon: root.glyphSettings
                        tooltip: root.settingsOpen ? "Back to files" : "Settings"
                        tooltipEdge: "bottom"
                        active: root.settingsOpen
                        onClicked: root.settingsOpen = !root.settingsOpen
                    }

                    LedgeIconButton {
                        theme: ledgeTheme
                        icon: root.glyphClose
                        tooltip: "Close"
                        tooltipEdge: "bottom"
                        onClicked: root.close()
                    }
                }
            }

            // Files ---------------------------------------------------------
            ListView {
                id: list
                anchors.top: header.bottom
                anchors.topMargin: Style.spacing.xl
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                spacing: root.chipGap
                model: ledgeModel
                visible: ledgeModel.count > 0 && !root.settingsOpen
                boundsBehavior: Flickable.StopAtBounds

                delegate: LedgeChip {
                    id: chipDelegate

                    required property int index
                    required property var model

                    width: ListView.view.width
                    height: root.chipHeight
                    theme: ledgeTheme
                    fontFamily: root.fontFamily
                    allowMove: root.moveAllowed
                    path: model.path
                    fileName: model.fileName
                    ext: model.ext
                    icon: model.icon
                    isImage: model.isImage
                    selected: model.selected === true
                    selectionCount: root.selectionCount
                    // Dragging a selected chip carries the whole selection;
                    // dragging an unselected one carries just itself and leaves
                    // the selection alone.
                    dragPaths: model.selected === true ? root.selectedPathList : [chipDelegate.path]

                    onCopyFileRequested: {
                        root.clearSelection()
                        root.copyAsFiles([chipDelegate.path])
                    }
                    onCopyPathRequested: root.copyPath(chipDelegate.path)
                    onOpenRequested: root.openPath(chipDelegate.path)
                    onRemoveRequested: root.removeAt(chipDelegate.index)
                    onSelectToggleRequested: root.toggleSelection(chipDelegate.index)
                    onSelectRangeRequested: additive => root.selectRangeTo(chipDelegate.index, additive)
                    onDragStarted: {
                        root.toast = ""
                        root.dragOutActive = true
                    }
                    // The pointer is over some other window by now, so the
                    // ledge tidies itself away right after the file lands.
                    //
                    // dragPaths has to be read before the selection is cleared:
                    // it is bound to the selection, so clearing first collapses
                    // it to this one chip and the rest are never checked.
                    onDragFinished: {
                        root.dragOutActive = false
                        const carried = chipDelegate.dragPaths.slice()
                        // A selection that has been dragged somewhere has done
                        // its job. Dropping the marks lets the ledge close
                        // itself again — holding them would pin the card open.
                        if (chipDelegate.selected)
                            root.clearSelection()
                        root.settleAfterDrag(carried)
                    }
                }
            }

            // Empty state ---------------------------------------------------
            Rectangle {
                anchors.top: header.bottom
                anchors.topMargin: Style.spacing.xl
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: ledgeModel.count === 0 && !root.settingsOpen
                radius: ledgeTheme.radius
                color: root.dropActive ? ledgeTheme.accentSoft : "transparent"
                border.width: 1
                border.color: ledgeTheme.border

                Column {
                    anchors.centerIn: parent
                    spacing: Style.spacing.md
                    width: parent.width - Style.space(24)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.glyphDrop
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.display
                        color: ledgeTheme.muted
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Drop files here"
                        color: ledgeTheme.text
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Drop on the bar icon too — it works mid-drag"
                        color: ledgeTheme.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        // An empty ledge is short enough that the toast lands
                        // on top of this line; it steps aside rather than
                        // being read through.
                        opacity: root.toast ? 0 : 1

                        Behavior on opacity {
                            NumberAnimation { duration: 140 }
                        }
                    }
                }
            }

            // Settings ------------------------------------------------------
            // Inline rather than a second surface: this card is a drag source
            // and must not grow anything that covers the screen (see
            // LedgePopup.qml), and a settings window of its own would be one
            // more thing to dismiss mid-drag.
            Column {
                id: settingsView
                anchors.top: header.bottom
                anchors.topMargin: Style.spacing.xl
                anchors.left: parent.left
                anchors.right: parent.right
                visible: root.settingsOpen
                spacing: Style.spacing.lg

                // Toggle carries its own description, so the explanation goes
                // there rather than in a paragraph underneath: one control,
                // one block of text, and the card stays short.
                Toggle {
                    width: parent.width
                    label: "Allow moving files out"
                    description: "Off, a drag out always copies. On, the app you "
                                 + "drop into decides and may move the original — "
                                 + "Ledge never deletes a file itself."
                    checked: root.moveAllowed
                    foreground: ledgeTheme.text
                    accent: ledgeTheme.accent
                    fontFamily: root.fontFamily
                    onClicked: root.setAllowMove(!root.moveAllowed)
                }
            }

            // Toast ---------------------------------------------------------
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: Math.min(parent.width, toastLabel.implicitWidth + Style.space(20))
                height: toastLabel.implicitHeight + Style.space(12)
                radius: height / 2
                color: ledgeTheme.accent
                opacity: root.toast ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 140 }
                }

                Text {
                    id: toastLabel
                    anchors.centerIn: parent
                    text: root.toast
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, parent.width - Style.space(16))
                    color: ledgeTheme.surface
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                }
            }

            // Drop target ---------------------------------------------------
            DropArea {
                anchors.fill: parent

                onEntered: drag => {
                    root.logDrag("card: drag entered", drag)
                    if (drag.hasUrls || drag.hasText) {
                        drag.accept(Qt.CopyAction)
                        root.dropActive = true
                    }
                }

                onExited: root.dropActive = false

                onDropped: drop => {
                    root.logDrag("card: dropped", drop)
                    root.dropActive = false
                    // Some sources only offer text: a plain path or a file://
                    // url still works, anything else is ignored by
                    // itemsFromDrop().
                    const entries = drop.hasUrls ? drop.urls : String(drop.text).split("\n")
                    if (root.addPaths(entries) > 0 || drop.hasUrls)
                        drop.accept(Qt.CopyAction)
                }
            }
        }
    }

    // The card gets a highlighted border while something is hovering over it,
    // which is the only feedback a drag gets before it is let go.
    Binding {
        target: popup
        property: "borderSpec"
        value: Border.flat(ledgeTheme.accent, Math.max(1, Style.space(2)))
        when: root.dropActive
    }
}
