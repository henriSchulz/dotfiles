import QtQuick
import Quickshell
import Quickshell.Io
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion

// The calendar events behind the month grid.
//
// vdirsyncer mirrors iCloud one way into a vdir at ~/.local/share/calendars,
// and `omarchy-calendar-events` turns that pile of per-event .ics files into
// the one shape this panel wants: a map from "yyyy-MM-dd" to the events on
// that day, already expanded through their recurrence rules and converted to
// local time.
//
// Nothing here blocks: the helper runs as a process and the grid draws its
// dots when the answer arrives. A month with no answer yet is simply a month
// without dots, which is also exactly what a month with no events looks like
// — there is no spinner, because the wait is well under the 300 ms that
// would earn one.
Item {
  id: service

  // The visible grid's first and last day, "yyyy-MM-dd". Set both; the
  // helper is asked for the range between them.
  property string rangeFrom: ""
  property string rangeTo: ""

  // dateKey -> [{ summary, location, allDay, start, end, calendar, color }]
  property var days: ({})
  property var calendars: []

  // False until a run comes back having found a vdir at all — the panel uses
  // it to tell "no events that day" apart from "nothing is synced yet".
  property bool synced: false
  property bool everLoaded: false
  property string error: ""

  function eventsOn(key) {
    var list = service.days[String(key)]
    return list === undefined ? [] : list
  }

  function countOn(key) {
    return eventsOn(key).length
  }

  // Force a fresh read — the panel opening, or the day rolling over. Goes
  // through the same debounce so it cannot overlap a run already queued.
  function refresh() {
    if (service.rangeFrom === "" || service.rangeTo === "") return
    debounce.restart()
  }

  onRangeFromChanged: service.refresh()
  onRangeToChanged: service.refresh()

  Timer {
    id: debounce
    // Holding an arrow key walks the months faster than the helper can
    // answer. Without this, every step would start a process whose result
    // the next step has already made irrelevant.
    interval: Motion.instant
    onTriggered: reader.reload()
  }

  Process {
    id: reader
    running: false
    command: ["omarchy-calendar-events", "--from", service.rangeFrom, "--to", service.rangeTo]
    stdout: StdioCollector { id: readerOut; waitForEnd: true }
    stderr: StdioCollector { id: readerErr; waitForEnd: true }

    // A run still going is a run for a month nobody is looking at any more.
    function reload() {
      reader.running = false
      reader.running = true
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        // Keep the days already on screen. A helper that is missing or
        // briefly unhappy should not blank a grid that was drawing fine.
        service.error = String(readerErr.text || "").trim() || ("omarchy-calendar-events exited " + exitCode)
        return
      }

      var payload
      try {
        payload = JSON.parse(String(readerOut.text))
      } catch (e) {
        service.error = "unreadable helper output: " + e
        return
      }

      service.error = ""
      service.days = payload.days || ({})
      service.calendars = payload.calendars || []
      service.synced = payload.synced === true
      service.everLoaded = true
    }
  }
}
