import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Capsem bar widget and popup panel. All state comes from Service.qml, which
// is the only thing that polls; this file just displays it.
Panel {
  id: root
  moduleName: "io.github.cbyrd01.capsem"
  ipcTarget: "io.github.cbyrd01.capsem"
  manageIpc: false

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  readonly property string tool: Qt.resolvedUrl("bin/capsem-omarchy").toString().replace("file://", "")

  // Third-party widgets may look up their own service, and only their own.
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null

  readonly property bool ready: service ? service.ready : false
  readonly property string version: service ? service.version : ""
  readonly property int runningCount: service ? service.runningCount : 0
  readonly property int pendingAsksCount: service ? service.pendingAsksCount : 0
  readonly property int deniedRequests: service ? service.deniedRequests : 0
  readonly property var pendingAsks: service ? service.pendingAsks : []
  readonly property var vms: service ? service.vms : []

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property bool busy: actionProc.running

  readonly property string iconIdle: "󰒃"
  readonly property string iconActive: "󰒘"
  readonly property string iconStopped: "󰒄"
  readonly property string iconApp: "󰀻"
  readonly property string iconTui: ""
  readonly property string iconShell: "󰆍"
  readonly property string iconDoctor: "󰓙"
  readonly property string iconCheck: "󰄬"
  readonly property string iconDeny: "󰅖"
  readonly property string iconStop: "󰓛"
  readonly property string iconPlay: "󰐊"
  readonly property string iconTrash: "󰩺"

  readonly property string iconBar: !ready ? iconStopped
    : ((runningCount > 0 || pendingAsksCount > 0) ? iconActive : iconIdle)

  readonly property int quickActionCount: 4

  function refresh() {
    if (service) service.refresh()
  }

  // Fill %1..%9 in one pass. Names and summaries come from inside the
  // sandbox and may themselves contain "%1"; chained .arg() would expand
  // a marker smuggled in by an earlier value.
  function fill(template, values) {
    return String(template).replace(/%([1-9])/g, function(match, n) {
      var v = values[Number(n) - 1]
      return v === undefined ? match : String(v)
    })
  }

  function vmStatusLabel(status) {
    return String(status).toUpperCase()
  }

  function runAction(argsList, closeAfter) {
    if (busy) return
    actionProc.command = [root.tool, "action"].concat(argsList)
    actionProc.running = true
    if (closeAfter) root.close()
  }

  function moveCursor(dx, dy) {
    var step = (dx !== 0) ? dx : dy
    cursorIndex = (cursorIndex + step + quickActionCount) % quickActionCount
  }

  function activateQuickAction(i) {
    if (i === 0) runAction(["open-ui"], true)
    else if (i === 1) runAction(["open-tui"], true)
    else if (i === 2) runAction(["new-shell"], true)
    else if (i === 3) runAction(["doctor"], true)
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconBar
    active: root.pendingAsksCount > 0
    dimmed: !root.ready
    tooltipText: !root.ready
      ? strings.t("tooltip.stopped")
      : (root.pendingAsksCount > 0
          ? strings.tn("tooltip.pending", root.pendingAsksCount).arg(Commons.I18n.formatNumber(root.pendingAsksCount))
          : (root.runningCount > 0
              ? strings.tn("tooltip.active", root.runningCount).arg(Commons.I18n.formatNumber(root.runningCount)).arg(Commons.I18n.formatNumber(root.deniedRequests))
              : strings.t("tooltip.idle")))
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateQuickAction(root.cursorIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.iconBar
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: strings.t("title")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: !root.ready
                ? strings.t("status.stopped")
                : strings.t("status.running").arg(root.version).arg(Commons.I18n.formatNumber(root.runningCount)).arg(Commons.I18n.formatNumber(root.deniedRequests))
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ---------- Service stopped state ----------
        Column {
          visible: !root.ready
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("service.stopped")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            width: parent.width
            iconText: root.iconPlay
            iconSize: Style.font.title
            text: strings.t("service.start")
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            bordered: true
            onClicked: root.runAction(["start-service"], false)
          }
        }

        // ---------- Pending Ask Approvals ----------
        Column {
          visible: root.ready && root.pendingAsks.length > 0
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: strings.t("asks.header").arg(Commons.I18n.formatNumber(root.pendingAsks.length))
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.pendingAsks
            Column {
              required property var modelData
              width: column.width
              spacing: Style.space(6)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.fill(strings.t("asks.item"), [modelData.vmLabel, modelData.ruleName, modelData.summary])
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Row {
                width: parent.width
                spacing: Style.space(6)
                readonly property real cellWidth: (width - spacing) / 2

                Button {
                  width: parent.cellWidth
                  iconText: root.iconCheck
                  iconSize: Style.font.bodySmall
                  text: strings.t("asks.approve")
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  active: true
                  onClicked: root.runAction(["ask-approve", modelData.vmId, modelData.askId, modelData.generation], false)
                }

                Button {
                  width: parent.cellWidth
                  iconText: root.iconDeny
                  iconSize: Style.font.bodySmall
                  text: strings.t("asks.deny")
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  onClicked: root.runAction(["ask-deny", modelData.vmId, modelData.askId, modelData.generation], false)
                }
              }
            }
          }
        }

        // ---------- Sandboxes List ----------
        Column {
          visible: root.ready
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: root.vms.length > 0 ? strings.t("vms.headerCount").arg(Commons.I18n.formatNumber(root.vms.length)) : strings.t("vms.header")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            visible: root.vms.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("vms.empty")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.vms
            Column {
              required property var modelData
              width: column.width
              spacing: Style.space(4)

              Item {
                width: parent.width
                implicitHeight: vmLabelText.implicitHeight

                Text {
                  id: vmLabelText
                  textFormat: Text.PlainText
                  text: root.fill(strings.t("vms.item"), [modelData.label, root.vmStatusLabel(modelData.status)])
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.left: parent.left
                }

                Text {
                  visible: modelData.status === "running"
                  textFormat: Text.PlainText
                  text: strings.t("vms.traffic").arg(Commons.I18n.formatNumber(modelData.allowed)).arg(Commons.I18n.formatNumber(modelData.denied))
                  color: Qt.darker(root.bar.foreground, 1.35)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)
                readonly property real cellWidth: (width - spacing * 2) / 3

                Button {
                  width: parent.cellWidth
                  iconText: root.iconApp
                  iconSize: Style.font.bodySmall
                  text: strings.t("vms.inspect")
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  bordered: true
                  enabled: modelData.status === "running"
                  onClicked: root.runAction(["open-ui", modelData.id], true)
                }

                Button {
                  width: parent.cellWidth
                  iconText: modelData.status === "running" ? root.iconStop : root.iconPlay
                  iconSize: Style.font.bodySmall
                  text: modelData.status === "running" ? strings.t("vms.stop") : (modelData.status === "suspended" ? strings.t("vms.resume") : strings.t("vms.start"))
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  bordered: true
                  onClicked: {
                    if (modelData.status === "running") root.runAction(["vm-stop", modelData.id], false)
                    else if (modelData.status === "suspended") root.runAction(["vm-resume", modelData.id], false)
                    else root.runAction(["vm-start", modelData.id], false)
                  }
                }

                Button {
                  width: parent.cellWidth
                  iconText: root.iconTrash
                  iconSize: Style.font.bodySmall
                  text: strings.t("vms.delete")
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  bordered: true
                  onClicked: root.runAction(["vm-delete", modelData.id], false)
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Quick Actions ----------
        PanelSectionHeader {
          text: strings.t("actions.header")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Grid {
          id: actionGrid
          width: parent.width
          columns: 2
          columnSpacing: Style.space(6)
          rowSpacing: Style.space(6)
          readonly property real cellWidth: (width - columnSpacing) / 2

          Button {
            width: actionGrid.cellWidth
            iconText: root.iconApp
            iconSize: Style.font.title
            text: strings.t("actions.app")
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            hasCursor: root.cursorActive && root.cursorIndex === 0
            onClicked: root.activateQuickAction(0)
            onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = 0 } }
          }

          Button {
            width: actionGrid.cellWidth
            iconText: root.iconTui
            iconSize: Style.font.title
            text: strings.t("actions.tui")
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            hasCursor: root.cursorActive && root.cursorIndex === 1
            onClicked: root.activateQuickAction(1)
            onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = 1 } }
          }

          Button {
            width: actionGrid.cellWidth
            iconText: root.iconShell
            iconSize: Style.font.title
            text: strings.t("actions.shell")
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            hasCursor: root.cursorActive && root.cursorIndex === 2
            onClicked: root.activateQuickAction(2)
            onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = 2 } }
          }

          Button {
            width: actionGrid.cellWidth
            iconText: root.iconDoctor
            iconSize: Style.font.title
            text: strings.t("actions.doctor")
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            hasCursor: root.cursorActive && root.cursorIndex === 3
            onClicked: root.activateQuickAction(3)
            onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = 3 } }
          }
        }
      }
    }
  }
}
