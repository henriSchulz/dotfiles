import QtQuick
import QtQuick.Effects
import "Velum"

// Draws the pieces of the LUKS screen (Plymouth theme velum) with the Velum tokens and the look of
// system/sddm-velum/Face.qml: Plymouth has no QML and no SF font in the initramfs, so the blurred
// wallpaper, the field, the labels and every glyph of the clock and date become PNGs here.
// Run by ./assemble, inside a compositor, as
//   qml Generate.qml -- <outdir> <width> <height> <scale> <background> <variant> <dark> <reduceTransparency> <touch>
// Width and height are device pixels, as the images and the layout come out (a grab already renders at
// the output's scale, which assemble sets to <scale>). The last line of its log is the layout
// (JSON) that ./assemble puts in front of velum.script.in.
// Keep it in step with Face.qml: a change to the lock screen's look belongs here too.
Window {
  id: win
  readonly property var args: { var a = Qt.application.arguments; return a.slice(a.indexOf("--") + 1) }
  readonly property string out: args[0]
  readonly property real scaleOut: Number(args[3])
  // the screen in logical pixels; the window itself is whatever the compositor gives it
  readonly property real screenWidth: Number(args[1]) / scaleOut
  readonly property real screenHeight: Number(args[2]) / scaleOut
  visible: true
  color: "black"

  readonly property real fieldWidth: Math.round(Theme.layout.module.width * 0.62)
  readonly property real fieldHeight: Theme.m.control.height + Theme.layout.module.pad
  readonly property real fieldTop: (screenHeight - fieldHeight) / 2 + Math.round(screenHeight * 0.08)
  readonly property real fieldLeft: (screenWidth - fieldWidth) / 2
  readonly property color photoInk: Theme.r.ink.onAccent
  readonly property real margin: Theme.layout.module.width / 8   // room for the shadows in every image
  readonly property int dotFont: Math.round(Theme.m.type.title * 1.1)
  readonly property int dotSpacing: Math.round(Theme.m.type.title * 0.16)
  readonly property real dateSize: Theme.m.type.title * 1.4
  readonly property real clockSize: Theme.m.type.title * 6.5
  readonly property real spinnerSize: Theme.layout.checkbox.size

  readonly property var weekdays: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
  readonly property var months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

  Component.onCompleted: {
    Theme.variant = args[5]
    Theme.dark = args[6] === "true"
    Theme.reduceTransparency = args[7] === "true"
    Theme.touch = args[8] === "true"
    start.start()
  }

  // ---- what gets drawn next (the same stage for every image)
  Item {
    id: stage
    width: win.screenWidth
    height: win.screenHeight
    property string kind: "wall"

    // the blurred wallpaper
    Item {
      id: wallLayer
      anchors.fill: parent
      visible: stage.kind === "wall"
      Rectangle { anchors.fill: parent; color: Theme.r.bg.window }
      Image {
        id: wallpaper
        anchors.fill: parent
        source: "file://" + win.args[4]
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: width
        sourceSize.height: height
      }
      MultiEffect {
        anchors.fill: wallpaper
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: wallpaper.status === Image.Ready
        blur: 1.0
        blurMax: 128
        blurMultiplier: 1.25
        contrast: -0.08
      }
    }

    // the field on the popover material with its shadow; its border turns red on a failed attempt
    Item {
      id: fieldLayer
      visible: stage.kind === "field"
      width: win.fieldWidth + 2 * win.margin
      height: win.fieldHeight + 2 * win.margin
      property bool error: false
      Item {
        x: win.margin; y: win.margin
        width: win.fieldWidth; height: win.fieldHeight
        VShadow { layers: Theme.r.popover.shadow; radius: pill.radius }
        Rectangle {
          id: pill
          anchors.fill: parent
          radius: height / 2
          color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
          border.width: fieldLayer.error ? Theme.core.size.focusRing : Theme.layout.separator
          border.color: fieldLayer.error ? Theme.r.danger : Theme.r.line.rim
        }
      }
    }

    // a label as big as the field
    Item {
      id: labelLayer
      visible: stage.kind === "label"
      width: win.fieldWidth
      height: win.fieldHeight
      Text {
        id: label
        textFormat: Text.PlainText
        anchors.fill: parent
        font.family: Theme.font
        font.pixelSize: Theme.m.type.body
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }

    // one password dot
    Item {
      id: dotLayer
      visible: stage.kind === "dot"
      width: dot.implicitWidth
      height: dot.implicitHeight
      Text {
        id: dot
        text: "●"
        color: Theme.r.popover.ink
        font.family: Theme.font
        font.pixelSize: win.dotFont
      }
    }

    // a frame of VSpinner, its spokes at a fixed step (VSpinner's own timer would race the grab)
    Item {
      id: spinLayer
      visible: stage.kind === "spin"
      width: win.spinnerSize
      height: win.spinnerSize
      property int step: 0
      Repeater {
        model: 8
        Rectangle {
          required property int index
          x: spinLayer.width / 2 - width / 2; y: 0
          width: Math.max(Theme.layout.separator, spinLayer.width / 9); height: spinLayer.width * 0.3; radius: width / 2   // lint-ok: VSpinner's glyph
          color: Theme.r.popover.inkSecondary
          transform: Rotation { origin.x: width / 2; origin.y: spinLayer.width / 2; angle: index * 45 }
          opacity: 0.15 + 0.85 * (((index - spinLayer.step + 8) % 8) / 7)   // lint-ok: VSpinner's spoke fade
        }
      }
    }

    // a piece of the date or the clock with the soft shade of the lock screen
    Item {
      id: glyphLayer
      visible: stage.kind === "glyph"
      width: glyph.implicitWidth + 2 * win.margin
      height: glyph.implicitHeight + 2 * win.margin
      Text {
        id: glyph
        x: win.margin; y: win.margin
        color: win.photoInk
        font.family: Theme.font
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: (Theme.r.popover.shadow || []).length > 1 ? Theme.r.popover.shadow[1].color : "transparent"
          shadowBlur: 1.0
          shadowVerticalOffset: Theme.layout.separator * 2
        }
      }
    }

    // the clock's colon: between digits SF Pro sets a raised one, so it is cut out of "0:0"
    Item {
      id: colonLayer
      visible: stage.kind === "colon"
      width: win.colonAdvance + 2 * win.margin
      height: colonText.implicitHeight + 2 * win.margin
      Item {
        x: win.margin; y: win.margin
        width: win.colonAdvance
        height: colonText.implicitHeight
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: (Theme.r.popover.shadow || []).length > 1 ? Theme.r.popover.shadow[1].color : "transparent"
          shadowBlur: 1.0
          shadowVerticalOffset: Theme.layout.separator * 2
        }
        // inside the layer: the layered item's own clip would not reach the shadow's source
        Item {
          anchors.fill: parent
          clip: true
          Text {
            id: colonText
            x: -zeroMetrics.advanceWidth
            text: "0:0"
            color: win.photoInk
            font.family: Theme.font
            font.pixelSize: win.clockSize
            font.weight: Font.Bold
          }
        }
      }
    }
  }

  // own metrics: a binding on advance() below would rerun, and reset it, whenever it measures
  TextMetrics { id: zeroMetrics; text: "0"; font.family: Theme.font; font.pixelSize: win.clockSize; font.weight: Font.Bold }
  TextMetrics { id: colonMetrics; text: "0:0"; font.family: Theme.font; font.pixelSize: win.clockSize; font.weight: Font.Bold }
  readonly property real colonAdvance: colonMetrics.advanceWidth - 2 * zeroMetrics.advanceWidth
  TextMetrics { id: measure; font.family: Theme.font }
  function advance(text, size, weight) {
    measure.font.pixelSize = size
    measure.font.weight = weight
    measure.text = text
    return measure.advanceWidth
  }
  function fontHeight(size, weight) {
    measure.font.pixelSize = size
    measure.font.weight = weight
    measure.text = "0"
    return measure.height
  }

  // ---- the job list: [file, item, setup]
  property var jobs: []
  property var layout: ({})
  function addGlyph(file, text, size, weight, record) {
    jobs.push({ file: file, item: glyphLayer, setup: function () {
      stage.kind = "glyph"; glyph.text = text; glyph.font.pixelSize = size; glyph.font.weight = weight
    } })
    record[file] = advance(text, size, weight) * scaleOut
  }
  function addLabel(file, text, color) {
    jobs.push({ file: file, item: labelLayer, setup: function () { stage.kind = "label"; label.text = text; label.color = color } })
  }
  Timer {
    id: start
    interval: 1500   // the wallpaper loads and the theme settles
    onTriggered: {
      var adv = {}
      jobs.push({ file: "bg", item: wallLayer, setup: function () { stage.kind = "wall" } })
      jobs.push({ file: "field", item: fieldLayer, setup: function () { stage.kind = "field"; fieldLayer.error = false } })
      jobs.push({ file: "field-error", item: fieldLayer, setup: function () { stage.kind = "field"; fieldLayer.error = true } })
      addLabel("label-placeholder", "Enter Password", Theme.r.popover.inkSecondary)
      addLabel("label-checking", "Checking…", Theme.r.popover.ink)
      for (var n = 1; n <= 9; n++) addLabel("label-fail-" + n, "Authentication failed (" + n + ")", Theme.r.danger)
      jobs.push({ file: "dot", item: dotLayer, setup: function () { stage.kind = "dot" } })
      for (var s = 0; s < 8; s++) (function (i) {
        jobs.push({ file: "spin-" + i, item: spinLayer, setup: function () { stage.kind = "spin"; spinLayer.step = i } })
      })(s)
      var clock = "0123456789"
      for (var c = 0; c < clock.length; c++) addGlyph("clock-" + clock[c], clock[c], clockSize, Font.Bold, adv)
      jobs.push({ file: "clock-colon", item: colonLayer, setup: function () { stage.kind = "colon" } })
      adv["clock-colon"] = colonAdvance * scaleOut
      for (var w = 0; w < 7; w++) addGlyph("weekday-" + (w + 1), weekdays[w] + ",", dateSize, Font.DemiBold, adv)
      for (var d = 1; d <= 31; d++) addGlyph("day-" + d, String(d), dateSize, Font.DemiBold, adv)
      for (var m = 0; m < 12; m++) addGlyph("month-" + (m + 1), months[m], dateSize, Font.DemiBold, adv)

      layout = {
        width: Number(args[1]),
        height: Number(args[2]),
        margin: Math.round(margin * scaleOut),
        fieldX: Math.round(fieldLeft * scaleOut),
        fieldY: Math.round(fieldTop * scaleOut),
        fieldW: Math.round(fieldWidth * scaleOut),
        fieldH: Math.round(fieldHeight * scaleOut),
        fieldPad: Math.round(Theme.layout.module.pad * scaleOut),
        dotAdvance: (advance("●", dotFont, Font.Normal) + dotSpacing) * scaleOut,
        spinnerX: Math.round((fieldLeft + Theme.layout.module.pad) * scaleOut),
        spinnerY: Math.round((fieldTop + (fieldHeight - spinnerSize) / 2) * scaleOut),
        spinnerMs: Math.round(Theme.dur("slower") * 2 / 8),
        clockTop: Math.round(Math.round(screenHeight * 0.12) * scaleOut),
        dateHeight: fontHeight(dateSize, Font.DemiBold) * scaleOut,
        // the gap between the pieces, kerning included: what a whole date measures beyond them
        dateSpace: (advance("Wednesday, 4 November", dateSize, Font.DemiBold) - advance("Wednesday,", dateSize, Font.DemiBold)
                    - advance("4", dateSize, Font.DemiBold) - advance("November", dateSize, Font.DemiBold)) / 2 * scaleOut,
        shakeAmp: Theme.reduceMotion ? 0 : Theme.core.motion.offset.shake * scaleOut,
        shakeMs: Theme.dur("shake"),
        advance: adv
      }
      next()
    }
  }
  function next() {
    if (jobs.length === 0) {
      console.warn("VELUM-LAYOUT " + JSON.stringify(layout))
      Qt.quit()
      return
    }
    var job = jobs.shift()
    job.setup()
    pause.job = job
    pause.start()
  }
  Timer {
    id: pause
    property var job
    interval: 80   // one frame for the visibility change, the layers and the text
    onTriggered: {
      var j = job
      j.item.grabToImage(function (result) {
        result.saveToFile(win.out + "/" + j.file + ".png")
        win.next()
      })
    }
  }
}
