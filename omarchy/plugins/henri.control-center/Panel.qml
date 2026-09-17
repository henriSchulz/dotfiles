import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// macOS-style Control Center. Everything here drives the same backends the
// stock panels use (Quickshell.Networking, Bluetooth, Pipewire, the shell's
// notification/nightlight/idle/media services, omarchy-brightness-display),
// so state stays in sync with the bar icons and the detail panels. Clicking a
// tile's round icon toggles it; clicking its label opens the stock detail
// panel, like the chevron in macOS.
Panel {
  id: root
  moduleName: "henri.control-center"
  ipcTarget: "henri.control-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var shell: bar ? bar.shell : null

  // ---- Palette. Tiles are a faint wash of the foreground over the popup
  //      background; an "on" icon circle takes the accent colour.
  readonly property color fg: Color.popups.text
  readonly property color tileColor: Qt.rgba(fg.r, fg.g, fg.b, 0.07)
  readonly property color tileHover: Qt.rgba(fg.r, fg.g, fg.b, 0.11)
  readonly property color circleOff: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
  readonly property color circleOn: Color.accent
  readonly property color onIcon: Color.popups.background
  readonly property color dimText: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property string iconFont: bar ? bar.fontFamily : Style.font.family
  readonly property int tileRadius: Math.max(Style.space(12), Style.cornerRadius)
  readonly property int gap: Style.space(10)
  readonly property int panelWidth: Style.space(340)
  readonly property int colWidth: Math.floor((panelWidth - gap) / 2)

  // ---- Wi-Fi
  readonly property var wifiDevice: {
    var devices = Networking.devices ? Networking.devices.values : []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || d.type !== DeviceType.Wifi) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }
  readonly property string wifiName: {
    if (!wifiDevice || !wifiDevice.networks) return ""
    var nets = wifiDevice.networks.values
    for (var i = 0; i < nets.length; i++) if (nets[i] && nets[i].connected) return nets[i].name
    return ""
  }
  readonly property bool wifiOn: Networking.wifiEnabled

  // ---- Bluetooth
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btOn: btAdapter ? btAdapter.enabled : false
  readonly property var btConnected: {
    var list = []
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].connected) list.push(devices[i])
    return list
  }

  // ---- Services owned by the shell
  function service(ids) {
    if (!shell) return null
    for (var i = 0; i < ids.length; i++) {
      var s = shell.serviceFor(ids[i])
      if (s) return s
    }
    return null
  }
  readonly property var notifications: opened ? service(["omarchy.notifications"]) : null
  readonly property var nightlight: opened ? service(["omarchy.nightlight"]) : null
  readonly property var idle: opened ? service(["henri.idle", "omarchy.idle"]) : null
  readonly property var media: opened ? service(["omarchy.media"]) : null

  readonly property bool dnd: notifications ? notifications.doNotDisturb : false
  readonly property bool nightOn: nightlight ? nightlight.enabled : false
  readonly property bool stayAwake: idle ? idle.stayAwake : false

  // ---- Sound
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  // ---- Display brightness (polled on open; set through the Omarchy CLI so
  //      the stock display panel and keyboard keys agree with us).
  property int brightness: 0
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property int queuedBrightness: -1

  // ---- AirDrop stand-in: LocalSend
  property bool localsendRunning: false

  function run(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }

  function openDetail(pluginId) {
    close()
    run("sleep 0.15; omarchy-shell shell toggle " + pluginId)
  }

  function setBrightness(value) {
    var percent = Math.max(1, Math.min(100, Math.round(value)))
    brightness = percent
    if (brightnessProc.running) { queuedBrightness = percent; return }
    queuedBrightness = -1
    brightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", internalMonitor, percent + "%"]
    brightnessProc.running = true
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (!localsendProc.running) localsendProc.running = true
  }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: stateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var b = String(lines[0] || "").trim()
        root.brightnessAvailable = b !== "" && b !== "unavailable"
        if (root.brightnessAvailable) root.brightness = Math.max(0, Math.min(100, parseInt(b, 10)))
        root.internalMonitor = String(lines[1] || "").trim()
      }
    }
  }

  Process {
    id: brightnessProc
    onExited: if (root.queuedBrightness >= 0) root.setBrightness(root.queuedBrightness)
  }

  Process {
    id: localsendProc
    command: ["pgrep", "-x", "localsend"]
    onExited: function(code) { root.localsendRunning = code === 0 }
  }

  // ======================================================== components

  // Round icon button. `on` fills it with the accent colour.
  component Circle: Rectangle {
    id: circle
    property string icon: ""
    property bool on: false
    signal clicked()
    width: Style.space(30)
    height: width
    radius: width / 2
    color: on ? root.circleOn : root.circleOff
    scale: circleMouse.pressed ? 0.92 : 1
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 90 } }

    Text {
      anchors.centerIn: parent
      text: circle.icon
      font.family: root.iconFont
      font.pixelSize: Style.font.iconLarge
      color: circle.on ? root.onIcon : root.fg
    }
    MouseArea {
      id: circleMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: circle.clicked()
    }
  }

  component Tile: Rectangle {
    id: tile
    property bool hoverable: false
    signal clicked()
    radius: root.tileRadius
    color: hoverable && tileMouse.containsMouse ? root.tileHover : root.tileColor
    Behavior on color { ColorAnimation { duration: 100 } }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: tile.hoverable
      cursorShape: tile.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: tile.clicked()
    }
  }

  // Icon + two lines of text, used inside the connectivity tile and Focus.
  component ToggleRow: Item {
    id: row
    property string icon: ""
    property bool on: false
    property string title: ""
    property string subtitle: ""
    signal toggled()
    signal details()
    implicitHeight: Style.space(38)

    Circle {
      id: rowCircle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      icon: row.icon
      on: row.on
      onClicked: row.toggled()
    }
    Column {
      anchors.left: rowCircle.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      Text {
        width: parent.width
        text: row.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: row.subtitle
        visible: text !== ""
        color: root.dimText
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
    MouseArea {
      anchors.fill: parent
      anchors.leftMargin: rowCircle.width + Style.space(4)
      cursorShape: Qt.PointingHandCursor
      onClicked: row.details()
    }
  }

  // Small square tile: centred icon circle with a caption underneath.
  component SmallTile: Tile {
    id: small
    property string icon: ""
    property bool on: false
    property string title: ""
    hoverable: true
    width: Math.floor((root.colWidth - root.gap) / 2)
    height: Style.space(82)

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      spacing: Style.space(5)
      Circle {
        anchors.horizontalCenter: parent.horizontalCenter
        icon: small.icon
        on: small.on
        onClicked: small.clicked()
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: small.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 2
      }
    }
  }

  // Wide tile with a heading and a slider, like Display / Sound on macOS.
  component SliderTile: Tile {
    id: st
    property string heading: ""
    property string icon: ""
    property real value: 0
    signal moved(real value)
    signal iconClicked()
    signal headingClicked()
    width: root.panelWidth
    height: Style.space(66)

    Text {
      id: stHeading
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: Style.space(12)
      anchors.topMargin: Style.space(9)
      text: st.heading
      color: root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.weight: Font.DemiBold
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: st.headingClicked()
      }
    }
    Text {
      id: stIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: stSlider.verticalCenter
      width: Style.space(20)
      text: st.icon
      color: root.fg
      font.family: root.iconFont
      font.pixelSize: Style.font.iconLarge
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        cursorShape: Qt.PointingHandCursor
        onClicked: st.iconClicked()
      }
    }
    PanelSlider {
      id: stSlider
      anchors.left: stIcon.right
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(14)
      anchors.bottomMargin: Style.space(6)
      bar: root.bar
      minimum: 0
      maximum: 1
      step: 0.05
      value: st.value
      fillColor: root.fg
      knobColor: root.fg
      trackColor: root.circleOff
      tickColor: "transparent"
      onMoved: function(v) { st.moved(v) }
    }
  }

  // ============================================================== layout

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: root.gap
    contentWidth: root.panelWidth + root.gap * 2
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Column {
      id: content
      width: root.panelWidth
      spacing: root.gap

      // Top block: connectivity on the left, Focus + small toggles on the right.
      Row {
        spacing: root.gap

        Tile {
          width: root.colWidth
          height: connectivity.implicitHeight + Style.space(20)

          Column {
            id: connectivity
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(4)

            ToggleRow {
              width: parent.width
              icon: root.wifiOn ? "󰖩" : "󰖪"
              on: root.wifiOn
              title: "WLAN"
              subtitle: !root.wifiOn ? "Aus" : (root.wifiName !== "" ? root.wifiName : "Nicht verbunden")
              onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
              onDetails: root.openDetail("omarchy.network")
            }
            ToggleRow {
              width: parent.width
              icon: root.btOn ? "󰂯" : "󰂲"
              on: root.btOn
              title: "Bluetooth"
              subtitle: !root.btOn ? "Aus"
                : root.btConnected.length === 1 ? (root.btConnected[0].name || "1 Gerät")
                : root.btConnected.length > 1 ? root.btConnected.length + " Geräte"
                : "Ein"
              // omarchy-bluetooth-power persists the state (see the stock panel).
              onToggled: Quickshell.execDetached(["omarchy-bluetooth-power", root.btOn ? "off" : "on"])
              onDetails: root.openDetail("omarchy.bluetooth")
            }
            ToggleRow {
              width: parent.width
              icon: "󰜡"
              on: root.localsendRunning
              title: "AirDrop"
              subtitle: root.localsendRunning ? "LocalSend aktiv" : "LocalSend"
              onToggled: {
                if (root.localsendRunning) {
                  root.run("pkill -x localsend")
                  root.localsendRunning = false
                } else {
                  root.run("setsid -f localsend >/dev/null 2>&1")
                  root.localsendRunning = true
                }
              }
              onDetails: { root.close(); root.run("omarchy-launch-or-focus localsend 'setsid -f localsend'") }
            }
          }
        }

        Column {
          spacing: root.gap

          Tile {
            width: root.colWidth
            height: Style.space(52)
            hoverable: true
            onClicked: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)

            ToggleRow {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(6)
              icon: "󰽥"
              on: root.dnd
              title: "Fokus"
              subtitle: root.dnd ? "Nicht stören" : ""
              onToggled: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)
              onDetails: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)
            }
          }

          Row {
            spacing: root.gap
            SmallTile {
              icon: "󰖔"
              on: root.nightOn
              title: "Night Shift"
              onClicked: if (root.nightlight) root.nightlight.setNightlight(!root.nightOn)
            }
            SmallTile {
              icon: "󰅶"
              on: root.stayAwake
              title: "Wach bleiben"
              onClicked: if (root.idle) root.idle.setIdleEnabled(root.stayAwake)
            }
          }
        }
      }

      SliderTile {
        visible: root.brightnessAvailable
        heading: "Bildschirm"
        icon: root.brightness < 40 ? "󰃞" : root.brightness < 75 ? "󰃟" : "󰃠"
        value: root.brightness / 100
        onMoved: function(v) { root.setBrightness(v * 100) }
        onHeadingClicked: root.openDetail("omarchy.monitor")
        onIconClicked: root.openDetail("omarchy.monitor")
      }

      SliderTile {
        visible: root.sink !== null
        heading: "Ton"
        icon: root.muted || root.volume === 0 ? "󰝟" : root.volume < 0.34 ? "󰕿" : root.volume < 0.67 ? "󰖀" : "󰕾"
        value: root.muted ? 0 : Math.min(1, root.volume)
        onMoved: function(v) {
          if (!root.sink || !root.sink.audio) return
          root.sink.audio.volume = v
          if (root.muted && v > 0) root.sink.audio.muted = false
        }
        onIconClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.muted
        onHeadingClicked: root.openDetail("omarchy.audio")
      }

      // Now Playing — only while an MPRIS player has a track.
      Tile {
        id: nowPlaying
        readonly property bool playing: root.media && root.media.activePlayer ? root.media.activePlayer.isPlaying === true : false
        visible: root.media ? root.media.hasMedia === true : false
        width: root.panelWidth
        height: Style.space(64)

        Rectangle {
          id: art
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(44)
          height: width
          radius: Style.space(8)
          color: root.circleOff
          clip: true

          Text {
            anchors.centerIn: parent
            visible: artImage.status !== Image.Ready
            text: "󰝚"
            color: root.dimText
            font.family: root.iconFont
            font.pixelSize: Style.font.iconLarge
          }
          Image {
            id: artImage
            anchors.fill: parent
            source: root.media ? root.media.artUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: width * 2
            sourceSize.height: height * 2
          }
        }

        Column {
          anchors.left: art.right
          anchors.leftMargin: Style.space(10)
          anchors.right: controls.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: root.media ? root.media.title : ""
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.media ? (root.media.artist || root.media.identity) : ""
            color: root.dimText
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Repeater {
            model: [
              { icon: "󰒮", action: "previous" },
              { icon: nowPlaying.playing ? "󰏤" : "󰐊", action: "playPause" },
              { icon: "󰒭", action: "next" }
            ]
            delegate: Rectangle {
              required property var modelData
              width: Style.space(30)
              height: width
              radius: width / 2
              color: controlMouse.containsMouse ? root.circleOff : "transparent"
              Text {
                anchors.centerIn: parent
                text: modelData.icon
                color: root.fg
                font.family: root.iconFont
                font.pixelSize: Style.font.iconLarge
              }
              MouseArea {
                id: controlMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.media) root.media.runAction(modelData.action, false)
              }
            }
          }
        }
      }
    }
  }
}
