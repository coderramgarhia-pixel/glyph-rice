import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components

// local change. pages: where you are. One app per screen, side by side in a workspace (scrolling layout, hypr/user.lua):
// 3 fingers ←/→ between apps, ↑/↓ between workspaces. After a move a pill rises at the bottom for a moment — the workspace
// number, the app's name, then a dot per app in left-to-right order: the current one is a white bar, the rest grey dots.
// The bar hides while an app is open, so this is the only "you are here". Click-through; the window exists only while shown
PanelWindow {
    id: root

    readonly property var mon: Hyprland.monitorFor(screen)
    readonly property var ws: mon?.activeWorkspace ?? null
    readonly property var active: Hyprland.activeToplevel
    // tiled apps of this workspace by x: columns of the scrolling layout, the order a swipe goes. x and floating come from
    // lastIpcObject, refreshed on every move (below)
    readonly property var apps: (ws?.toplevels.values ?? [])
        .filter(t => !t.lastIpcObject.floating)
        .sort((a, b) => (a.lastIpcObject.at?.[0] ?? 0) - (b.lastIpcObject.at?.[0] ?? 0))
    readonly property string name: {
        const id = active?.wayland?.appId ?? "";
        return DesktopEntries.heuristicLookup(id)?.name ?? id;
    }

    property bool armed: false // not on shell start
    Timer { running: true; interval: 1500; onTriggered: root.armed = true }
    // a different app took focus on this screen: a swipe, Super+arrow, a new app, a closed one. Null and back (Spot, the
    // launcher took the keyboard) is not a move
    property string last: ""
    onActiveChanged: {
        if (!active || active.monitor !== mon || active.address === last) return;
        last = active.address;
        Hyprland.refreshToplevels();
        if (!armed) return;
        shown = true;
        hide.restart();
    }
    Timer { id: hide; interval: 1200; onTriggered: root.shown = false }

    property bool shown: false
    property real t: shown && apps.includes(active) ? 1 : 0 // a dialog has no dot: nothing to show
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "glyph-pages"

    Stage {
        id: stage

        Rectangle {
            x: (stage.width - width) / 2
            y: stage.height - 64 - height + 24 * (1 - root.t) // rises from the edge and sinks back into it
            width: row.width + 40
            height: 52
            radius: Theme.corner(26)
            opacity: root.t
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 16
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Lb { text: String(root.ws?.id ?? "").padStart(2, "0"); px: 11 } // the workspace: the ↑/↓ axis
                    Lb { text: root.name; color: Theme.fg; px: 11 }
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    // by index: a move only shifts the white bar, the dots aren't recreated — so it slides, not jumps
                    Repeater {
                        model: root.apps.length
                        Rectangle {
                            required property int index
                            readonly property bool on: root.apps[index] === root.active
                            width: on ? 22 : 8
                            height: 8
                            radius: 4
                            color: on ? Theme.fg : Theme.mute
                            Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            Behavior on color { ColorAnimation { duration: Theme.t } }
                        }
                    }
                }
            }
        }
    }
}
