import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid reads out a month: today is outlined, chevrons, the scroll
// wheel and the arrow keys step which month is on screen. Days carrying
// events from the synced iCloud calendars show a dot apiece, and clicking
// one grows that day's list out of the bottom of the grid.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  // Calendar day and month names in German, to match the bar label.
  readonly property var labelLocale: Qt.locale("de_DE")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)
  readonly property var gridRange: Model.gridRange(weeks)

  // ---- The day being asked about, as the grid's own cell object, or null.
  //      Nothing is selected until a day is clicked, so a calendar nobody is
  //      questioning stays the quiet read-out it has always been.
  property var selectedDay: null
  readonly property string selectedKey: selectedDay ? String(selectedDay.key) : ""
  readonly property var selectedEvents: selectedDay ? events.eventsOn(selectedDay.key) : []
  readonly property string selectedDayLabel: selectedDay
    ? labelLocale.toString(new Date(selectedDay.year, selectedDay.month, selectedDay.day), "dddd, d. MMMM")
    : ""


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  // henri-ui: secondary text by alpha, not Qt.darker (which darkens dark text
  // further in light themes such as cupertino instead of receding it).
  readonly property color secondaryText: Util.alpha(contentForeground, Motion.secondaryTextAlpha)

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Next time it opens it should be the month grid again, not whichever
    // Tuesday was left expanded underneath it.
    root.clearSelection()
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
    // The timer syncs every 15 minutes, so what is on disk when the panel
    // opens is what the panel should be showing.
    events.refresh()
  }

  function goToToday() {
    root.clearSelection()
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.clearSelection()
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  // Clicking the open day closes it again, so the same target both asks and
  // stops asking.
  function selectDay(day) {
    if (!day) root.selectedDay = null
    else if (root.selectedKey === String(day.key)) root.selectedDay = null
    else root.selectedDay = day
  }

  function clearSelection() {
    root.selectedDay = null
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  EventService {
    id: events
    rangeFrom: root.gridRange.from
    rangeTo: root.gridRange.to
  }

  HUi.PopupPanel {
    id: panel
    kind: "popover"
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: {
        if (root.selectedDay) root.clearSelection()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
                Behavior on color { ColorAnimation { duration: heroMouse.containsMouse ? Motion.instant : Motion.fast } }
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: root.labelLocale.toString(root.today, "d. MMMM")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
                Behavior on color { ColorAnimation { duration: heroMouse.containsMouse ? Motion.instant : Motion.fast } }
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: root.secondaryText
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: root.secondaryText
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: root.secondaryText
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: height / 2
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: root.secondaryText
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: height / 2
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.space(Motion.radiusChip)
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : Util.alpha(Style.hoverFillFor(root.contentForeground, Color.accent), 0)
                  Behavior on color { ColorAnimation { duration: weekStartMouse.containsMouse ? Motion.instant : Motion.fast } }

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : root.secondaryText
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: weekStartMouse.containsMouse ? Motion.instant : Motion.fast } }
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: root.secondaryText
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: root.secondaryText
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: cell
                      required property var modelData

                      readonly property var dayEvents: events.eventsOn(cell.modelData.key)
                      readonly property bool selected: root.selectedKey === String(cell.modelData.key)

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.space(Motion.radiusRow)
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. The day you picked is the one
                      // exception, because that is what selection looks like
                      // everywhere else in the shell.
                      color: cell.selected
                        ? Color.accent
                        : Util.alpha(Style.hoverFillFor(root.contentForeground, Color.accent),
                                     dayMouse.containsMouse ? 1 : 0)
                      Behavior on color {
                        ColorAnimation {
                          duration: cell.selected || dayMouse.containsMouse ? Motion.instant : Motion.fast
                          easing.type: Easing.BezierSpline
                          easing.bezierCurve: Motion.easeOut
                        }
                      }
                      // Dropped under the accent fill rather than drawn over
                      // it: today and selected both want the eye, and two
                      // markers on one cell only muddle which is which.
                      border.width: cell.modelData.today && !cell.selected ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        // Lifted by the height of the dot row below, so a day
                        // with events and a day without still sit on the same
                        // line across the grid.
                        anchors.verticalCenterOffset: -Style.space(3)
                        text: cell.modelData.day
                        color: cell.selected
                          ? Motion.onColor(Color.accent)
                          : (cell.modelData.inMonth
                              ? (cell.modelData.weekend ? root.secondaryText : root.contentForeground)
                              : Util.alpha(root.contentForeground, Motion.disabledOpacity))
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: cell.modelData.today
                      }

                      // One dot per event, three at most. Past that the count
                      // stops being readable at this size and the grid only
                      // gets noisier; the day's own list has the rest.
                      Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(6)
                        spacing: Style.space(3)

                        Repeater {
                          model: Math.min(cell.dayEvents.length, 3)

                          Rectangle {
                            id: dot
                            required property int index

                            readonly property string calendarColor: String(cell.dayEvents[dot.index].color || "")
                            // The dots arrive with the helper's answer rather
                            // than with the frame, so they fade up instead of
                            // popping into a grid that was already drawn.
                            property bool shown: false

                            width: Style.space(4)
                            height: width
                            radius: width / 2
                            // On an accent-filled cell the calendar's own
                            // color would be whatever survives against blue.
                            // The selected day borrows the fill's text color
                            // instead, which is the one thing guaranteed to
                            // read on it.
                            color: cell.selected
                              ? Motion.onColor(Color.accent)
                              : (dot.calendarColor !== "" ? dot.calendarColor : Color.accent)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            opacity: dot.shown ? (cell.modelData.inMonth ? 1 : Motion.disabledOpacity) : 0
                            scale: dot.shown ? 1 : Motion.iconFromScale
                            Component.onCompleted: Qt.callLater(function() { dot.shown = true })
                            Behavior on opacity {
                              NumberAnimation {
                                duration: Motion.fast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.easeOut
                              }
                            }
                            Behavior on scale {
                              NumberAnimation {
                                duration: Motion.fast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.easeOut
                              }
                            }
                          }
                        }
                      }

                      MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Every day answers, not just the ones with dots:
                        // "is anything on the 23rd?" is the same question
                        // whether or not the answer turns out to be no.
                        onClicked: root.selectDay(cell.modelData)
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- The day you clicked, growing out of the bottom of the grid
          //      it came from. Collapsed to nothing the rest of the time, so
          //      the popup is the same panel it always was until something is
          //      actually asked of it.
          HUi.Collapse {
            width: parent.width
            expanded: root.selectedDay !== null

            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              // The grid's own width, so the list lines up under the days
              // rather than under the popup.
              width: gridColumn.width
              spacing: Style.space(2)

              Item { width: parent.width; height: Style.space(14) }

              Rectangle {
                width: parent.width
                height: Style.spacing.hairline
                color: root.contentForeground
                opacity: Motion.hairlineAlpha
              }

              Item { width: parent.width; height: Style.space(6) }

              // The day spelled out. The cell it came from is two digits,
              // which is not enough to confirm you hit the one you meant.
              HUi.CrossfadeText {
                width: parent.width
                height: implicitHeight
                text: root.selectedDayLabel
                color: root.secondaryText
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                fontWeight: Font.Bold
                elide: Text.ElideRight
              }

              Item { width: parent.width; height: Style.space(4) }

              Repeater {
                model: root.selectedEvents

                Item {
                  id: eventRow
                  required property var modelData
                  required property int index

                  width: parent.width
                  height: Style.space(Motion.controlHeight)

                  HUi.StaggerIn {
                    anchors.fill: parent
                    active: true
                    index: eventRow.index

                    // The calendar's own color, the way it is on the phone —
                    // a stripe rather than a dot, because at this size a dot
                    // beside text reads as a bullet point.
                    Rectangle {
                      id: stripe
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(3)
                      height: Style.space(16)
                      radius: width / 2
                      color: String(eventRow.modelData.color || "") !== ""
                        ? eventRow.modelData.color
                        : Color.accent
                    }

                    Text {
                      id: timeText
                      textFormat: Text.PlainText
                      anchors.left: stripe.right
                      anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      // Fixed, so the titles line up into a column instead of
                      // stepping in and out behind times of different widths.
                      width: Style.space(58)
                      text: eventRow.modelData.allDay ? "ganztägig" : String(eventRow.modelData.start)
                      color: root.secondaryText
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      id: placeText
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      // Never more than a third of the row: the title is what
                      // the list is for, and a long address must not squeeze
                      // it down to an ellipsis.
                      width: Math.min(implicitWidth, Math.round(parent.width / 3))
                      horizontalAlignment: Text.AlignRight
                      elide: Text.ElideRight
                      text: String(eventRow.modelData.location || "")
                      color: root.secondaryText
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: timeText.right
                      anchors.leftMargin: Style.space(8)
                      anchors.right: placeText.text !== "" ? placeText.left : parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      elide: Text.ElideRight
                      text: String(eventRow.modelData.summary)
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }

              // An empty day still answers. A blank gap under the grid would
              // read as a panel that broke rather than as a free afternoon.
              Item {
                width: parent.width
                height: root.selectedEvents.length === 0 ? Style.space(Motion.controlHeight) : 0
                visible: height > 0

                HUi.CrossfadeText {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(13)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  height: implicitHeight
                  // Told apart deliberately: a day with nothing on it and a
                  // machine with no calendar on it look identical otherwise,
                  // and only one of them is worth doing something about.
                  text: events.everLoaded && !events.synced
                    ? "Kein Kalender synchronisiert"
                    : "Keine Termine"
                  color: root.secondaryText
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.body
                  elide: Text.ElideRight
                }
              }

              Item { width: parent.width; height: Style.space(6) }
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              HUi.CrossfadeText {
                id: monthLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: root.labelLocale.toString(root.viewDate, "MMMM yyyy").toUpperCase()
                color: root.secondaryText
                fontFamily: root.contentFontFamily
                fontSize: Style.font.body
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }
        }
      }
    }
  }
}
