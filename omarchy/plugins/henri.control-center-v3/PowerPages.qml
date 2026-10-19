import QtQuick
import "Model.js" as Model
import "file:///home/henri/.local/share/velum/qml/Velum"

// The battery menu as Control Center pages: Overview and History.
// Faceless itself — it hands out the three pages as Components for the host's
// VPageStack (the Control Center, and the right island of the bar through
// henri.power-v3), and asks the host to push or go back. All values come from
// a PowerService (`svc`).
//
//   PowerPages { id: power; svc: powerSvc; onPushRequested: n => host.push(n); onBackRequested: host.back() }
//   stack.push(power.page("battery"))      // battery | battery-history
Item {
  id: pp
  property var svc: null
  property bool standalone: false   // the host's first page (the bar island): the overview has no way back
  signal pushRequested(string name)
  signal backRequested()
  function page(name) { return name === "battery-history" ? historyPage : name === "battery" ? overviewPage : null }
  // the History page's range menu
  property bool rangeOpen: false
  visible: false

  // ---- parts
  component MRow: VModuleRow { width: parent ? parent.width : implicitWidth }
  component MHead: VPageHead { width: parent ? parent.width : implicitWidth; onBack: pp.backRequested() }
  component MSection: VModuleSection { width: parent ? parent.width : 0 }
  component DrillRow: MRow {
    VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary }
  }
  component Caption: VText {
    x: Theme.layout.module.pad; width: (parent ? parent.width : 0) - 2 * x
    wrapMode: Text.WordWrap; tone: "secondary"; font.pixelSize: Theme.m.type.small
    bottomPadding: Theme.layout.list.gap
  }
  // Segmented control over values: `current` picks the plate, busy dims it
  component Segmented: Item {
    id: seg
    property var options: []
    property var labels: []
    property string current: ""
    property bool busy: false
    signal picked(string value)
    width: parent ? parent.width : 0
    height: Theme.m.control.height + Theme.layout.list.gap
    opacity: busy ? Theme.core.alpha.disabled : 1
    Behavior on opacity { NumberAnimation { duration: Theme.dur("fast") } }
    VSegment {
      id: segCtl
      x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
      model: seg.options.map(function (o, i) { return seg.labels[i] !== undefined ? seg.labels[i] : String(o) })
      enabled: !seg.busy
      onActivated: i => seg.picked(String(seg.options[i]))
    }
    // re-applied on every change (a click inside VSegment would cut a plain binding)
    Binding { target: segCtl; property: "currentIndex"; value: Math.max(0, seg.options.indexOf(seg.current)) }
  }

  // ================================================================ Overview
  Component {
    id: overviewPage
    Column {
      id: ov
      spacing: Theme.layout.module.gap
      readonly property var s: pp.svc
      readonly property real third: (width - 2 * spacing) / 3
      MHead { visible: !pp.standalone; title: "Battery" }
      Item {
        visible: pp.standalone; width: parent.width; height: visible ? Theme.layout.module.head : 0
        VText { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; text: "Battery"
          color: Theme.r.popover.ink; font.pixelSize: Theme.m.type.title; font.weight: Font.DemiBold }
      }

      // -- the battery, the level, what it is doing
      VTile {
        width: parent.width; height: Theme.layout.meter.hero
        VBatteryArt {
          id: art
          x: Theme.layout.module.pad * 2; anchors.verticalCenter: parent.verticalCenter
          level: ov.s.batteryFraction; charging: ov.s.charging; plugged: ov.s.plugged
        }
        Column {
          x: art.x + art.width + Theme.layout.module.pad * 2; width: parent.width - x - Theme.layout.module.pad
          anchors.verticalCenter: parent.verticalCenter
          VCrossfadeText { width: parent.width; text: Math.round(ov.s.batteryFraction * 100) + " %"; color: Theme.r.popover.ink
            pixelSize: Theme.core.type.largeTitle; weight: Font.DemiBold }
          VCrossfadeText { width: parent.width; elide: Text.ElideRight; tone: "secondary"; color: Theme.r.popover.inkSecondary
            text: ov.s.statusText + (ov.s.timeText !== "—" && !ov.s.chargeThresholdActive ? " · " + ov.s.timeText : "") }
        }
      }

      // -- the charge limit: the level on a track with the thresholds (drag a marker to change it)
      Group {
        visible: ov.s.dellThresholdsReady || ov.s.dellError !== ""
        title: ov.s.dellThresholdsReady ? "Charge Limit" : ""
        titleDetail: ov.s.dellThresholdsReady ? ov.s.effStart() + " – " + ov.s.effEnd() + " %" : ""
        ChargeBar { visible: ov.s.dellThresholdsReady; x: Theme.layout.module.pad; width: parent.width - 2 * x }
        Caption { visible: ov.s.dellThresholdsReady && !ov.s.thresholdsLive
          text: "Inactive (mode " + (ov.s.dellStatus ? ov.s.dellStatus.mode : "?") + "). Drag a marker to apply." }
        Caption { visible: ov.s.dellError !== ""; text: ov.s.dellError; color: Theme.r.danger; topPadding: Theme.layout.list.gap }
      }

      // -- the last hours (opens History)
      VTile {
        id: hist
        visible: ov.s.historyBars.length > 0
        width: parent.width; height: histCol.height + Theme.layout.module.section + Theme.layout.module.tileInset
        VText { x: Theme.layout.module.pad; height: Theme.layout.module.section; verticalAlignment: Text.AlignVCenter
          text: "Last " + ov.s.historyRange.label; font.weight: Font.DemiBold; color: Theme.r.popover.ink }
        VIcon { anchors.right: parent.right; anchors.rightMargin: Theme.layout.module.pad; y: (Theme.layout.module.section - height) / 2
          name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.r.popover.fillHover; visible: histMouse.containsMouse }
        MouseArea { id: histMouse; anchors.fill: parent; hoverEnabled: true; onClicked: pp.pushRequested("battery-history") }
        Column {
          id: histCol
          x: Theme.layout.module.pad; y: Theme.layout.module.section; width: parent.width - 2 * x; spacing: Theme.layout.list.gap / 2
          bottomPadding: Theme.layout.module.pad - Theme.layout.module.tileInset
          VChart {
            width: parent.width
            values: ov.s.historyBars.map(b => b ? b.pct / 100 : null)
            marks: ov.s.historyBars.map(b => !!b && !b.battery)
          }
          Item {
            width: parent.width; height: hAgo.height
            VText { id: hAgo; text: ov.s.historyRange.label + " ago"; tone: "secondary"; font.pixelSize: Theme.m.type.small }
            Row {
              anchors.centerIn: parent; spacing: Theme.layout.list.gap / 2
              visible: ov.s.historyBars.some(b => !!b && !b.battery)
              Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.layout.meter.dot; height: width; radius: Theme.m.radius.chip / 4
                color: Qt.alpha(Theme.r.success.base, 0.35) }   // the chart's plugged-in ground, a little stronger to read as a key
              VText { text: "Plugged In"; tone: "secondary"; font.pixelSize: Theme.m.type.small }
            }
            VText { anchors.right: parent.right; text: "Now"; tone: "secondary"; font.pixelSize: Theme.m.type.small }
          }
        }
      }

      // -- numbers
      Grid {
        columns: 3; spacing: ov.spacing
        VStatTile { width: ov.third; label: ov.s.timeLabel; value: ov.s.timeText }
        VStatTile { width: ov.third; label: ov.s.flowLabel; value: ov.s.flowText }
        VStatTile { width: ov.third; label: "Health"; value: ov.s.health >= 0 ? Math.round(ov.s.health * 100) + " %" : "—" }
        VStatTile { width: ov.third; label: "Capacity"; value: ov.s.sizeText }
        VStatTile { width: ov.third; label: "Cycles"; value: ov.s.batteryInfo.cycles || "—" }
        VStatTile { width: ov.third; label: "Power Source"; value: ov.s.discharging ? "Battery"
          : ov.s.powerChain && ov.s.powerChain.source === "typec" ? "USB-C" : "Adapter" }
      }

      // -- power profile as cards
      Row {
        visible: ov.s.profiles.length > 0
        spacing: ov.spacing
        readonly property real cell: (ov.width - (ov.s.profiles.length - 1) * spacing) / Math.max(1, ov.s.profiles.length)
        Repeater {
          model: ov.s.profiles
          ModeCard { required property var modelData
            width: parent.cell; icon: ov.s.profileIcon(modelData); label: ov.s.profileLabel(modelData)
            selected: ov.s.activeProfile === modelData; onChosen: ov.s.setProfile(modelData) }
        }
      }

      Group {
        DrillRow { icon: "recents"; text: "History"; onClicked: pp.pushRequested("battery-history") }
      }
    }
  }

  // ================================================================ History
  Component {
    id: historyPage
    Item {
      id: hp
      readonly property var s: pp.svc
      implicitHeight: hcol.height
      Column {
        id: hcol
        width: parent.width
        spacing: Theme.layout.module.gap
        MHead {
          title: "Battery History"
          PopUpButton { text: hp.s.historyRange.short; open: pp.rangeOpen; onClicked: pp.rangeOpen = !pp.rangeOpen }
        }
        Group {
          // what the bars show: charge, power, voltage or current
          Segmented { options: hp.s.historyMetricKeys; labels: hp.s.historyMetricLabels; current: hp.s.historyMetric.key
            onPicked: v => hp.s.setHistoryMetric(v) }
          VCrossfadeText { x: Theme.layout.module.pad; width: parent.width - 2 * x; height: implicitHeight + Theme.layout.list.gap
            text: graph.readout; tone: "secondary"; color: Theme.r.popover.inkSecondary; pixelSize: Theme.m.type.small }
          HistoryGraph { id: graph; x: Theme.layout.module.pad; width: parent.width - 2 * x; svc: hp.s }
          Item { width: 1; height: Theme.layout.module.pad }
        }
        Grid {
          id: hgrid
          visible: hp.s.historyStats !== null && hp.s.historyStats.samples
          columns: 2; spacing: Theme.layout.module.gap
          readonly property real cell: (hcol.width - spacing) / 2
          VStatTile { width: hgrid.cell; label: "Time on Battery"; value: hp.s.historyStats ? hp.s.durationText(hp.s.historyStats.onBatteryH) : "—" }
          VStatTile { width: hgrid.cell; label: "Used on Battery"; value: hp.s.historyStats ? hp.s.historyWh(hp.s.historyStats.usedWh) : "—" }
          VStatTile { width: hgrid.cell; label: "Average Draw"; value: hp.s.historyStats ? hp.s.historyWatt(hp.s.historyStats.avgDrawW) : "—" }
          VStatTile { width: hgrid.cell; label: "A Full Charge Lasts"
            value: hp.s.historyStats && hp.s.historyStats.runtimeH !== null ? "≈ " + hp.s.durationText(hp.s.historyStats.runtimeH) : "—" }
        }
        Group {
          visible: dis.text !== "" || chg.text !== "" || empty.visible
          Caption { id: dis; visible: text !== ""; topPadding: Theme.layout.list.gap; text: hp.s.historyDischargeText }
          Caption { id: chg; visible: text !== ""; topPadding: Theme.layout.list.gap; text: hp.s.historyChargeText }
          Caption { id: empty; visible: hp.s.historyStats !== null && !hp.s.historyStats.samples; topPadding: Theme.layout.list.gap
            text: "No samples in " + hp.s.historyDir }
        }
      }
      // the range menu drops out of the head's button; a click beside it only closes it
      MouseArea { anchors.fill: parent; z: 9; enabled: pp.rangeOpen; visible: enabled; acceptedButtons: Qt.AllButtons; onPressed: pp.rangeOpen = false }
      VMenu {
        id: rangeMenu
        z: 10
        open: pp.rangeOpen
        x: parent.width - width - Theme.layout.module.pad; y: Theme.layout.module.head
        model: {
          var cur = hp.s.historyRange, out = [], list = hp.s.historyRanges
          for (var i = 0; i < list.length; i++) {
            // minutes, hours, days: a separator between the groups
            if (i > 0 && (list[i].hours >= 1 !== list[i - 1].hours >= 1 || list[i].hours > 24 !== list[i - 1].hours > 24)) out.push({ separator: true })
            out.push({ text: list[i].label, rangeKey: list[i].key, key: list[i] === cur ? "Current" : "" })
          }
          return out
        }
        onTriggered: index => { pp.rangeOpen = false; hp.s.setHistoryRange(model[index].rangeKey) }
      }
      Component.onDestruction: pp.rangeOpen = false
    }
  }

  // ================================================================ components

  // The charge level on a track, the thresholds drawn onto it: an accent zone between start
  // and stop, a marker at each end. Drag a marker to change it (the helper switches the mode
  // to Custom, so an inactive zone comes alive on the first drag).
  component ChargeBar: Item {
    id: chargeBar
    readonly property var s: pp.svc
    readonly property real trackH: Theme.layout.list.gap
    readonly property bool low: s.batteryFraction <= 0.2 && s.discharging
    height: Theme.layout.icon.large + Theme.layout.module.pad
    Rectangle { id: barTrack; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      height: chargeBar.trackH; radius: height / 2; color: Theme.r.popover.switchOff }
    Rectangle {
      x: barTrack.width * chargeBar.s.effStart() / 100
      width: Math.max(0, barTrack.width * (chargeBar.s.effEnd() - chargeBar.s.effStart()) / 100)
      anchors.verticalCenter: barTrack.verticalCenter; height: barTrack.height; radius: barTrack.radius
      color: Theme.r.fill.selected
      opacity: chargeBar.s.thresholdsLive ? 1 : Theme.core.alpha.disabled
    }
    VMeter { anchors.left: barTrack.left; anchors.right: barTrack.right; anchors.verticalCenter: barTrack.verticalCenter; height: barTrack.height
      track: "transparent"; value: chargeBar.s.batteryFraction
      color: chargeBar.low ? Theme.r.danger : Theme.r.accent.base; colorTop: chargeBar.low ? Theme.r.danger : Theme.r.accent.top }
    ThresholdMarker { percent: chargeBar.s.effStart(); dragging: chargeBar.s.draggingStart }
    ThresholdMarker { percent: chargeBar.s.effEnd(); dragging: chargeBar.s.draggingStop }
    MouseArea {
      id: barMouse
      anchors.fill: parent
      hoverEnabled: true
      readonly property real grab: Theme.layout.module.pad
      function tickNear(x) {
        var sx = barTrack.width * chargeBar.s.effStart() / 100, ex = barTrack.width * chargeBar.s.effEnd() / 100
        return Math.abs(x - ex) <= grab ? "end" : Math.abs(x - sx) <= grab ? "start" : ""
      }
      cursorShape: tickNear(mouseX) !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
      onPressed: m => {
        var s = chargeBar.s
        if (s.dellBusy) return
        var t = tickNear(m.x)
        if (t === "end") { s.previewEnd = s.effEnd(); s.draggingStop = true }
        else if (t === "start") { s.previewStart = s.effStart(); s.draggingStart = true }
      }
      onPositionChanged: m => {
        var s = chargeBar.s
        if (!s.draggingStart && !s.draggingStop) return
        var pct = Math.max(0, Math.min(100, m.x / barTrack.width * 100))
        var snapped = Math.round(pct / s.chargeLimitStep) * s.chargeLimitStep
        if (s.draggingStop) s.previewEnd = Model.dellClampEnd(snapped, s.effStart())
        else s.previewStart = Model.dellClampStart(Math.min(snapped, s.effEnd() - Model.DELL_GAP))
      }
      // the preview stays until the helper answers
      onReleased: {
        var s = chargeBar.s
        if (s.draggingStop) { s.draggingStop = false; if (s.previewEnd !== s.dellStatus.end) s.applyDellEnd(s.previewEnd); else s.previewEnd = -1 }
        if (s.draggingStart) { s.draggingStart = false; if (s.previewStart !== s.dellStatus.start) s.applyDellStart(s.previewStart); else s.previewStart = -1 }
      }
    }
  }
  // start/stop marker: follows the pointer while dragged, glides otherwise
  component ThresholdMarker: Rectangle {
    id: marker
    property int percent: 0
    property bool dragging: false
    width: Theme.layout.module.tileInset; height: Theme.layout.icon.large - Theme.layout.separator * 2; radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    color: Theme.r.accent.base
    x: parent.width * percent / 100 - width / 2
    opacity: pp.svc.thresholdsLive ? 1 : Theme.core.alpha.disabled
    scale: dragging ? Theme.scale("lift") : 1
    Behavior on x { enabled: !marker.dragging; NumberAnimation { duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    Behavior on scale { NumberAnimation { duration: Theme.dur("instant"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
  }

  // The chosen metric over the window as bars, like the macOS battery graph: accent on
  // battery, green while plugged in, danger at 20 % and below on the charge view; empty
  // slots stay empty. Three gridlines label the axis; pointing at a bar reads it out.
  component HistoryGraph: Item {
    id: graph
    property var svc: null
    readonly property real gutter: gutterMetrics.advanceWidth + Theme.layout.list.gap
    readonly property real plotW: Math.max(1, width - gutter)
    readonly property real plotH: Theme.layout.meter.chart * 1.5
    readonly property real from: svc.historyNow - svc.historyHours * 3600000
    readonly property var metric: svc.historyMetric
    readonly property var axis: Model.historyAxis(svc.historyBars, metric.key)
    readonly property real axisSpan: Math.max(1e-9, axis.max - axis.min)
    readonly property bool multiDay: svc.historyHours > 24
    function barValue(b) { return b ? b[metric.field] : null }
    function valueOf(b) { var v = barValue(b); return v === null || v === undefined || !isFinite(v) ? 0 : Math.max(0, Math.min(1, (v - axis.min) / axisSpan)) }
    function stamp(t) { return multiDay ? Qt.formatDateTime(new Date(t), "ddd HH:mm") : svc.clockText(t) }
    readonly property int barCount: Math.max(1, svc.historyBars.length)
    readonly property real slotW: plotW / barCount
    readonly property real barGap: Math.max(1, Math.round(slotW * 0.3))   // a third of a slot between bars
    property bool grown: false
    Component.onCompleted: Qt.callLater(function () { graph.grown = true })
    property int hoverIndex: -1
    readonly property var hoverBar: hoverIndex >= 0 ? svc.historyBars[hoverIndex] || null : null
    readonly property string readout: {
      var b = hoverBar
      if (b) return stamp(b.t0) + " · " + svc.historyValue(barValue(b), metric)
      var st = svc.historyStats
      if (!st || !st.samples) return ""
      if (metric.key === "percent") return "Now " + Math.round(svc.batteryFraction * 100) + " %"
      return "Now " + svc.historyValue(metric.key === "watts" ? st.lastW : metric.key === "volts" ? st.lastV : st.lastA, metric)
    }
    implicitHeight: plotH + timeRow.height + Theme.layout.module.pad + legend.height
    height: implicitHeight
    TextMetrics { id: gutterMetrics; font.family: Theme.font; font.pixelSize: Theme.m.type.small; text: "888 W" }
    function xOf(t) { return (t - from) / (svc.historyHours * 3600000) * plotW }
    function yOf(pct) { return plotH - Math.max(0, Math.min(100, pct)) / 100 * plotH }
    readonly property var ticks: Model.historyTicks(graph.from, svc.historyNow, graph.multiDay ? 7 : 6).ticks
    function tickText(t) { var d = new Date(t); return multiDay && d.getHours() === 0 && d.getMinutes() === 0 ? Qt.formatDate(d, "ddd") : svc.clockText(t) }

    Repeater {
      model: [100, 50, 0]
      Item {
        required property var modelData
        y: Math.round(graph.yOf(modelData)); width: graph.width
        Rectangle { width: graph.plotW; height: Theme.layout.separator; color: Theme.r.line.base }
        VCrossfadeText { x: graph.plotW + Theme.layout.list.gap / 2; anchors.verticalCenter: parent.top
          text: graph.svc.historyAxisLabel(graph.axis.min + graph.axisSpan * modelData / 100, graph.metric)
          tone: "secondary"; color: Theme.r.popover.inkSecondary; pixelSize: Theme.m.type.small }
      }
    }
    // full-height bars scaled from the baseline: changes animate as a transform
    Repeater {
      model: graph.svc.historyBars.length
      Rectangle {
        id: bar
        required property int index
        readonly property var bucket: graph.svc.historyBars[index] || null
        readonly property bool low: !!bucket && graph.metric.key === "percent" && bucket.pct <= 20
        x: Math.round(index * graph.slotW + graph.barGap / 2)
        width: Math.max(1, Math.round(graph.slotW - graph.barGap)); height: graph.plotH
        radius: Math.min(width / 2, Theme.layout.separator * 2)
        color: !bucket ? "transparent" : low ? Theme.r.danger : bucket.battery ? Theme.r.accent.base : Theme.r.success.base
        gradient: !bucket || low ? null : bucket.battery ? accentFill : chargeFill
        Gradient { id: accentFill; GradientStop { position: 0; color: Theme.r.accent.top } GradientStop { position: 1; color: Theme.r.accent.base } }
        Gradient { id: chargeFill; GradientStop { position: 0; color: Theme.r.success.top } GradientStop { position: 1; color: Theme.r.success.base } }
        opacity: !bucket ? 0 : graph.hoverIndex < 0 || graph.hoverIndex === index ? 1 : Theme.core.alpha.disabled
        transform: Scale {
          origin.y: graph.plotH
          yScale: bar.bucket && graph.grown ? Math.max(0.02, graph.valueOf(bar.bucket)) : 0
          Behavior on yScale { NumberAnimation { duration: Theme.move(Theme.dur("slow")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
        }
        Behavior on opacity { NumberAnimation { duration: graph.hoverIndex >= 0 ? Theme.dur("instant") : Theme.dur("fast") } }
      }
    }
    MouseArea {
      width: graph.plotW; height: graph.plotH
      hoverEnabled: true; acceptedButtons: Qt.NoButton
      onExited: graph.hoverIndex = -1
      onPositionChanged: m => { var i = Math.max(0, Math.min(graph.barCount - 1, Math.floor(m.x / graph.slotW))); graph.hoverIndex = graph.svc.historyBars[i] ? i : -1 }
    }
    Item {
      id: timeRow
      y: graph.plotH + Theme.layout.module.tileInset; width: graph.plotW; height: tickMetrics.height
      TextMetrics { id: tickMetrics; font.family: Theme.font; font.pixelSize: Theme.m.type.small; text: "00:00" }
      Repeater {
        model: graph.ticks
        VText { required property var modelData
          x: Math.max(0, Math.min(graph.plotW - width, graph.xOf(modelData) - width / 2))
          text: graph.tickText(modelData); tone: "secondary"; font.pixelSize: Theme.m.type.small }
      }
    }
    Row {
      id: legend
      y: timeRow.y + timeRow.height + Theme.layout.list.gap
      spacing: Theme.layout.module.pad
      Repeater {
        model: [{ ink: Theme.r.accent.base, text: "On Battery" }, { ink: Theme.r.success.base, text: "Plugged In" }]
        Row {
          required property var modelData
          spacing: Theme.layout.list.gap / 2
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.layout.list.gap; height: width; radius: width / 2; color: modelData.ink }
          VText { text: modelData.text; tone: "secondary"; font.pixelSize: Theme.m.type.small }
        }
      }
    }
  }

  // macOS pop-up button: the value and a chevron on a soft fill
  component PopUpButton: Rectangle {
    id: pop
    property string text: ""
    property bool open: false
    signal clicked()
    implicitWidth: widest.advanceWidth + Theme.layout.icon.small + Theme.layout.module.tileInset + 2 * Theme.layout.menu.itemPadX
    implicitHeight: Theme.m.control.height - Theme.layout.module.tileInset
    width: implicitWidth; height: implicitHeight
    radius: Theme.m.radius.control
    color: popMouse.pressed || pop.open || popMouse.containsMouse ? Theme.r.popover.fillHover : Theme.r.popover.tile
    border.width: Theme.layout.separator; border.color: Theme.r.line.base
    TextMetrics { id: widest; font.family: Theme.font; font.pixelSize: Theme.m.type.small; font.weight: Font.DemiBold; text: "30 min" }
    Row {
      anchors.centerIn: parent; spacing: Theme.layout.module.tileInset
      VText { anchors.verticalCenter: parent.verticalCenter; text: pop.text; color: Theme.r.popover.ink; font.pixelSize: Theme.m.type.small; font.weight: Font.DemiBold }
      VIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron.down"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary
        rotation: pop.open ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } } }
    }
    MouseArea { id: popMouse; anchors.fill: parent; hoverEnabled: true; onClicked: pop.clicked() }
  }
}
