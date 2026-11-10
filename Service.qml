import QtQuick
import Quickshell
import Quickshell.Io

// The one place that talks to Capsem.
//
// The Capsem gateway has no change signal for approvals or blocked requests
// (its /events stream only reports VM state, and only when something asks for
// /status), so this has to poll. It does so once for the whole shell rather
// than once per bar widget: a widget is built per monitor, the service is
// not. Each tick is a single helper process making a single gateway request,
// which also raises the desktop notifications for anything new.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string tool: Qt.resolvedUrl("bin/capsem-omarchy").toString().replace("file://", "")

  // Capsem's own tray polls the same endpoint every 5 seconds. With the
  // gateway down there is nothing to miss, so back off.
  readonly property int readyIntervalMs: 5000
  readonly property int stoppedIntervalMs: 15000

  property bool ready: false
  property string serviceState: "stopped"
  property string version: ""
  property int runningCount: 0
  property int stoppedCount: 0
  property int suspendedCount: 0
  property int pendingAsksCount: 0
  property int deniedRequests: 0
  property int allowedRequests: 0
  property var pendingAsks: []
  property var vms: []

  property bool refreshAgain: false

  // Called by the widget when its panel opens and after every action, so the
  // display never waits for the next tick.
  function refresh() {
    if (pollProc.running) refreshAgain = true
    else pollProc.running = true
  }

  function applyStatus(text) {
    var d
    try {
      d = JSON.parse(text)
    } catch (e) {
      return
    }
    root.ready = d.ready === true
    root.serviceState = String(d.service || "stopped")
    root.version = String(d.version || "")
    root.runningCount = Number(d.runningCount || 0)
    root.stoppedCount = Number(d.stoppedCount || 0)
    root.suspendedCount = Number(d.suspendedCount || 0)
    root.pendingAsksCount = Number(d.pendingAsksCount || 0)
    root.deniedRequests = Number(d.deniedRequests || 0)
    root.allowedRequests = Number(d.allowedRequests || 0)
    root.pendingAsks = d.pendingAsks || []
    root.vms = d.vms || []
  }

  Process {
    id: pollProc
    command: [root.tool, "poll"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    onExited: {
      if (root.refreshAgain) {
        root.refreshAgain = false
        root.refresh()
      }
    }
  }

  Timer {
    interval: root.ready ? root.readyIntervalMs : root.stoppedIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
