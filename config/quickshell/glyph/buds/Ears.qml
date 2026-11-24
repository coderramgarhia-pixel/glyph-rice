import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import qs
import qs.components

// local change: приложение для наушников Nothing / CMF — по образцу меню питания (power/Power.qml): экран почти чёрный, слева
// столбец слов Doto, выбранное крупно с красной точкой; справа карточка наушников: фото (своё, buds/<имя>.png), значение
// выбранной настройки или описание варианта, имя, связь и заряд левый / правый / кейс.
// Уровни: настройки → её варианты (у CONTROLS: часть → жест → действие). ↵ / → / клик открывает варианты (тот же столбец слов, съезжает справа), там ↵ —
// применить, esc / ← / «‹ …» сверху — назад. Всё через Sys.ear (./ear)
// Во весь экран поверх всего, непрозрачный. Выйти — esc (на внутренних уровнях esc сначала назад) или крестик справа сверху;
// клик по пустому ничего не делает, ярлык и лаунчер только открывают
PanelWindow {
    id: root

    property int sel: 0
    property int depth: 0 // 0 — настройки, 1… — уровни внутри выбранной
    property int pick: 0 // подсвеченный пункт текущего уровня
    property point keyAt: Qt.point(-1, -1) // local change: pointer position at the last key press (see Words)
    property var stack: [] // что выбрано на пройденных уровнях (CONTROLS: часть, жест)
    property bool ringing: false
    property bool fitting: false
    readonly property var onoff: [[0, "off"], [1, "on"]]
    readonly property var rows: [
        { w: "NOISE", cap: "noise control", k: "mode", o: Sys.ancModes },
        { w: "EQ", cap: "equaliser", k: "eq", o: [[0, "dirac"], [1, "rock"], [2, "electro"], [3, "pop"], [4, "vocal"], [5, "classic"], [6, "custom"]] },
        { w: "BASS", cap: "ultra bass", k: "bass", o: [[0, "off"], [1, "1"], [2, "2"], [3, "3"], [4, "4"], [5, "5"]] },
        { w: "CONTROLS", cap: "controls", k: "gest" },
        { w: "SPATIAL", cap: "spatial audio", k: "spatial", o: onoff },
        { w: "LOW LAG", cap: "low latency", k: "latency", o: onoff },
        { w: "IN-EAR", cap: "in-ear detection", k: "inear", o: onoff },
        { w: "DUAL", cap: "dual connection", k: "dual", o: onoff },
        { w: "FIND", cap: "find my buds", act: () => root.ring(!root.ringing) },
        { w: "FIT TEST", cap: "ear tip fit", act: () => root.fit() }
    ]
    readonly property var row: rows[sel]
    readonly property int at: row.o ? row.o.findIndex(m => m[0] === Sys.ear?.[row.k]) : -1
    readonly property var fitRes: Sys.ear?.fit ?? null
    readonly property var fitWord: ["good", "loose", "error"]

    // полные имена вариантов на втором уровне (в Quick и в кольце — короткие)
    readonly property var full: ({ transp: "TRANSPARENCY", auto: "ADAPTIVE", electro: "ELECTRONIC", vocal: "VOCALS", classic: "CLASSICAL" })
    // что делает вариант — в кольце второго уровня, пока он подсвечен
    readonly property var desc: ({
        "mode:5": "no noise control", "mode:7": "lets outside sound in, so you hear what's around you",
        "mode:3": "light noise cancelling", "mode:2": "medium noise cancelling", "mode:1": "strongest noise cancelling",
        "mode:4": "adjusts cancelling to how loud it is around you",
        "eq:0": "balanced, neutral tuning", "eq:1": "punchy drums and guitars", "eq:2": "deep bass and crisp highs",
        "eq:6": "your own bass, mid and treble · ↵ to tune", "eq:3": "bright, forward vocals", "eq:4": "clearer voices for podcasts and calls", "eq:5": "wide, natural detail for orchestral music",
        "bass:0": "no extra bass",
        "spatial:1": "sound placed around you, not inside your head", "spatial:0": "normal stereo",
        "latency:1": "less audio delay for games and video", "latency:0": "normal delay",
        "inear:1": "pauses when you take a bud out", "inear:0": "keeps playing when you take a bud out",
        "dual:1": "stays connected to two devices · the buds restart", "dual:0": "one device at a time · the buds restart"
    })

    // ---- CONTROLS: жесты из ear ("gest": [часть, кнопка, тип, действие]). Действия по типу — как у CMF Buds Pro 2 в BudsLink
    // (deviceConfigs). ponytail: у других моделей список может отличаться — тогда видно лишь то, что они сами сообщили
    readonly property var gest: Sys.ear?.gest ?? []
    readonly property var partName: ({ 2: "LEFT", 3: "RIGHT", 4: "CASE" })
    readonly property var partDesc: ({ 2: "taps on the left bud", 3: "taps on the right bud", 4: "the dial on the case" })
    readonly property var actName: ({ 1: "NONE", 2: "PLAY PAUSE", 8: "PREVIOUS", 9: "NEXT", 11: "ASSISTANT", 18: "VOLUME UP",
        19: "VOLUME DOWN", 10: "NOISE", 20: "NOISE", 21: "NOISE", 22: "NOISE", 17: "GAME MODE", 23: "VOLUME" })
    readonly property var actDesc: ({ 1: "does nothing", 2: "play or pause", 8: "previous track", 9: "next track",
        11: "your phone's voice assistant", 18: "louder", 19: "quieter", 10: "switches noise control",
        17: "game mode: less audio delay", 23: "turn to change the volume" })
    function gestName(dev, type) {
        const bud = dev !== 4;
        return ({ 1: "PRESS", 2: bud ? "DOUBLE TAP" : "DOUBLE PRESS", 3: bud ? "TRIPLE TAP" : "TRIPLE PRESS", 7: "HOLD",
                  9: "DOUBLE HOLD", 10: "TURN" })[type] ?? `GESTURE ${type}`;
    }
    function gestHow(dev, type) {
        const v = dev !== 4 ? "tap" : "press";
        return ({ 1: "press the dial once", 2: `${v} twice`, 3: `${v} three times`, 7: `${v} and hold`,
                  9: `${v} twice, hold on the second`, 10: "turn the dial" })[type] ?? "";
    }
    function actsFor(dev, type) {
        if (dev === 4) return ({ 1: [2, 8, 9, 11, 17, 1], 2: [2, 8, 9, 11, 17, 1], 3: [2, 8, 9, 11, 17, 1], 7: [10, 11, 17, 1],
                                 9: [18, 19, 11, 17, 1], 10: [23, 1] })[type] ?? [1];
        return ({ 2: [2, 8, 9, 11, 1], 3: [8, 9, 11, 1], 7: [10, 11, 1], 9: [18, 19, 11, 1] })[type] ?? [1];
    }
    // у «noise control» четыре кода (какие режимы он перебирает) — любой из них считается им
    function sameAct(a, c) { return a === c || (c === 10 && [20, 21, 22].includes(a)); }
    readonly property var parts: [2, 3, 4].filter(d => gest.some(g => g[0] === d && g[1] === 1))
    // shortcut: только кнопка 1 — у кейса CMF Buds Pro 2 есть ещё кнопка 9 с неизвестными кодами (25, 26); разобраться — показать и её
    function slotsOf(dev) { return gest.filter(g => g[0] === dev && g[1] === 1); }
    readonly property var gPart: parts[stack[0]] ?? 0
    readonly property var gSlot: slotsOf(gPart)[stack[1]] ?? null
    // ---- local change: свой эквалайзер (EQ → CUSTOM, пресет 6): полосы бас / середина / верх, −6…6 дБ (ear set ceq).
    // Экран — три строки «имя · 13 точек · число» (Bands ниже): ↑↓ полоса, ←→ меньше / больше, клик по точке — сразу туда, ↵ готово
    readonly property bool bands: row.k === "eq" && depth >= 2
    readonly property var ceq: Sys.ear?.ceq ?? [0, 0, 0]
    readonly property var bandName: ["BASS", "MID", "TREBLE"]
    readonly property var bandDesc: ["deep sounds · kick drums and bass lines", "the middle · voices and most instruments",
                                     "high sounds · detail, cymbals and air"]
    function setBand(i, v) {
        v = Math.max(-6, Math.min(6, v));
        if (!Sys.ear || v === ceq[i]) return; // без ответа наушников Sys.ear не трогать: иначе он перестал бы быть null
        const c = ceq.slice();
        c[i] = v;
        Sys.ear = Object.assign({}, Sys.ear, { ceq: c });
        ceqT.restart(); // держишь клавишу — уйдёт одна команда с последним значением, а не очередь из каждого шага
    }
    Timer {
        id: ceqT
        interval: 400
        onTriggered: { root.pending = true; root.note = ""; Sys.earRun(["set", "ceq", root.ceq.join(".")]); }
    }

    readonly property string crumb: [row.cap, depth > 1 && row.k === "eq" ? "custom" : depth > 1 && gPart ? partName[gPart].toLowerCase() : "",
                                     depth > 2 && gSlot ? gestName(gSlot[0], gSlot[2]).toLowerCase() : ""].filter(x => x).join(" · ")

    // пункты текущего уровня: { v, t — слово, now — применён сейчас, tag — подпись справа, go — ведёт глубже, d — описание }
    readonly property var opts: {
        if (bands) return bandName.map((t, i) => ({ v: i, t: t, d: bandDesc[i] }));
        if (row.k === "gest") {
            if (depth <= 1) return parts.map(d => ({ v: d, t: partName[d], go: true, d: partDesc[d] }));
            if (depth === 2) return slotsOf(gPart).map(g => ({ v: g, t: gestName(g[0], g[2]), go: true,
                tag: (actName[g[3]] ?? `#${g[3]}`).toLowerCase(),
                d: `${gestHow(g[0], g[2])} · now ${(actName[g[3]] ?? "unknown").toLowerCase()}` }));
            if (!gSlot) return [];
            return actsFor(gSlot[0], gSlot[2]).map(c => ({ v: c, t: actName[c], now: sameAct(gSlot[3], c), d: actDesc[c] }));
        }
        if (row.o) return row.o.map(m => ({
            v: m[0], t: full[m[1]] ?? m[1].toUpperCase(), now: m[0] === Sys.ear?.[row.k], go: row.k === "eq" && m[0] === 6,
            d: desc[`${row.k}:${m[0]}`] ?? `extra bass, level ${m[0]} of 5`
        }));
        if (row.w === "FIND") return [{ v: "ring", t: ringing ? "STOP" : "RING",
            d: ringing ? "ringing both buds · ↵ to stop" : "plays a loud tone on both buds · take them out of your ears first" }];
        if (row.w === "FIT TEST") return [{ v: "fit", t: fitting ? "TESTING" : "START",
            d: fitting ? "listen · keep both buds in"
              : fitRes ? `last result · left ${fitWord[fitRes[0]] ?? "error"} · right ${fitWord[fitRes[1]] ?? "error"}`
              : "plays a short tone to check the ear tip seal · put both buds in" }];
        return [];
    }
    readonly property var po: opts[pick] ?? null

    // карточка справа: [подпись, крупное значение (Doto), текст под ним]
    readonly property var ctx: {
        if (!Sys.buds) return [row.cap, "", "connect your buds in quick settings"];
        // не отвечают долго: канал управления держит другое устройство (Nothing X на телефоне при dual connection) или буды зависли
        if (!Sys.ear) return [row.cap, "", Sys.earFails >= 3 ? "buds aren't answering · close Nothing X on your phone, or put the buds in the case for 10 s" : "waiting for buds…"];
        const fitTxt = fitting ? "..." : fitRes ? (fitRes[0] === 0 && fitRes[1] === 0 ? "GOOD" : "REFIT") : "";
        if (depth) {
            if (row.w === "FIT TEST") return [row.cap, fitTxt, po?.d ?? ""];
            if (bands) return [crumb, "", po?.d ?? ""]; // значение — только в строке полосы
            return [crumb, "", po?.d ?? ""];
        }
        if (row.k === "gest") return [row.cap, "", gest.length ? "change what taps, holds and the case dial do" : "your buds didn't report their controls"];
        if (row.w === "FIND") return [row.cap, ringing ? "RINGING" : "", "play a loud tone to find your buds"];
        if (row.w === "FIT TEST") return [row.cap, fitTxt, fitRes ? "last result" : "check how well the ear tips seal"];
        return [row.cap, at < 0 ? "--" : (full[row.o[at][1]] ?? row.o[at][1].toUpperCase()), row.k === "dual" ? "the buds restart when this changes" : ""];
    }
    // заряд под карточкой: у вкладышей левый / правый / кейс (кейс — пока наушники в нём), у полноразмерных одно «bat»
    readonly property var cells: Sys.ear?.bat !== undefined ? [["bat", "battery"]] : [["l", "left"], ["r", "right"], ["case", "case"]]
    // фото — по имени устройства, как у Buds.qml; не подключены — по спаренным, приглушённое
    readonly property var paired: Sys.buds ?? Bluetooth.devices.values.find(d => d.paired && /^(nothing|cmf|ear)\b|^(buds|neckband) pro$/i.test(d.deviceName || d.name)) ?? null
    readonly property string slug: (paired?.name ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")

    function open() {
        if (visible) return; // уже открыто: ярлык и лаунчер не закрывают и не сбрасывают — выход только esc
        sel = 0;
        depth = 0;
        stack = [];
        Sys.earRun(["all"]);
        visible = true;
    }
    function close() {
        if (ringing) ring(false);
        visible = false;
    }
    function toggle() { visible ? close() : open(); }
    // второй уровень открывается на применённом варианте
    function enter() {
        depth = 1;
        if (!opts.length) { depth = 0; return; }
        pick = Math.max(0, opts.findIndex(o => o.now));
    }
    function back() {
        if (depth <= 1) { depth = 0; stack = []; return; }
        const p = stack[stack.length - 1];
        stack = stack.slice(0, -1);
        depth--;
        pick = p;
    }
    function apply(i) {
        if (!opts[i]) return;
        if (bands) return back(); // ↵ на полосе — готово: значения уже ушли в наушники
        if (opts[i].go) { // глубже: пункт запоминается, новый уровень открывается на применённом
            if (row.k === "eq" && Sys.ear?.eq !== 6) set(6); // local change: CUSTOM сразу включает свой эквалайзер
            stack = [...stack, i];
            depth++;
            pick = Math.max(0, opts.findIndex(o => o.now));
            return;
        }
        if (!Sys.buds) return;
        pick = i;
        if (row.act) row.act();
        else if (row.o) set(opts[i].v);
        else if (row.k === "gest" && gSlot) setGesture(gSlot, opts[i].v);
    }
    function setGesture(g, c) {
        if (sameAct(g[3], c)) return; // уже стоит (noise control — любой из его кодов)
        const n = [g[0], g[1], g[2], c];
        Sys.ear = Object.assign({}, Sys.ear, { gest: gest.map(x => x[0] === g[0] && x[1] === g[1] && x[2] === g[2] ? n : x) });
        pending = true;
        note = "";
        Sys.earRun(["set", "gesture", n.join(".")]);
    }

    // отклик на смену: «current» переезжает сразу, пока ear работает — «saving…», потом «saved» на 2.5 с; ошибка висит до
    // следующей удачной команды
    property bool pending: false
    property string note: ""
    readonly property string status: pending ? "saving…" : note
    function set(v) {
        pending = true;
        note = "";
        Sys.earSet(row.k, v);
    }
    Timer { id: noteT; interval: 2500; onTriggered: root.note = "" }
    function ring(on) {
        ringing = on;
        Sys.earSet("ring", on ? 1 : 0);
    }
    function fit() {
        if (fitting) return;
        fitting = true;
        Sys.ear = Object.assign({}, Sys.ear, { fit: null });
        Sys.earRun(["fit"]);
    }
    // заряд вживую: пока приложение открыто — заряд и шумодав раз в 5 с (ear без аргументов, ~0.3 с; общий замок и очередь Sys)
    Timer { interval: 5000; repeat: true; running: root.visible && !!Sys.buds && !!Sys.ear; onTriggered: Sys.earRun([]) }
    // ear ждёт результат до 25 с; не пришёл — снять ожидание
    Timer { running: root.fitting; interval: 30000; onTriggered: root.fitting = false }
    Connections {
        target: Sys
        function onEarRunningChanged() {
            if (Sys.earRunning || !root.pending || Sys.earQ.length) return;
            root.pending = false;
            root.note = Sys.ear ? "saved" : "buds didn't answer · try again";
            if (Sys.ear) noteT.restart(); else noteT.stop();
        }
        function onEarChanged() { if (root.fitting && Sys.ear?.fit) root.fitting = false; }
        function onBudsChanged() { if (!Sys.buds) root.ringing = root.fitting = false; }
    }

    // между внутренними уровнями столбец заново въезжает: глубже — справа, назад — слева
    property int lastDepth: 0
    onDepthChanged: {
        if (depth >= 1 && lastDepth >= 1) {
            deepIn.from = depth > lastDepth ? 200 : -200;
            deepIn.restart();
        }
        lastDepth = depth;
    }
    NumberAnimation { id: deepIn; target: deepT; property: "x"; to: 0; duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }

    visible: false
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-buds"

    // макет 1920×1080 вписан в экран целиком
    Item {
        id: stage
        width: 1920
        height: 1080
        anchors.centerIn: parent
        scale: Math.min(parent.width / width, parent.height / height)
        focus: true
        Keys.onPressed: e => {
            const k = e.key;
            const ok = k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space;
            if (root.depth === 0) {
                const n = root.rows.length;
                if (k === Qt.Key_Up || k === Qt.Key_K) root.sel = (root.sel + n - 1) % n;
                else if (k === Qt.Key_Down || k === Qt.Key_J || k === Qt.Key_Tab) root.sel = (root.sel + 1) % n;
                else if (ok || k === Qt.Key_Right || k === Qt.Key_L) root.enter();
                else if (k === Qt.Key_Escape) root.close();
                else return;
            } else {
                const n = Math.max(1, root.opts.length);
                if (k === Qt.Key_Up || k === Qt.Key_K) root.pick = (root.pick + n - 1) % n;
                else if (k === Qt.Key_Down || k === Qt.Key_J || k === Qt.Key_Tab) root.pick = (root.pick + 1) % n;
                else if (root.bands && (k === Qt.Key_Right || k === Qt.Key_L)) root.setBand(root.pick, root.ceq[root.pick] + 1);
                else if (root.bands && (k === Qt.Key_Left || k === Qt.Key_H)) root.setBand(root.pick, root.ceq[root.pick] - 1);
                else if (ok) root.apply(root.pick);
                else if (k === Qt.Key_Escape || k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Backspace) root.back();
                else return;
            }
            root.keyAt = ptr.point.scenePosition; // local change: keys take over until the mouse really moves (Words)
            e.accepted = true;
        }
        HoverHandler { id: ptr } // where the pointer is, for keyAt

        // уровень 1 — настройки; при входе уезжает влево и гаснет
        Words {
            x: root.depth ? 40 : 240
            opacity: root.depth ? 0 : 1
            enabled: root.depth === 0
            items: root.rows.map(r => ({ t: r.w, now: false }))
            cur: root.sel
            keyAt: root.keyAt
            onHovered: i => root.sel = i
            onTapped: i => { root.sel = i; root.enter(); }
        }

        // уровни глубже — варианты; въезжают справа на место первого
        Words {
            transform: Translate { id: deepT }
            x: root.depth ? 240 : 440
            opacity: root.depth && !root.bands ? 1 : 0 // у своего эквалайзера вместо слов — Bands
            enabled: root.depth === 1
            items: root.opts
            cur: root.pick
            keyAt: root.keyAt
            onHovered: i => root.pick = i
            onTapped: i => root.apply(i)
        }

        // local change: свой эквалайзер — строка на полосу: имя (обычного размера, выбранная — белая с красной точкой), 13 точек
        // −6…+6 от центра к значению, как заряд, и число. Точки — цели клика (поле 28 px)
        Column {
            x: 240
            anchors.verticalCenter: parent.verticalCenter
            spacing: 64
            opacity: root.bands ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.t } }
            Repeater {
                model: root.bandName
                Row {
                    id: band
                    required property string modelData
                    required property int index
                    readonly property bool on: root.pick === index
                    readonly property int v: root.ceq[index]
                    spacing: 30
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: 15
                        color: Theme.accent
                        opacity: band.on ? 1 : 0
                    }
                    Num {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 290
                        text: band.modelData
                        font.pixelSize: 66
                        color: band.on ? Theme.fg : Theme.mute
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Repeater {
                            model: 13
                            Rectangle {
                                id: dot
                                required property int index
                                readonly property int at: index - 6
                                readonly property bool lit: at === 0 || (band.v > 0 ? at > 0 && at <= band.v : at < 0 && at >= band.v)
                                width: 18
                                height: 18
                                radius: 9
                                color: lit ? (band.on ? Theme.fg : Theme.grey) : Theme.s3
                                Behavior on color { ColorAnimation { duration: Theme.t } }
                                TapHandler { margin: 5; onTapped: { root.pick = band.index; root.setBand(band.index, dot.at); } }
                            }
                        }
                    }
                    Num {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 130
                        horizontalAlignment: Text.AlignRight
                        text: band.v > 0 ? `+${band.v}` : `${band.v}`
                        font.pixelSize: 54
                        color: band.on ? Theme.fg : Theme.mute
                    }
                }
            }
        }

        // local change: закрыть мышью. Это хром окна, не содержимое: круглая кнопка в углу с равными отступами сверху и справа
        // (48), где × ждут. Цвет — системная «пилюля» (s1, обводка s2) с белым ×; под курсором — «включённая» плитка: белый
        // круг, тёмный ×. Акцент не трогаем — он у выбора, красный — для тревог. Круг 72 (≈48 логических px), а поле клика
        // доходит до угла экрана: брошенный в угол указатель не промахнётся
        Item {
            x: stage.width - width
            width: 48 + 72 + 24
            height: 48 + 72 + 24
            HoverHandler { id: xHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: xTap; onTapped: root.close() }
            Rectangle {
                x: parent.width - 48 - width
                y: 48
                width: 72
                height: 72
                radius: 36
                color: xHov.hovered ? Theme.fg : Theme.s1
                border { width: 1; color: xHov.hovered ? Theme.fg : Theme.s2 }
                scale: xTap.pressed ? 0.92 : 1
                Behavior on color { ColorAnimation { duration: Theme.t } }
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                // × самого Doto: середина знака — 0.25 em от левого края и 0.525 em от верха коробки Num (метрики шрифта),
                // поэтому ставим по ним, а не centerIn (тот центрует коробку, знак уехал бы вниз-влево)
                Num {
                    x: parent.width / 2 - 0.25 * font.pixelSize
                    y: parent.height / 2 - 0.525 * font.pixelSize
                    text: "×"
                    font.pixelSize: 66 // знак 32 px = 0.45 круга; точки — как у невыбранных слов
                    color: xHov.hovered ? Theme.ink : Theme.fg
                    Behavior on color { ColorAnimation { duration: Theme.t } }
                }
            }
        }

        // где я: «‹ noise control», клик — назад
        Lb {
            x: 240
            y: 46
            opacity: root.depth ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.t } }
            enabled: root.depth === 1
            text: "‹  " + root.crumb
            color: bk.hovered ? Theme.fg : Theme.grey
            HoverHandler { id: bk; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.back() }
        }

        // карточка: фото крупнее всего, под ним — что выбрано (главное), ниже мелко имя, связь и заряд
        Column {
            x: stage.width - 160 - width
            anchors.verticalCenter: parent.verticalCenter
            width: 560
            spacing: 0

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 520
                height: 384
                visible: status === Image.Ready
                source: root.slug ? Quickshell.shellPath(`buds/${root.slug}.png`) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                mipmap: true
                opacity: Sys.buds ? 1 : 0.3
                Behavior on opacity { NumberAnimation { duration: Theme.t } }
            }

            Column {
                width: parent.width
                topPadding: 40
                spacing: 6
                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: root.ctx[0] }
                Num {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: Text.HorizontalFit // TRANSPARENCY и т.п.
                    topPadding: lead + 8
                    bottomPadding: lead + 8
                    text: root.ctx[1]
                    font.pixelSize: 66
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 440
                    visible: text !== ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: root.ctx[2]
                    font { family: Theme.mono; pixelSize: 17 }
                    color: root.depth ? Theme.fg : Theme.grey
                }
                Lb {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 8
                    visible: text !== ""
                    text: root.status
                    color: root.status.startsWith("buds") ? Theme.fg : Theme.grey
                }
            }

            Lb {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 46
                text: Sys.buds ? `${Sys.buds.name} · ${Sys.ear ? "connected" : Sys.earFails >= 3 ? "not answering" : "connecting"}` : "not connected"
            }

            // заряд: число Doto, под ним 10 точек — как Glyph; нет значения — «--» и пустые точки
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 18
                spacing: 64
                Repeater {
                    model: root.cells
                    Column {
                        id: cell
                        required property var modelData
                        // кейс вне ответа (наушники не в нём) — последний известный, подпись «last»
                        readonly property bool stale: modelData[0] === "case" && Sys.ear?.case === undefined && Sys.earCase !== null
                        readonly property var v: stale ? Sys.earCase : Sys.ear?.[modelData[0]]
                        readonly property bool chg: (Sys.ear?.chg ?? []).includes(modelData[0])
                        spacing: 8
                        Num {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: cell.v === undefined ? "--" : `${cell.v}`
                            font.pixelSize: 36
                            color: cell.v === undefined ? Theme.mute : Theme.fg
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4
                            Repeater {
                                model: 10
                                Rectangle {
                                    required property int index
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: cell.v !== undefined && index < Math.round(cell.v / 10) ? Theme.fg : Theme.s3
                                    Behavior on color { ColorAnimation { duration: Theme.t } }
                                }
                            }
                        }
                        Lb {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: cell.modelData[1] + (cell.chg ? " · charging" : cell.stale ? " · last" : "")
                            color: cell.chg ? Theme.fg : Theme.grey
                        }
                    }
                }
            }
        }

        Row {
            x: 240
            anchors { bottom: parent.bottom; bottomMargin: 70 }
            spacing: 34
            Lb { text: root.bands ? "↑↓ band" : root.depth ? "↑↓ choose" : "↑↓ select" }
            Lb { text: root.bands ? "←→ less · more" : root.depth && !root.po?.go ? "↵ apply" : "↵ open" }
            Lb { text: root.bands ? "↵ done" : root.depth ? "esc back" : "esc close" }
        }
    }

    // столбец слов как в меню питания: выбранное крупно (длинное — мельче, чтобы не залезть под кольцо) с красной точкой,
    // остальные Mute. «current» — применённый сейчас вариант. Сдвиг и угасание при смене уровня — glide, Theme.t
    component Words: Column {
        id: wc
        property var items: []
        property int cur: 0
        property point keyAt // where the pointer was at the last key press
        signal hovered(int i)
        signal tapped(int i)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 26
        Behavior on x { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        Behavior on opacity { NumberAnimation { duration: Theme.t } }
        Repeater {
            model: wc.items
            Row {
                id: it
                required property var modelData
                required property int index
                readonly property bool on: wc.cur === index
                spacing: 30
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: it.on
                    width: 30
                    height: 30
                    radius: 15
                    color: Theme.accent
                }
                Num {
                    text: it.modelData.t
                    font.pixelSize: it.on ? Math.min(168, 900 / (it.modelData.t.length * 0.59)) : 66
                    color: it.on ? Theme.fg : Theme.mute
                    Behavior on font.pixelSize { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                    Behavior on color { ColorAnimation { duration: Theme.t } }
                }
                Lb {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: it.modelData.tag ?? (it.modelData.now ? "current" : "") // у жестов — что делает сейчас
                    color: it.on ? Theme.fg : Theme.grey
                }
                // local change: Qt re-sends hover when words slide or get rebuilt (5 s poll) under a still pointer; that used to
                // snap the selection back to the pointer and swallow ↑/↓. Hover counts only once the pointer left where the last key found it
                HoverHandler {
                    onHoveredChanged: if (hovered && (point.scenePosition.x !== wc.keyAt.x || point.scenePosition.y !== wc.keyAt.y)) wc.hovered(it.index)
                }
                TapHandler { onTapped: wc.tapped(it.index) }
            }
        }
    }
}
