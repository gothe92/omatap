import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string typedPrefix: ""
  property string clickMode: "left" // "left" | "right" | "double" | "middle" | "move" | "scroll-down" | "scroll-up"
  property bool precisionMode: false
  property bool subGridActive: false
  property real activeCellX: 0
  property real activeCellY: 0
  property real activeCellW: 80
  property real activeCellH: 60
  property var smartTargets: []
  property bool targetsRestart: false
  property var targetScreen: null
  property var gridCells: []

  readonly property string helperPath: Qt.resolvedUrl("omatap-helper.py").toString().replace(/^file:\/\//, "")
  readonly property string alphabet: "ASDFGHJKLQWERTYUIOPZXCVBNM"
  readonly property int gridCols: 13
  readonly property int gridRows: 12
  readonly property string subGridKeys: "QWEASDZXC"
  // Mode keys match the US ; ' , . [ ] by physical position (xkb keycode), so they sit in
  // the same place on any layout (É Á , . Ő Ú on Hungarian), or by the typed character
  readonly property var keycodes: ({ semicolon: 47, apostrophe: 48, comma: 59, period: 60, bracketLeft: 34, bracketRight: 35 })

  // Theme-driven palette: the [menu] section of the active theme's shell.toml
  readonly property color bgColor: Commons.Color.menu.background
  readonly property color fgColor: Commons.Color.menu.text
  readonly property color borderColor: Commons.Color.menu.border
  readonly property color matchColor: Commons.Color.menu.selectedText
  readonly property color accentColor: Commons.Color.accent
  readonly property string fontFamily: Style.font.menuFamily
  readonly property string modeLabel: {
    var parts = []
    if (root.clickMode !== "left") parts.push(root.clickMode)
    if (root.precisionMode) parts.push("precision")
    return parts.join(" · ")
  }

  function open(payloadJson) {
    root.typedPrefix = ""
    root.subGridActive = false
    root.clickMode = "left"
    root.precisionMode = false
    if (payloadJson && typeof payloadJson === "string" && payloadJson.length > 2) {
      try {
        var parsed = JSON.parse(payloadJson)
        if (parsed && parsed.mode) root.clickMode = String(parsed.mode)
        if (parsed && parsed.precision === true) root.precisionMode = true
      } catch (e) {}
    }
    root.targetScreen = focusedScreen()
    root.smartTargets = []
    root.opened = true
    rebuildGrid()
    if (targetsProcess.running) root.targetsRestart = true
    else targetsProcess.running = true
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
    })
  }

  // Draw on the output Hyprland has focused; the helper maps clicks onto the same one
  function focusedScreen() {
    var name = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function close() {
    root.opened = false
    root.typedPrefix = ""
    root.subGridActive = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "gothe92.omatap")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function rebuildGrid() {
    var w = panel.width > 100 ? panel.width : 1536
    var h = panel.height > 100 ? panel.height : 960
    var cw = w / root.gridCols
    var ch = h / root.gridRows
    var cells = []
    var idx = 0

    for (var r = 0; r < root.gridRows; r++) {
      var firstChar = root.alphabet.charAt(r % root.alphabet.length)
      for (var c = 0; c < root.gridCols; c++) {
        var secondChar = root.alphabet.charAt(c % root.alphabet.length)
        var code = firstChar + secondChar
        var cx = Math.round(c * cw + cw * 0.5)
        var cy = Math.round(r * ch + ch * 0.5)
        cells.push({
          code: code,
          first: firstChar,
          second: secondChar,
          x: cx,
          y: cy,
          cellX: Math.round(c * cw),
          cellY: Math.round(r * ch),
          cellW: Math.round(cw),
          cellH: Math.round(ch),
          index: idx++
        })
      }
    }
    root.gridCells = cells
  }

  function performActionAt(x, y, modeOverride) {
    var mode = modeOverride || root.clickMode
    root.dismiss()
    Quickshell.execDetached([
      "python3",
      root.helperPath,
      "act",
      String(Math.round(x)),
      String(Math.round(y)),
      String(mode),
      root.targetScreen ? String(root.targetScreen.name) : ""
    ])
  }

  function selectCell(cell) {
    if (!cell) return
    if (root.precisionMode) {
      root.activeCellX = cell.x
      root.activeCellY = cell.y
      root.activeCellW = cell.cellW
      root.activeCellH = cell.cellH
      root.subGridActive = true
    } else {
      performActionAt(cell.x, cell.y, root.clickMode)
    }
  }

  function handleSubGridKey(ch) {
    var pos = root.subGridKeys.indexOf(ch)
    if (pos !== -1) {
      var sr = Math.floor(pos / 3) - 1 // -1, 0, 1
      var sc = (pos % 3) - 1           // -1, 0, 1
      var targetX = root.activeCellX + sc * (root.activeCellW * 0.3)
      var targetY = root.activeCellY + sr * (root.activeCellH * 0.3)
      performActionAt(targetX, targetY, root.clickMode)
      return true
    }
    return false
  }

  function handleLetter(upperChar, shiftHeld) {
    if (root.subGridActive) {
      handleSubGridKey(upperChar)
      return
    }

    if (root.typedPrefix === "") {
      // Check if any cell starts with upperChar
      for (var i = 0; i < root.gridCells.length; i++) {
        if (root.gridCells[i].first === upperChar) {
          root.typedPrefix = upperChar
          return
        }
      }
    } else {
      var code = root.typedPrefix + upperChar
      for (var j = 0; j < root.gridCells.length; j++) {
        if (root.gridCells[j].code === code) {
          if (shiftHeld) {
            root.precisionMode = true
          }
          selectCell(root.gridCells[j])
          return
        }
      }
      root.typedPrefix = ""
    }
  }

  function handleDigit(digitChar) {
    // Window targets are hidden while a prefix or the sub-grid is active
    if (root.subGridActive || root.typedPrefix !== "") return
    for (var i = 0; i < root.smartTargets.length; i++) {
      var t = root.smartTargets[i]
      if (String(t.hint) === digitChar) {
        performActionAt(t.x, t.y, root.clickMode)
        return
      }
    }
  }

  Process {
    id: targetsProcess
    command: ["python3", root.helperPath, "targets"]
    onExited: {
      if (!root.targetsRestart) return
      root.targetsRestart = false
      running = true
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Result of a run started before the latest open; a fresh run follows
        if (root.targetsRestart) return
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && Array.isArray(parsed.smartTargets)) {
            root.smartTargets = parsed.smartTargets
          }
        } catch (e) {
          root.smartTargets = []
        }
      }
    }
  }

  IpcHandler {
    target: "gothe92.omatap"

    function open(): void { root.open("{}") }
    function close(): void { root.dismiss() }
    function show(): void { root.open("{}") }
    function hide(): void { root.dismiss() }
    function toggle(): void { root.toggle() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omatap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onWidthChanged: if (root.opened) root.rebuildGrid()
    onHeightChanged: if (root.opened) root.rebuildGrid()

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.subGridActive) {
            root.subGridActive = false
            root.typedPrefix = ""
          } else if (root.typedPrefix !== "") {
            root.typedPrefix = ""
          } else {
            root.dismiss()
          }
          event.accepted = true
          return
        }

        if (event.key === Qt.Key_Backspace) {
          root.subGridActive = false
          root.typedPrefix = ""
          event.accepted = true
          return
        }

        if (event.key === Qt.Key_Tab) {
          root.precisionMode = !root.precisionMode
          event.accepted = true
          return
        }

        // Action mode hotkeys: F1..F5, Ctrl+L/R/D/M/G or the physical punctuation keys
        if (event.key === Qt.Key_F1 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_L)) {
          root.clickMode = "left"; event.accepted = true; return
        }
        if (event.key === Qt.Key_F2 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) || (event.nativeScanCode === root.keycodes.semicolon || event.text === ";")) {
          root.clickMode = (root.clickMode === "right") ? "left" : "right"
          event.accepted = true; return
        }
        if (event.key === Qt.Key_F3 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_D) || (event.nativeScanCode === root.keycodes.apostrophe || event.text === "'")) {
          root.clickMode = (root.clickMode === "double") ? "left" : "double"
          event.accepted = true; return
        }
        if (event.key === Qt.Key_F4 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_M) || (event.nativeScanCode === root.keycodes.comma || event.text === ",")) {
          root.clickMode = (root.clickMode === "middle") ? "left" : "middle"
          event.accepted = true; return
        }
        if (event.key === Qt.Key_F5 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_G) || (event.nativeScanCode === root.keycodes.period || event.text === ".")) {
          root.clickMode = (root.clickMode === "move") ? "left" : "move"
          event.accepted = true; return
        }
        if ((event.nativeScanCode === root.keycodes.bracketLeft || event.text === "[")) {
          root.clickMode = (root.clickMode === "scroll-up") ? "left" : "scroll-up"
          event.accepted = true; return
        }
        if ((event.nativeScanCode === root.keycodes.bracketRight || event.text === "]")) {
          root.clickMode = (root.clickMode === "scroll-down") ? "left" : "scroll-down"
          event.accepted = true; return
        }

        // Precision sub-grid arrow nudging & Enter commit
        if (root.subGridActive) {
          var step = (event.modifiers & Qt.ShiftModifier) ? 2 : 8
          if (event.key === Qt.Key_Left) { root.activeCellX -= step; event.accepted = true; return }
          if (event.key === Qt.Key_Right) { root.activeCellX += step; event.accepted = true; return }
          if (event.key === Qt.Key_Up) { root.activeCellY -= step; event.accepted = true; return }
          if (event.key === Qt.Key_Down) { root.activeCellY += step; event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.performActionAt(root.activeCellX, root.activeCellY, root.clickMode)
            event.accepted = true
            return
          }
        }

        var ch = String(event.text || "")
        if (ch >= "1" && ch <= "9") {
          root.handleDigit(ch)
          event.accepted = true
          return
        }

        var upper = ch.toUpperCase()
        if (upper.length === 1 && upper >= "A" && upper <= "Z") {
          root.handleLetter(upper, (event.modifiers & Qt.ShiftModifier) !== 0)
          event.accepted = true
          return
        }
      }
    }

    // Grid cells layer
    Repeater {
      model: root.gridCells

      Item {
        id: cell
        required property var modelData

        readonly property bool filtered: root.typedPrefix !== ""
        visible: !root.subGridActive && (!filtered || modelData.first === root.typedPrefix)

        x: modelData.cellX
        y: modelData.cellY
        width: modelData.cellW
        height: modelData.cellH

        Rectangle {
          anchors.fill: parent
          visible: cell.filtered
          color: Style.normalFill
          border.width: Style.normalBorderWidth
          border.color: Style.normalBorderColor
        }

        Rectangle {
          anchors.centerIn: parent
          width: badgeRow.implicitWidth + Style.spacing.lg * 2
          height: Style.spacing.controlHeight - Style.spacing.md
          radius: Style.cornerRadius
          color: root.bgColor
          border.width: Style.normalBorderWidth
          border.color: cell.filtered ? Style.selectedBorderColor : Util.alpha(root.borderColor, Style.normalBorderAlpha)

          Row {
            id: badgeRow
            anchors.centerIn: parent

            Text {
              textFormat: Text.PlainText
              text: modelData.first
              color: cell.filtered ? Commons.Color.muted : root.fgColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: modelData.second
              color: cell.filtered ? root.matchColor : root.fgColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectCell(modelData)
          }
        }
      }
    }

    // Window targets (1..9)
    Repeater {
      model: root.smartTargets

      Rectangle {
        required property var modelData
        visible: !root.subGridActive && root.typedPrefix === ""

        x: Math.round(Number(modelData.x || 0) - width / 2)
        y: Math.round(Number(modelData.y || 0) - height / 2)
        width: height
        height: Style.spacing.controlHeight
        radius: Style.cornerRadius
        color: root.bgColor
        border.width: Math.max(1, Style.selectedBorderWidth)
        border.color: root.accentColor

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: String(modelData.hint || "")
          color: root.accentColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.performActionAt(modelData.x, modelData.y, root.clickMode)
        }
      }
    }

    // 3x3 precision sub-grid
    Item {
      visible: root.subGridActive
      x: Math.round(root.activeCellX - root.activeCellW / 2)
      y: Math.round(root.activeCellY - root.activeCellH / 2)
      width: root.activeCellW
      height: root.activeCellH

      Rectangle {
        anchors.fill: parent
        color: Style.selectedAccentFill
        border.width: Math.max(1, Style.selectedBorderWidth)
        border.color: root.accentColor
        radius: Style.cornerRadius
      }

      Repeater {
        model: 9

        Item {
          required property int index

          x: Math.round((index % 3) * (parent.width / 3))
          y: Math.round(Math.floor(index / 3) * (parent.height / 3))
          width: Math.round(parent.width / 3)
          height: Math.round(parent.height / 3)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.subGridKeys.charAt(index)
            color: root.fgColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      // Exact click point
      Rectangle {
        x: Math.round(parent.width / 2 - width / 2)
        y: Math.round(parent.height / 2 - height / 2)
        width: Style.spacing.md
        height: width
        radius: width / 2
        color: root.accentColor
      }
    }

    // Mode indicator, only when something other than a plain left click is active
    Rectangle {
      visible: root.modeLabel !== ""
      // Bottom edge sits between the last hint row and the screen edge, clear of the bar
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.gapsOut
      anchors.horizontalCenter: parent.horizontalCenter
      width: modeText.implicitWidth + Style.spacing.controlPaddingX * 2
      height: Style.spacing.controlHeight
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.width: Style.normalBorderWidth
      border.color: Commons.Color.popups.border

      Text {
        id: modeText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.modeLabel
        color: Commons.Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
