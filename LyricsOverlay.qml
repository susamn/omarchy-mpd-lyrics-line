import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property string pluginPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/susamn.mpd-lyrics"
  property var lyricsData: ({ state: "stopped", title: "", artist: "", lines: ["", "", "", ""], hasLyrics: false })

  property string fontFamily: Style.font.family
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  property color scrim: Color.polkit.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(480), panel.width - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.refreshLyrics()
    lyricsTimer.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    lyricsTimer.stop()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  IpcHandler {
    target: "susamn.mpd-lyrics"

    function toggle(): void {
      root.toggle()
    }

    function open(): void {
      root.open("{}")
    }

    function close(): void {
      root.close()
    }
  }

  function refreshLyrics() {
    if (lyricsProc.running) return
    lyricsProc.command = ["bash", root.pluginPath + "/scripts/lyrics.sh"]
    lyricsProc.running = true
  }

  function applyLyrics(text) {
    try {
      var parsed = JSON.parse(text)
      if (parsed) root.lyricsData = parsed
    } catch (e) {
      console.warn("Error parsing lyrics JSON:", e)
    }
  }

  Timer {
    id: lyricsTimer
    interval: 500
    repeat: true
    running: root.opened
    onTriggered: root.refreshLyrics()
  }

  Process {
    id: lyricsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyLyrics(text)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-mpd-lyrics"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: cardColumn.implicitHeight + card.contentTopInset + card.contentBottomInset + root.contentMargin * 2
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      radius: root.cornerRadius

      MouseArea {
        anchors.fill: parent
        onClicked: {} // Keep clicks inside card from dismissing scrim
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          }
        }
      }

      Column {
        id: cardColumn
        anchors.left: parent.left
        anchors.leftMargin: card.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: card.contentRightInset
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        spacing: Style.space(12)

        // Header Row
        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: "󰝚"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(64)
            spacing: Style.space(2)

            Text {
              text: root.lyricsData.title || "No track playing"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodyLarge
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.lyricsData.artist || ""
              visible: text !== ""
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅙"
            iconSize: Style.font.iconSmall
            foreground: root.foreground
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            tooltipText: "Close"
            onClicked: root.close()
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        // Lyrics 4-Line Synced Window
        Column {
          width: parent.width
          spacing: Style.space(6)

          // Line 0: Previous line
          Text {
            visible: root.lyricsData.hasLyrics
            width: parent.width
            text: (root.lyricsData.lines && root.lyricsData.lines[0]) ? root.lyricsData.lines[0] : " "
            color: Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
          }

          // Line 1: Active Singing Line (Highlighted with Pill / Accent)
          BorderSurface {
            visible: root.lyricsData.hasLyrics
            width: parent.width
            color: Util.alpha(root.accent, 0.12)
            borderSpec: Border.flat(root.accent, Style.normalBorderWidth)
            radius: Style.cornerRadius
            padding: Style.space(10)

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(12)
              text: (root.lyricsData.lines && root.lyricsData.lines[1]) ? root.lyricsData.lines[1] : "♪ ♪ ♪"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodyLarge
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          // Line 2: Upcoming Line 1
          Text {
            visible: root.lyricsData.hasLyrics
            width: parent.width
            text: (root.lyricsData.lines && root.lyricsData.lines[2]) ? root.lyricsData.lines[2] : " "
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
          }

          // Line 3: Upcoming Line 2
          Text {
            visible: root.lyricsData.hasLyrics
            width: parent.width
            text: (root.lyricsData.lines && root.lyricsData.lines[3]) ? root.lyricsData.lines[3] : " "
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
          }

          // Placeholder when no synced lyrics available
          Column {
            visible: !root.lyricsData.hasLyrics
            width: parent.width
            spacing: Style.space(8)
            topPadding: Style.space(10)
            bottomPadding: Style.space(10)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰎆"
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              color: Qt.darker(root.foreground, 1.6)
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.lyricsData.state === "playing" ? "No synced lyrics available" : "Nothing playing"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        // Footer Hint
        Item {
          width: parent.width
          height: Style.space(14)
          Text {
            anchors.right: parent.right
            text: "Press Esc or click outside to dismiss"
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
