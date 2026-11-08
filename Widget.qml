import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Fan control for laptops driven by NBFC-Linux. A bar icon that turns urgent
// when the machine runs hot, and a panel with every fan's temperature and
// speed, presets (auto, 50 %, 75 %, turbo), and a manual speed slider.
//
// Everything goes through the unprivileged `nbfc` client, which talks to the
// nbfc_service socket; the plugin never asks for root. Toggle the panel from
// anywhere with: omarchy-shell io.github.rob-d3v.omafan toggle
Panel {
  id: root
  moduleName: "io.github.rob-d3v.omafan"
  ipcTarget: "io.github.rob-d3v.omafan"

  property var status: ({ config: "", readOnly: false, fans: [] })
  property string error: ""
  property bool loaded: false
  property int cursorIndex: -1
  // Which fan the presets and slider act on: -1 for all of them, or one
  // fan's index, so the CPU and GPU fans can run at different speeds.
  property int fanTarget: -1
  // The speed being dragged or typed, shown until nbfc reports it back.
  property real pendingSpeed: NaN

  readonly property bool showTemperature: setting("showTemperature", false) === true
  readonly property var fans: status.fans || []
  readonly property var mode: Model.mode(Model.targetFans(fans, fanTarget))
  readonly property real hottest: Model.hottest(fans)
  readonly property string heat: Model.heat(hottest)
  readonly property bool working: fans.length > 0 && error === ""
  readonly property color heatColor: heat === "hot" ? Commons.Color.urgent
    : heat === "warm" ? Commons.Color.accent
    : (bar ? bar.foreground : Commons.Color.foreground)
  readonly property real sliderSpeed: isFinite(pendingSpeed) ? pendingSpeed
    : mode.kind === "manual" ? mode.speed
    : Model.targetFans(fans, fanTarget).length > 0 && isFinite(Model.targetFans(fans, fanTarget)[0].target)
      ? Math.round(Model.targetFans(fans, fanTarget)[0].target) : 0
  readonly property var targetOptions: {
    var options = [{ value: "-1", label: strings.t("target.all") }]
    for (var i = 0; i < fans.length; i++) {
      var kind = Model.fanKind(fans[i].name, i)
      options.push({ value: String(i), label: kind.kind === "fan" ? strings.t("target.fan").arg(kind.number) : strings.t("target." + kind.kind) })
    }
    return options
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function degrees(value) {
    return isFinite(value) ? Commons.I18n.formatNumber(Math.round(value)) + "°" : "—"
  }

  function percentText(value) {
    return isFinite(value) ? Commons.I18n.formatNumber(Math.round(value)) + "%" : "—"
  }

  function modeText() {
    if (!root.working) return strings.t("status.offline")
    return root.modeLabel(Model.mode(root.fans))
  }

  function modeLabel(m) {
    if (m.kind === "critical") return strings.t("status.critical")
    if (m.kind === "auto") return strings.t("status.auto")
    if (m.kind === "manual") return strings.t("status.manual").arg(root.percentText(m.speed))
    return strings.t("status.mixed")
  }

  function cycleTarget() {
    root.fanTarget = root.fanTarget + 1 >= root.fans.length ? -1 : root.fanTarget + 1
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function apply(value) {
    var command = Model.setCommand(value, root.fanTarget)
    if (!command || actionProc.running) return
    root.pendingSpeed = value === "auto" ? NaN : Number(command[3])
    actionProc.command = command
    actionProc.running = true
  }

  function presetLabel(value) {
    if (value === "auto") return strings.t("preset.auto")
    if (value === "100") return strings.t("preset.turbo")
    return root.percentText(Number(value))
  }

  function presetIcon(value) {
    return value === "auto" ? "󰁪" : value === "100" ? "󱐋" : "󰈐"
  }

  function toggleTemperature() {
    root.settings = Object.assign({}, root.settings, { showTemperature: !root.showTemperature })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  onOpenedChanged: {
    if (opened) {
      cursorIndex = -1
      refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: ["nbfc", "status", "-a"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: statusErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.loaded = true
      var parsed = Model.parseStatus(statusOut.text)
      if (exitCode === 0 && parsed.fans.length > 0) {
        root.status = parsed
        root.error = ""
      } else {
        root.status = { config: parsed.config, readOnly: parsed.readOnly, fans: [] }
        root.error = String(statusErr.text || statusOut.text || "").trim().slice(0, 240)
      }
      // Drop the pending speed once nbfc reports the fans where it was sent.
      if (isFinite(root.pendingSpeed) && root.mode.kind === "manual" && root.mode.speed === Math.round(root.pendingSpeed))
        root.pendingSpeed = NaN
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      id: actionErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.pendingSpeed = NaN
        root.error = String(actionErr.text || "").trim().slice(0, 240)
      }
      root.refresh()
    }
  }

  // Fast while the panel is open; slow in the bar, enough to warn when hot.
  Timer {
    interval: root.opened ? 2000 : 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰈐"
    foreground: root.heat === "hot" ? Commons.Color.urgent : root.barForeground
    labelText: root.showTemperature && !vertical && root.working ? root.degrees(root.hottest) : ""
    slotSize: Style.bar.iconSlot * (root.showTemperature && !vertical && root.working ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleTemperature()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (!root.working) return
        if (dy !== 0) {
          root.apply(Math.max(0, Math.min(100, Math.round(root.sliderSpeed / 5) * 5 - dy * 5)))
          return
        }
        if (root.cursorIndex < 0) root.cursorIndex = Math.max(0, Model.presets.indexOf(Model.presetForMode(root.mode)))
        else root.cursorIndex = Math.max(0, Math.min(Model.presets.length - 1, root.cursorIndex + dx))
      }
      onActivateRequested: {
        if (root.working && root.cursorIndex >= 0) root.apply(Model.presets[root.cursorIndex])
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!root.working) return
        if (text === "a") root.apply("auto")
        else if (text === "t") root.apply(100)
        else if (text === "f") root.cycleTarget()
        else if (isFinite(Model.speedForDigit(text))) root.apply(Model.speedForDigit(text))
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: fan · title/mode · hottest temperature ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroTemp.implicitHeight)

          PlainText {
            id: heroIcon
            text: "󰈐"
            color: root.heatColor
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroTemp.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PlainText {
              text: strings.t("title")
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            PlainText {
              text: root.modeText().toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          PlainText {
            id: heroTemp
            text: root.working ? root.degrees(root.hottest) : ""
            color: root.heatColor
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Service problem ----------
        Column {
          visible: root.loaded && !root.working
          width: parent.width
          spacing: Style.space(6)

          PlainText {
            width: parent.width
            wrapMode: Text.Wrap
            text: strings.t("error.body")
            font.pixelSize: Style.font.bodySmall
          }
          PlainText {
            width: parent.width
            wrapMode: Text.Wrap
            text: "sudo systemctl enable --now nbfc_service"
            font.family: "monospace"
            font.pixelSize: Style.font.bodySmall
          }
          PlainText {
            visible: root.error !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.error
            opacity: 0.6
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- One row per fan ----------
        Repeater {
          model: root.fans

          Column {
            required property var modelData
            width: column.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: fanName.implicitHeight

              PlainText {
                id: fanName
                anchors.left: parent.left
                anchors.right: fanReading.left
                anchors.rightMargin: Style.space(8)
                text: modelData.name
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
              PlainText {
                id: fanReading
                anchors.right: parent.right
                text: strings.t("fan.reading")
                  .arg(root.modeLabel(Model.mode([modelData])))
                  .arg(root.degrees(modelData.temperature))
                  .arg(root.percentText(modelData.current))
                  .arg(root.percentText(modelData.target))
                opacity: 0.7
                font.pixelSize: Style.font.bodySmall
              }
            }

            Item {
              width: parent.width
              implicitHeight: Style.space(8)

              Rectangle {
                id: track
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
              }
              Rectangle {
                anchors.left: track.left
                anchors.verticalCenter: track.verticalCenter
                height: track.height
                radius: track.radius
                color: Model.heat(modelData.temperature) === "hot" ? Commons.Color.urgent : root.bar.foreground
                width: Math.max(track.height, track.width * (isFinite(modelData.current) ? modelData.current : 0) / 100)
                Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
              }
            }
          }
        }

        // ---------- Presets and manual speed ----------
        PanelSeparator {
          visible: root.working
          foreground: root.bar.foreground
        }

        Column {
          visible: root.working
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            visible: root.fans.length > 1
            text: strings.t("section.target")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          ButtonGroup {
            id: targetGroup
            visible: root.fans.length > 1
            width: parent.width
            spacing: Style.space(6)
            focusable: false
            options: root.targetOptions
            value: String(root.fanTarget)
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onChanged: function(value) { root.fanTarget = Number(value) }
          }

          PanelSectionHeader {
            text: strings.t("section.mode")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: presetRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * (Model.presets.length - 1)) / Model.presets.length

            Repeater {
              model: Model.presets
              Button {
                required property var modelData
                required property int index
                width: presetRow.cellWidth
                iconText: root.presetIcon(modelData)
                iconSize: Style.font.title
                text: root.presetLabel(modelData)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: Model.presetForMode(root.mode) === modelData
                hasCursor: root.cursorIndex === index
                onClicked: root.apply(modelData)
                onHovered: function(h) { if (h) root.cursorIndex = index }
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: speedLabel.implicitHeight

            PanelSectionHeader {
              id: speedLabel
              anchors.left: parent.left
              text: strings.t("section.manual")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }
            PlainText {
              anchors.right: parent.right
              anchors.verticalCenter: speedLabel.verticalCenter
              text: root.percentText(slider.dragging ? slider.liveValue : root.sliderSpeed)
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          PanelSlider {
            id: slider
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: 100
            step: 5
            integer: true
            tickCount: 5
            value: root.sliderSpeed
            onReleased: function(value) { root.apply(value) }
          }

          PlainText {
            width: parent.width
            wrapMode: Text.Wrap
            text: strings.t("hint")
            opacity: 0.5
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // Every string here is plain text: fan names and nbfc errors come from
  // another process and must never be read as rich text.
  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.bar ? root.bar.foreground : Commons.Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
  }
}
