import QtQuick
import Quickshell
import qs.Ui

BarWidget {
  id: root
  moduleName: "gothe92.omatap"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    tooltipText: "Omatap"
    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        if (root.bar) root.bar.run("omarchy-shell shell toggle gothe92.omatap '{}'")
        else Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "gothe92.omatap", "{}"])
      }
    }
  }
}
