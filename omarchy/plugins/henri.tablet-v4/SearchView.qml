import QtQuick
import QtQuick.Effects
import "file:///home/henri/.local/share/velum/qml/Velum"
import "SearchScore.js" as SS

// The tablet's search (phase 2 of docs/TABLET-V4-PLAN.md): Material 3's search bar grows into a search
// view at the top of the screen (lab/mui-material/src/SearchView.jsx). Results: Apps (a grid of the
// home grid's columns), the apps' own desktop actions ("New Terminal") as rows with the app's icon and
// name, and "Search the web for …". Apps match by the start of the name, then the start of a word, then
// anywhere, plus a category prefix (SearchScore.js). Enter opens the first result, Escape or the back
// arrow closes, a tap beside the view closes. Empty: the suggested apps. Floating surface = Velum's
// popover glass and shadow over a scrim: a downscaled, blurred copy of the screen taken once per open
// (never a live blur), dimmed. Tokens: surface.material.search.
//
// It launches nothing — the owner (the home) does, on the signals. Place it over the whole screen
// area (it fills its parent) above the item given as `backdropSource`; the window must give it the
// keyboard while it is open. Wrap it in a Loader if it should cost nothing while closed.
//
// API
//   apps: [{ id, name, icon (url), cats: [string], actions: [{ id, name, command? }], launcherHidden? }]
//         or a map id → app. launcherHidden apps (Omarchy's helpers) are never found.
//   suggested: [id]          shown while the query is empty (default: the first apps A–Z)
//   columns: int             the result grid's columns (the home grid's; token default 6)
//   topInset, bottomInset    kept free (status bar, keyboard)
//   backdropSource: Item     what lies under the view (same window, not containing the view): taken
//                            once per open, blurred under the scrim; null = the scrim alone
//   closeOnActivate: bool    close after a result is chosen (default true)
//   text: string             the query (read/write)
//   readonly shown           open (or opening); readonly active: on screen (also while closing)
//   readonly results         { query, apps, actions: [{ app, action }], first }
//   open(initialText, fromRect)   fromRect = the search bar in this item's coordinates (the view
//                            grows out of it; omitted = scale from the token's fromScale). Typing on a
//                            keyboard while the home shows: open(thatLetter, barRect).
//   close(), submit() (= Enter), clear()
//   signals: openApp(id), runAction(id, action) (action = { id, name, command }), webSearch(text),
//            voiceSearch(), closed() (after the close motion ended)
Item {
  id: view
  anchors.fill: parent

  property var apps: []
  property var suggested: []
  property int columns: cfg.columns
  property rect fromRect: Qt.rect(0, 0, 0, 0)
  property real topInset: 0
  property real bottomInset: 0
  property Item backdropSource: null
  property bool closeOnActivate: true
  property string text: ""
  readonly property bool shown: _shown
  readonly property bool active: visible
  readonly property var results: _results

  signal openApp(string id)
  signal runAction(string id, var action)
  signal webSearch(string text)
  signal voiceSearch()
  signal closed()

  readonly property var cfg: Theme.core.surface.material.search
  property bool _shown: false
  property var _results: ({ query: "", apps: [], actions: [], first: null })
  // for tests: the last thing chosen ("app:ID", "action:ID:ACTION", "web:TEXT", "voice")
  property string lastActivated: ""

  // ---- look: Material base (Roboto, bundled by the plugin), Velum's glass, the variant's accent
  // Roboto: the plugin's one FontLoader set (Home.qml, fonts/) registers it for the whole shell
  readonly property string family: Theme.core.surface.material.widgets.font[0]
  readonly property color ink: Theme.r.popover.ink
  readonly property color inkSecondary: Theme.r.popover.inkSecondary
  readonly property color firstFill: Qt.alpha(Theme.r.accent.base, cfg.firstTint)

  // ---- motion: one Velum Spring 0 → 1; transform and opacity only
  Spring {
    id: grow
    preset: view._shown ? ({ response: view.cfg.openResponse * Theme.speed, dampingRatio: view.cfg.openDamping })
      : ({ response: view.cfg.openResponse * Theme.speed * Theme.core.motion.exitFactor, dampingRatio: view.cfg.openDamping })
    target: view._shown ? 1 : 0
  }
  readonly property real fade: Math.max(0, Math.min(1, grow.value))
  // reduced motion: the view stands where it ends and only fades
  readonly property real k: Theme.reduceMotion ? 1 : grow.value
  visible: _shown || grow.value > 0
  Connections {
    target: grow
    function onMovingChanged() { if (!grow.moving && !view._shown) view._finishClose() }
  }

  function open(initialText, from) {
    if (from !== undefined && from !== null) fromRect = from
    text = initialText ? String(initialText) : ""
    if (!_shown) {
      _snapRect = backdropSource ? backdropSource.mapToItem(view, 0, 0, backdropSource.width, backdropSource.height) : Qt.rect(0, 0, 0, 0)
      _shown = true
    }
    refresh()
    list.contentY = 0
    Qt.callLater(function () { field.forceActiveFocus(); field.cursorPosition = field.text.length })
  }
  function close() {
    if (!_shown) return
    _shown = false
    field.focus = false
    if (!grow.moving) _finishClose()
  }
  function _finishClose() {
    if (_shown || grow.value > 0) return
    text = ""
    _results = { query: "", apps: [], actions: [], first: null }
    closed()
  }
  function clear() { text = ""; field.forceActiveFocus() }
  function submit() { if (_results.first) activate(_results.first) }
  function activate(r) {
    if (!r) return
    if (r.kind === "app") { lastActivated = "app:" + r.app.id; openApp(r.app.id) }
    else if (r.kind === "action") { lastActivated = "action:" + r.app.id + ":" + r.action.id; runAction(r.app.id, r.action) }
    else if (r.kind === "web") { lastActivated = "web:" + r.text; webSearch(r.text) }
    else if (r.kind === "voice") { lastActivated = "voice"; voiceSearch() }
    if (closeOnActivate) close()
  }
  // filtering runs on a change of the query or the apps, only while the view is up
  function refresh() {
    if (!_shown) return
    _results = SS.search(apps, text, suggested, { apps: cfg.apps, actions: cfg.actions })
  }
  onTextChanged: { if (field.text !== text) field.text = text; refresh() }
  onAppsChanged: refresh()
  onSuggestedChanged: refresh()

  // ---- geometry: the view at the top, the width of a search bar; grown out of `fromRect`
  readonly property real viewW: Math.max(cfg.barHeight, Math.min(width - 2 * cfg.edge, cfg.maxWidth))
  readonly property real viewX: Math.round((width - viewW) / 2)
  readonly property real viewY: topInset + cfg.edge
  readonly property real maxH: Math.max(cfg.barHeight, height - viewY - cfg.edge - bottomInset)
  readonly property real panelH: Math.min(maxH, cfg.barHeight + resultsCol.implicitHeight + cfg.pad)
  readonly property bool fromBar: fromRect.width > 0 && fromRect.height > 0
  readonly property real sx: fromBar ? fromRect.width / viewW : cfg.fromScale
  readonly property real sy: fromBar ? fromRect.height / cfg.barHeight : cfg.fromScale
  readonly property real tx: fromBar ? fromRect.x - viewX : viewW * (1 - cfg.fromScale) / 2
  readonly property real ty: fromBar ? fromRect.y - viewY : 0
  property rect _snapRect: Qt.rect(0, 0, 0, 0)

  // ---- the scrim: the screen under the view, taken once and blurred, then dimmed
  Loader {
    anchors.fill: parent
    opacity: view.fade
    active: view.visible && view.backdropSource !== null && !Theme.reduceTransparency
    sourceComponent: Item {
      ShaderEffectSource {
        id: snap
        x: view._snapRect.x; y: view._snapRect.y; width: view._snapRect.width; height: view._snapRect.height
        sourceItem: view.backdropSource
        live: false
        hideSource: false
        visible: false
        textureSize: Qt.size(Math.max(1, Math.round(width / view.cfg.blurDownscale)), Math.max(1, Math.round(height / view.cfg.blurDownscale)))
      }
      MultiEffect {
        x: snap.x; y: snap.y; width: snap.width; height: snap.height
        source: snap
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: view.cfg.blur
      }
    }
  }
  Rectangle {
    anchors.fill: parent
    color: view.cfg.scrim
    opacity: view.fade
  }
  // a tap beside the view closes it (and goes nowhere else)
  MouseArea {
    anchors.fill: parent
    enabled: view._shown
    onClicked: view.close()
  }

  // ---- the view
  Item {
    id: panel
    property string velumSurface: "popover"
    x: view.viewX
    y: view.viewY
    width: view.viewW
    height: view.panelH
    opacity: view.fade
    transform: [
      Scale { xScale: view.sx + (1 - view.sx) * view.k; yScale: view.sy + (1 - view.sy) * view.k },
      Translate { x: view.tx * (1 - view.k); y: view.ty * (1 - view.k) }
    ]

    VShadow { layers: Theme.r.popover.shadow; radius: view.cfg.barHeight / 2 }
    Rectangle {
      anchors.fill: parent
      radius: view.cfg.barHeight / 2
      color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
      border.width: 1 / Screen.devicePixelRatio
      border.color: Theme.r.line.rim
    }
    // taps on the view's empty parts stay on it
    MouseArea { anchors.fill: parent }

    // header: back · query · clear or mic
    Item {
      id: header
      width: parent.width
      height: view.cfg.barHeight
      RoundButton {
        id: back
        x: view.cfg.pad
        anchors.verticalCenter: parent.verticalCenter
        glyph: "arrow-left"
        onClicked: view.close()
      }
      TextInput {
        id: field
        x: back.x + back.width + view.cfg.pad
        width: trailing.x - view.cfg.pad - x
        anchors.verticalCenter: parent.verticalCenter
        font.family: view.family
        font.pixelSize: view.cfg.inputSize
        font.weight: view.cfg.weightRegular
        color: view.ink
        selectionColor: Qt.alpha(Theme.r.accent.base, view.cfg.firstTint)
        selectedTextColor: view.ink
        clip: true
        onTextEdited: view.text = text
        Keys.onEscapePressed: view.close()
        Keys.onReturnPressed: view.submit()
        Keys.onEnterPressed: view.submit()
        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: field.text === "" && field.preeditText === ""
          text: "Search apps and actions"
          font: field.font
          color: view.inkSecondary
          elide: Text.ElideRight
        }
      }
      RoundButton {
        id: trailing
        x: parent.width - view.cfg.pad - width
        anchors.verticalCenter: parent.verticalCenter
        glyph: view.text !== "" ? "x" : "microphone"
        onClicked: view.text !== "" ? view.clear() : view.activate({ kind: "voice" })
      }
    }

    // results
    Flickable {
      id: list
      y: header.height
      width: parent.width
      height: Math.max(0, parent.height - header.height - view.cfg.pad)
      contentHeight: resultsCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickDeceleration: Theme.core.motion.scroll.flickDeceleration
      maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity
      opacity: Math.max(0, Math.min(1, (view.fade - view.cfg.contentFrom) / (1 - view.cfg.contentFrom)))

      Column {
        id: resultsCol
        x: view.cfg.pad
        width: list.width - 2 * view.cfg.pad
        readonly property var r: view._results
        readonly property bool typed: r.query !== ""

        Subheader { text: resultsCol.typed ? "Apps" : "Suggested"; visible: resultsCol.r.apps.length > 0 }
        Grid {
          id: grid
          visible: resultsCol.r.apps.length > 0
          columns: Math.max(1, view.columns)
          columnSpacing: view.cfg.tileGap
          rowSpacing: view.cfg.tileGap
          readonly property real tileW: (resultsCol.width - (columns - 1) * columnSpacing) / columns
          Repeater {
            model: resultsCol.r.apps
            delegate: Item {
              id: tile
              required property var modelData
              required property int index
              width: grid.tileW
              height: view.cfg.tilePadY * 2 + view.cfg.resultIcon + view.cfg.tileLabelGap + label.implicitHeight
              Rectangle {
                anchors.fill: parent
                radius: view.cfg.radius
                color: view.firstFill
                visible: tile.index === 0 && resultsCol.typed
              }
              PressLayer { pressed: tileTap.pressed; radius: view.cfg.radius }
              Image {
                y: view.cfg.tilePadY
                anchors.horizontalCenter: parent.horizontalCenter
                width: view.cfg.resultIcon; height: view.cfg.resultIcon
                sourceSize.width: view.cfg.resultIcon; sourceSize.height: view.cfg.resultIcon
                source: tile.modelData.icon || ""
                asynchronous: true
                smooth: true
              }
              Text {
                id: label
                y: view.cfg.tilePadY + view.cfg.resultIcon + view.cfg.tileLabelGap
                x: view.cfg.tileLabelPadX
                width: parent.width - 2 * view.cfg.tileLabelPadX
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.modelData.name
                font.family: view.family
                font.pixelSize: view.cfg.labelSize
                color: view.ink
              }
              TapHandler { id: tileTap; onTapped: view.activate({ kind: "app", app: tile.modelData }) }
            }
          }
        }
        Subheader { text: "Actions"; visible: resultsCol.r.actions.length > 0 }
        Repeater {
          model: resultsCol.r.actions
          delegate: Row2 {
            required property var modelData
            required property int index
            highlighted: index === 0 && resultsCol.r.apps.length === 0
            title: modelData.action.name
            subtitle: modelData.app.name
            iconSource: modelData.app.icon || ""
            onClicked: view.activate({ kind: "action", app: modelData.app, action: modelData.action })
          }
        }
        Text {
          visible: resultsCol.typed && resultsCol.r.apps.length === 0 && resultsCol.r.actions.length === 0
          width: resultsCol.width
          leftPadding: view.cfg.subheaderPadX
          topPadding: view.cfg.emptyPadY
          bottomPadding: view.cfg.emptyPadY
          text: "No apps or actions match."
          font.family: view.family
          font.pixelSize: view.cfg.rowSize
          color: view.inkSecondary
        }
        Row2 {
          visible: resultsCol.typed
          height: view.cfg.rowOne
          highlighted: resultsCol.r.apps.length === 0 && resultsCol.r.actions.length === 0
          glyph: "globe"
          title: "Search the web for “" + view.text.trim() + "”"
          onClicked: view.activate({ kind: "web", text: view.text.trim() })
        }
      }
    }
  }

  // ---- parts
  component Subheader: Text {
    width: resultsCol.width
    height: view.cfg.subheader
    leftPadding: view.cfg.subheaderPadX
    verticalAlignment: Text.AlignVCenter
    font.family: view.family
    font.pixelSize: view.cfg.rowSize
    font.weight: view.cfg.weightMedium
    color: view.inkSecondary
  }
  // Material's state layer under a finger (no ripple: one opacity, nothing moves)
  component PressLayer: Rectangle {
    property bool pressed: false
    anchors.fill: parent
    color: view.ink
    opacity: pressed ? Theme.core.alpha.pressed : 0
    Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
  }
  component Glyph: Text {
    property string name: ""
    font.family: Theme.iconFamily("bold")
    font.pixelSize: view.cfg.glyph
    text: Theme.glyph(name, "bold")
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
  component RoundButton: Item {
    id: rb
    property string glyph: ""
    signal clicked()
    width: view.cfg.button
    height: view.cfg.button
    PressLayer { pressed: rbTap.pressed; radius: width / 2 }
    Glyph { anchors.fill: parent; name: rb.glyph; color: view.ink }
    TapHandler { id: rbTap; onTapped: rb.clicked() }
  }
  // a list row: app icon (or a glyph), a title and an optional second line
  component Row2: Item {
    id: row
    property bool highlighted: false
    property string title: ""
    property string subtitle: ""
    property string iconSource: ""
    property string glyph: ""
    signal clicked()
    width: resultsCol.width
    height: subtitle !== "" ? view.cfg.rowTwo : view.cfg.rowOne
    Rectangle { anchors.fill: parent; radius: view.cfg.radius; color: view.firstFill; visible: row.highlighted }
    PressLayer { pressed: rowTap.pressed; radius: view.cfg.radius }
    Image {
      visible: row.iconSource !== ""
      x: view.cfg.rowPadX
      anchors.verticalCenter: parent.verticalCenter
      width: view.cfg.rowIcon; height: view.cfg.rowIcon
      sourceSize.width: view.cfg.rowIcon; sourceSize.height: view.cfg.rowIcon
      source: row.iconSource
      asynchronous: true
      smooth: true
    }
    Glyph {
      visible: row.glyph !== ""
      x: view.cfg.rowPadX
      width: view.cfg.rowIcon; height: parent.height
      name: row.glyph
      color: view.inkSecondary
    }
    Column {
      x: view.cfg.rowPadX + view.cfg.rowIconColumn
      width: parent.width - x - view.cfg.rowPadX
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        text: row.title
        elide: Text.ElideRight
        font.family: view.family
        font.pixelSize: view.cfg.rowSize
        font.weight: view.cfg.weightMedium
        color: view.ink
      }
      Text {
        visible: row.subtitle !== ""
        width: parent.width
        text: row.subtitle
        elide: Text.ElideRight
        font.family: view.family
        font.pixelSize: view.cfg.rowSize
        color: view.inkSecondary
      }
    }
    TapHandler { id: rowTap; onTapped: row.clicked() }
  }
}
