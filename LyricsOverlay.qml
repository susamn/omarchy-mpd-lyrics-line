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
  property var lyricsData: ({
    state: "stopped",
    title: "",
    artist: "",
    file: "",
    type: "none",
    elapsed: 0.0,
    duration: 0.0,
    lines: []
  })
  property int currentIndex: -1

  property string fontFamily: Style.font.family
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  property color scrim: Color.polkit.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.space(20)
  property int cardWidth: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)

  // Exactly 7 visible rows: 3 above (Rows 0-2), 1 active (Row 3, stationary center), 3 upcoming (Rows 4-6)
  property int rowHeight: Style.space(32)
  readonly property int viewportHeight: rowHeight * 7

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

  function seekTo(targetSec) {
    Quickshell.execDetached(["bash", root.pluginPath + "/scripts/lyrics.sh", "seek", String(targetSec)])
    if (root.lyricsData && root.lyricsData.type === "synced") {
      root.lyricsData.elapsed = targetSec
      root.updateCurrentIndex(true)
    }
  }

  function refreshLyrics() {
    if (lyricsProc.running) return
    lyricsProc.command = ["bash", root.pluginPath + "/scripts/lyrics.sh"]
    lyricsProc.running = true
  }

  function updateCurrentIndex(forceScroll) {
    if (!root.lyricsData || !root.lyricsData.lines || root.lyricsData.lines.length === 0) {
      root.currentIndex = -1
      return
    }

    if (root.lyricsData.type === "synced") {
      var elapsed = Number(root.lyricsData.elapsed || 0)
      var lines = root.lyricsData.lines
      var idx = -1

      for (var i = 0; i < lines.length; i++) {
        if (lines[i].time <= elapsed) {
          idx = i
        } else {
          break
        }
      }

      var indexChanged = (idx !== root.currentIndex)
      root.currentIndex = idx

      if ((indexChanged || forceScroll) && idx >= 0) {
        lyricsList.contentY = (idx - 3) * root.rowHeight
      }
    }
  }

  function applyLyrics(text) {
    try {
      var parsed = JSON.parse(text)
      if (parsed) {
        var fileChanged = (!root.lyricsData || parsed.file !== root.lyricsData.file)
        root.lyricsData = parsed
        root.updateCurrentIndex(fileChanged)
      }
    } catch (e) {
      console.warn("Error parsing lyrics JSON:", e)
    }
  }

  Timer {
    id: lyricsTimer
    interval: 350
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
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
      height: cardColumn.implicitHeight + card.contentTopInset + card.contentBottomInset
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      radius: root.cornerRadius

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            root.close()
            event.accepted = true
            return
          }

          var canScroll = (root.lyricsData.type === "synced" || root.lyricsData.type === "plain")
          if (!canScroll) return

          if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            lyricsList.contentY = Math.min(lyricsList.contentHeight - lyricsList.height, lyricsList.contentY + root.rowHeight)
            event.accepted = true
          } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            lyricsList.contentY = Math.max(lyricsList.originY, lyricsList.contentY - root.rowHeight)
            event.accepted = true
          } else if ((event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) || event.key === Qt.Key_PageDown) {
            lyricsList.contentY = Math.min(lyricsList.contentHeight - lyricsList.height, lyricsList.contentY + 2 * root.rowHeight)
            event.accepted = true
          } else if ((event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) || event.key === Qt.Key_PageUp) {
            lyricsList.contentY = Math.max(lyricsList.originY, lyricsList.contentY - 2 * root.rowHeight)
            event.accepted = true
          } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            lyricsList.contentY = Math.max(lyricsList.originY, lyricsList.contentHeight - lyricsList.height)
            event.accepted = true
          } else if (event.key === Qt.Key_G) {
            lyricsList.contentY = lyricsList.originY
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
        Item {
          width: parent.width
          height: Math.max(headerIcon.implicitHeight, headerTextCol.implicitHeight, closeBtn.implicitHeight)

          Text {
            id: headerIcon
            text: "󰝚"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Button {
            id: closeBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅙"
            iconSize: Style.font.iconSmall
            foreground: root.foreground
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            tooltipText: "Close"
            onClicked: root.close()
          }

          Column {
            id: headerTextCol
            anchors.left: headerIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: closeBtn.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.lyricsData.title || "No track playing"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Row {
              spacing: Style.space(8)
              width: parent.width

              Text {
                text: root.lyricsData.artist || ""
                visible: text !== ""
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }

              // Badge for lyrics mode
              BorderSurface {
                visible: root.lyricsData.type === "plain" || root.lyricsData.type === "synced"
                anchors.verticalCenter: parent.verticalCenter
                color: root.lyricsData.type === "synced" ? Util.alpha(root.accent, 0.15) : Util.alpha(root.foreground, 0.08)
                borderSpec: Border.flat(root.lyricsData.type === "synced" ? root.accent : Qt.darker(root.foreground, 1.8), 1)
                radius: Style.space(4)
                padding: Style.space(2)

                Text {
                  anchors.centerIn: parent
                  text: root.lyricsData.type === "synced" ? "SYNCED LRC" : "PLAIN TXT"
                  color: root.lyricsData.type === "synced" ? root.accent : Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.tiny
                  font.bold: true
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        // Fixed 7-Row Viewport
        Item {
          id: viewportContainer
          width: parent.width
          height: root.viewportHeight
          clip: true

          // Scrollable 7-Row List
          ListView {
            id: lyricsList
            anchors.fill: parent
            model: root.lyricsData.lines || []
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: root.lyricsData.type === "plain"

            // Header creates 3 blank rows so Line 0 starts at Row 3 (preceded by 3 rows above)
            header: Item {
              width: lyricsList.width
              height: 3 * root.rowHeight
            }

            // Footer creates 3 blank rows so the final line can reach Row 3 (followed by 3 rows below)
            footer: Item {
              width: lyricsList.width
              height: 3 * root.rowHeight
            }

            onCountChanged: {
              if (root.currentIndex >= 0 && root.lyricsData.type === "synced") {
                Qt.callLater(function() {
                  lyricsList.contentY = (root.currentIndex - 3) * root.rowHeight
                })
              }
            }

            Behavior on contentY {
              NumberAnimation {
                duration: 380
                easing.type: Easing.OutCubic
              }
            }

            delegate: Item {
              id: lineDelegate
              width: lyricsList.width
              height: root.rowHeight

              readonly property bool isSynced: root.lyricsData.type === "synced"
              readonly property bool isSyncedActive: (isSynced && index === root.currentIndex)
              readonly property int offset: isSynced ? (index - root.currentIndex) : 0
              readonly property string lineText: isSynced ? (modelData.text || "") : String(modelData || "")
              readonly property string displayText: (lineText === "" && isSyncedActive) ? "♪ ♪ ♪" : lineText

              // Symmetrical 7-row vignetted opacity curve:
              // Offset  0 (Current active): 1.0 (bold, bright accent)
              // Offset ±1 (1 line away):    0.65
              // Offset ±2 (2 lines away):   0.40
              // Offset ±3 (3 lines away):   0.20
              // Outside:                    0.0
              readonly property real targetOpacity: {
                if (!isSynced) return 0.85
                if (isSyncedActive) return 1.0
                if (offset === -1 || offset === 1) return 0.65
                if (offset === -2 || offset === 2) return 0.40
                if (offset === -3 || offset === 3) return 0.20
                return 0.0
              }

              Item {
                id: lineContent
                anchors.centerIn: parent
                width: parent.width - Style.space(24)

                Text {
                  anchors.centerIn: parent
                  width: parent.width
                  text: lineDelegate.displayText
                  color: lineDelegate.isSyncedActive ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: lineDelegate.isSyncedActive ? Style.font.heading : ((Math.abs(lineDelegate.offset) === 1) ? Style.font.body : Style.font.bodySmall)
                  font.bold: lineDelegate.isSyncedActive
                  horizontalAlignment: lineDelegate.isSynced ? Text.AlignHCenter : Text.AlignLeft
                  elide: Text.ElideRight
                  opacity: lineDelegate.targetOpacity

                  Behavior on opacity {
                    NumberAnimation { duration: 320; easing.type: Easing.OutQuad }
                  }
                  Behavior on color {
                    ColorAnimation { duration: 250 }
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: lineDelegate.isSynced ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (lineDelegate.isSynced && modelData.time !== undefined) {
                    root.seekTo(modelData.time)
                  }
                }
              }
            }
          }



          // Empty state: No lyrics found
          Column {
            anchors.centerIn: parent
            visible: root.lyricsData.type === "none" || !root.lyricsData.lines || root.lyricsData.lines.length === 0
            spacing: Style.space(10)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰎆"
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              color: Qt.darker(root.foreground, 1.8)
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.lyricsData.state === "stopped" ? "No track currently playing" : "No lyrics found"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.lyricsData.state === "stopped" ? "Start playing music in MPD to view lyrics" : "No .lrc or .txt file found for this track"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }



        PanelSeparator {
          foreground: root.foreground
        }

        // Footer Navigation Hint
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.lyricsData.type === "synced" ? "Click line to seek" : (root.lyricsData.type === "plain" ? "Vim: j/k to scroll, d/u half page, gg/G top/bottom" : "")
            color: Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            width: parent.width - parent.childrenRect.width - Style.space(16)
            height: 1
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Esc or q to dismiss"
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}




