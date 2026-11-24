import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// local change. spot: Spotlight on Ctrl+Space. A single search pill; rows appear under it once you type:
// calc (qalc) · apps (the launcher's list and ranking) · files (plocate, spot/files.sh) · the web.
// From the launcher family: scrim, 24px lift with a fade, red caret; the selected row is a white pill, as in Clip.
// The window only exists while open (visible: t > 0), so closed it costs nothing
PanelWindow {
    id: root

    required property var launcher // apps, match and use counts: no second DesktopEntries scan
    readonly property string query: input.text.trim()
    readonly property string home: Quickshell.env("HOME")
    property int sel: 0

    property string calcOut: ""
    property var files: [] // { dir, path }

    readonly property var rows: {
        const q = query, ql = q.toLowerCase(), r = [];
        if (!q) return r;
        if (calcOut && calcOut !== q) {
            const v = calcOut;
            r.push({ kind: "calc", name: v, sub: q, glyph: "\u{F00EC}", hint: "↵ copy", run: () => Quickshell.execDetached(["wl-copy", "--", v.replace(/^≈ /, "")]) });
        }
        for (const a of launcher.filter(launcher.apps, ql).slice(0, 4))
            r.push(Object.assign({}, a, { kind: "apps", sub: a.gen ?? "" }));
        // the last search's files that still match: typing on doesn't blank the rows until plocate answers
        if (q.length >= 3) for (const f of files) {
            const cut = f.path.lastIndexOf("/"), name = f.path.slice(cut + 1);
            if (!name.toLowerCase().includes(ql)) continue;
            const dir = f.path.slice(0, cut);
            r.push({ kind: "files", name, sub: dir === home ? "~" : dir.replace(home + "/", "~/"),
                     glyph: f.dir ? "\u{F024B}" : "\u{F0214}", run: () => Quickshell.execDetached(["xdg-open", f.path]) });
        }
        r.push({ kind: "web", name: `Search the web for “${q}”`, sub: "google", glyph: "\u{F059F}",
                 run: () => Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(q)]) });
        return r;
    }

    property bool shown: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    function open() {
        input.text = "";
        sel = 0;
        shown = true;
        input.forceActiveFocus();
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }
    function run(it) {
        if (!shown || !it) return; // fading out it still takes clicks: a double click would open twice
        close();
        if (it.id) launcher.used(it.id);
        it.run();
    }

    onQueryChanged: {
        sel = 0;
        // shortcut: only queries with a digit go to qalc ("pi" won't); words it doesn't know it takes as 0, so those are dropped
        if (/\d/.test(query)) { calc.q = query; calc.exec(["qalc", query]); }
        else calcOut = "";
        if (query.length >= 3) filesT.restart();
        else files = [];
    }
    onRowsChanged: sel = Math.min(sel, Math.max(0, rows.length - 1))

    // full output, not -t: only it says `error: "f" is not a valid variable` — -t answers "fire 2" with 0
    Process {
        id: calc
        property string q
        stdout: StdioCollector {
            onStreamFinished: {
                if (calc.q !== root.query) return;
                const out = text.trim(), last = out.split("\n").pop() ?? "", parts = last.split(/ = | ≈ /);
                root.calcOut = !out || out.includes("error:") ? "" : (last.includes(" ≈ ") ? "≈ " : "") + parts[parts.length - 1];
            }
        }
    }
    Timer { id: filesT; interval: 150; onTriggered: { find.q = root.query; find.exec(["sh", Quickshell.shellPath("spot/files.sh"), root.query]); } }
    Process {
        id: find
        property string q
        stdout: StdioCollector {
            onStreamFinished: if (find.q === root.query) root.files = text.split("\n").filter(l => l.length > 2).map(l => ({ dir: l[0] === "d", path: l.slice(2) }))
        }
    }

    onVisibleChanged: if (visible) input.forceActiveFocus()

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-spot"

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.t
        // no click-to-close: with tap-to-click a stray palm tap closed Spot mid-search. Esc / Ctrl+Space close it
    }

    Stage {
        id: stage

        Rectangle {
            id: panel
            x: (stage.width - width) / 2
            y: 180 + 24 * (1 - root.t)
            width: 680
            height: bar.height + (root.rows.length ? list.height + 14 : 0)
            Behavior on height { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            opacity: root.t
            radius: Theme.corner(38)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            clip: true

            Item {
                id: bar
                width: parent.width
                height: 76

                Icon { id: lens; x: 28; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0349}"; color: Theme.grey; font.pixelSize: 22 }
                TextInput {
                    id: input
                    anchors { left: lens.right; leftMargin: 16; right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                    font { family: Theme.ui; pixelSize: 22 }
                    color: Theme.fg
                    selectionColor: Theme.s3
                    clip: true
                    cursorDelegate: Rectangle {
                        width: 2
                        color: Theme.accent
                        Timer { running: input.activeFocus; interval: 500; repeat: true; onTriggered: parent.opacity = 1 - parent.opacity }
                    }
                    Text {
                        visible: !input.text
                        x: 6
                        text: "Search apps, files, math, the web"
                        font: input.font
                        color: Theme.mute
                    }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) root.close();
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.run(root.rows[root.sel]);
                        else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) root.sel = Math.min(root.sel + 1, root.rows.length - 1);
                        else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) root.sel = Math.max(root.sel - 1, 0);
                        else return;
                        e.accepted = true;
                    }
                }
            }
            Rectangle { visible: root.rows.length > 0; x: 28; y: bar.height; width: parent.width - 56; height: 1; color: Theme.s2 }

            Column {
                id: list
                x: 14
                y: bar.height + 1
                width: parent.width - 28

                // by index, as in the launcher: a new letter changes the rows' data, it doesn't recreate them
                Repeater {
                    model: root.rows.length

                    Column {
                        id: row
                        required property int index
                        readonly property var it: root.rows[index] ?? ({})
                        readonly property bool on: root.sel === index
                        width: list.width

                        Lb {
                            visible: row.index === 0 || root.rows[row.index - 1]?.kind !== row.it.kind
                            x: 14
                            topPadding: 14
                            bottomPadding: 8
                            text: row.it.kind ?? ""
                            px: 11
                        }
                        Rectangle {
                            width: parent.width
                            height: 52
                            radius: Theme.corner(26)
                            color: row.on ? Theme.fg : "transparent"

                            Rectangle {
                                id: disc
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 40
                                radius: 20
                                color: row.on ? Theme.ink : Theme.s2
                                Image {
                                    anchors.centerIn: parent
                                    visible: !!row.it.src && status === Image.Ready
                                    width: 24
                                    height: 24
                                    source: row.it.src ?? ""
                                    sourceSize: Qt.size(24, 24)
                                    asynchronous: true
                                    retainWhileLoading: true
                                    layer.enabled: !!row.it.src
                                    layer.effect: Dm { step: 2 }
                                }
                                Icon { anchors.centerIn: parent; visible: !row.it.src; text: row.it.glyph ?? ""; color: row.on ? Theme.fg : Theme.grey }
                            }
                            Column {
                                anchors { left: disc.right; leftMargin: 14; right: hint.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText // file names and queries are not markup
                                    text: row.it.name ?? ""
                                    font { family: Theme.ui; pixelSize: 17 }
                                    color: row.on ? Theme.ink : Theme.fg
                                }
                                Text {
                                    visible: !!row.it.sub
                                    width: parent.width
                                    elide: Text.ElideMiddle
                                    textFormat: Text.PlainText
                                    text: row.it.sub ?? ""
                                    font { family: Theme.ui; pixelSize: 13 }
                                    color: row.on ? Theme.mute : Theme.grey
                                }
                            }
                            Lb {
                                id: hint
                                visible: row.on
                                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                                text: row.it.hint ?? "↵ open"
                                px: 11
                                color: Theme.mute
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.sel = row.index }
                            TapHandler { onTapped: root.run(row.it) }
                        }
                    }
                }
            }
        }
    }
}
