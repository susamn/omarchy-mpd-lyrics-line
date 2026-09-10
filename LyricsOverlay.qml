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
  property var currentLines: []
  property int currentIndex: -1
  property real lineProgress: 0.0
  property bool showDurationSweep: true

  function toggleDurationSweep() {
    root.showDurationSweep = !root.showDurationSweep
    if (root.showDurationSweep) {
      lineAdvanceTimer.stop()
      root.updateProgress(false)
    } else {
      root.lineProgress = 0.0
      root.scheduleNextLineTimer()
    }
  }

  function scheduleNextLineTimer() {
    if (root.showDurationSweep) {
      lineAdvanceTimer.stop()
      return
    }
    if (!root.opened || !root.lyricsData || root.lyricsData.state !== "playing" || root.lyricsData.type !== "synced") {
      lineAdvanceTimer.stop()
      return
    }
    var remaining = root.activeLineEnd - root.currentElapsed
    if (remaining > 0) {
      lineAdvanceTimer.interval = Math.max(20, Math.round(remaining * 1000))
      lineAdvanceTimer.restart()
    } else {
      lineAdvanceTimer.stop()
    }
  }

  // Local playback clock, advanced by the render loop's own frame deltas. This is
  // strictly monotonic, unlike Date.now(), which NTP or DST can step backwards.
  property real currentElapsed: 0.0
  // Bounds of the active line, recomputed only when currentIndex actually moves.
  property real activeLineStart: 0.0
  property real activeLineEnd: 0.0
  // An idle-watcher push that arrived while a poll was in flight.
  property bool refreshPending: false

  // A poll whose elapsed differs from the local clock by more than this is a real
  // external seek; smaller positive gaps are just latency catch-up.
  readonly property real resyncThresholdSec: 1.2
  readonly property real catchUpThresholdSec: 0.1
  // Keeps a compositor stall from being swallowed whole by a single frame step.
  readonly property real maxFrameStepSec: 0.25

  property string fontFamily: Style.font.family
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  property color scrim: Color.polkit.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.space(20)
  property int cardWidth: panel.width > 0 ? Math.min(Style.space(720), panel.width - Style.gapsOut * 2) : Style.space(720)

  // Exactly 7 visible rows: 3 above (Rows 0-2), 1 active (Row 3, stationary center), 3 upcoming (Rows 4-6)
  property int rowHeight: Style.space(32)
  readonly property int viewportHeight: rowHeight * 7

  function open(payloadJson) {
    root.opened = true
    root.refreshLyrics()
    lyricsTimer.restart()
    idleWatcherRetry.stop()
    idleWatcher.command = ["bash", root.pluginPath + "/scripts/lyrics.sh", "idle"]
    idleWatcher.running = true
    if (!root.showDurationSweep) root.scheduleNextLineTimer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    lyricsTimer.stop()
    lineAdvanceTimer.stop()
    idleWatcher.running = false
    idleWatcherRetry.stop()
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

    function toggleSweep(): void {
      root.toggleDurationSweep()
    }
  }

  function seekTo(targetSec) {
    Quickshell.execDetached(["bash", root.pluginPath + "/scripts/lyrics.sh", "seek", String(targetSec)])
    if (root.lyricsData && root.lyricsData.type === "synced") {
      root.currentElapsed = targetSec
      // MPD applies the seek asynchronously. Polls already in flight still report
      // the pre-seek position; without this guard they read as an external seek
      // and snap the highlight backwards until the real seek lands.
      seekGuard.restart()
      root.updateProgress(true)
      root.scheduleNextLineTimer()
    }
  }

  function refreshLyrics() {
    if (lyricsProc.running) {
      // Remember the request instead of dropping it: an idle-watcher push that
      // lands mid-poll would otherwise wait for the next fallback tick.
      root.refreshPending = true
      return
    }
    root.refreshPending = false
    lyricsProc.command = ["bash", root.pluginPath + "/scripts/lyrics.sh"]
    lyricsProc.running = true
  }

  function updateActiveLineBounds(idx) {
    var lines = root.currentLines
    if (idx < 0 || !lines || idx >= lines.length) {
      root.activeLineStart = 0.0
      root.activeLineEnd = 0.0
      return
    }

    var start = lines[idx].time
    var end = -1
    for (var j = idx + 1; j < lines.length; j++) {
      if (lines[j].time > start) {
        end = lines[j].time
        break
      }
    }

    if (end <= start) {
      var dur = Number((root.lyricsData && root.lyricsData.duration) || 0)
      end = (dur > start) ? dur : (start + 4.0)
    }

    root.activeLineStart = start
    root.activeLineEnd = end
  }

  function updateProgress(forceScroll) {
    var lines = root.currentLines
    if (!lines || lines.length === 0 || !root.lyricsData || root.lyricsData.type !== "synced") {
      root.currentIndex = -1
      root.lineProgress = 0.0
      return
    }

    var elapsed = root.currentElapsed
    var idx = root.currentIndex

    // Fast path: between frames the clock only creeps forward, so the cached index
    // is almost always still correct. Only rescan when it demonstrably is not.
    if (idx < 0 || idx >= lines.length || lines[idx].time > elapsed
        || (idx + 1 < lines.length && lines[idx + 1].time <= elapsed)) {
      idx = -1
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].time <= elapsed) {
          idx = i
        } else {
          break
        }
      }
    }

    var indexChanged = (idx !== root.currentIndex)
    root.currentIndex = idx

    if (indexChanged || forceScroll) {
      lyricsList.contentY = (idx - 3) * root.rowHeight
      root.updateActiveLineBounds(idx)
    }

    if (idx < 0) {
      root.lineProgress = 0.0
      return
    }

    var lineDuration = root.activeLineEnd - root.activeLineStart
    if (root.showDurationSweep && lineDuration > 0) {
      var progress = (elapsed - root.activeLineStart) / lineDuration
      root.lineProgress = Math.max(0.0, Math.min(1.0, progress))
    } else {
      root.lineProgress = 0.0
    }
  }

  function applyLyrics(text) {
    try {
      var parsed = JSON.parse(text)
      if (!parsed) return

      // Track identity is file + lyrics type only. MPD metadata titles can change
      // independently of the track, and must not reset the clock or the view.
      var fileChanged = (!root.lyricsData || parsed.file !== root.lyricsData.file || parsed.type !== root.lyricsData.type)
      var stateChanged = (!root.lyricsData || parsed.state !== root.lyricsData.state)
      var metaChanged = (!root.lyricsData || parsed.title !== root.lyricsData.title || parsed.artist !== root.lyricsData.artist)
      var mpdElapsed = Number(parsed.elapsed || 0)

      if (fileChanged) {
        root.lyricsData = parsed
        root.currentLines = parsed.lines ? parsed.lines : []
        root.currentElapsed = mpdElapsed
        root.updateProgress(true)
        root.scheduleNextLineTimer()
        return
      }

      // Reassign only when something bound actually changed: holding the reference
      // steady keeps the ListView from re-evaluating delegates mid-song.
      if (stateChanged || metaChanged) {
        root.lyricsData = parsed
      }

      // Our own seek is still in flight, so this poll predates it in either state.
      // The state/metadata assignment above still lands; only the clock is held.
      if (seekGuard.running) return

      if (parsed.state !== "playing") {
        // Not playing: MPD's elapsed is authoritative and stable.
        root.currentElapsed = mpdElapsed
        root.updateProgress(false)
        lineAdvanceTimer.stop()
        return
      }

      var diff = mpdElapsed - root.currentElapsed
      if (Math.abs(diff) > root.resyncThresholdSec) {
        // External seek, or the overlay was closed while playback ran on.
        root.currentElapsed = mpdElapsed
        root.updateProgress(true)
        root.scheduleNextLineTimer()
      } else if (diff > root.catchUpThresholdSec) {
        // Local clock lagging the audio: catch up.
        root.currentElapsed = mpdElapsed
        root.updateProgress(false)
        root.scheduleNextLineTimer()
      }
      // Otherwise keep the local clock. MPD's reading is stale by the subprocess
      // round-trip, and stepping backwards onto it is what caused the stutter.
    } catch (e) {
      console.warn("Error parsing lyrics JSON:", e)
    }
  }

  Timer {
    id: lyricsTimer
    interval: 2500
    repeat: true
    running: root.opened
    onTriggered: root.refreshLyrics()
  }

  // Suppresses external-seek reclassification of polls that were already in flight
  // when the user clicked to seek.
  Timer {
    id: seekGuard
    interval: 400
    repeat: false
  }

  FrameAnimation {
    id: progressAnim
    running: root.opened && root.showDurationSweep && root.lyricsData && root.lyricsData.state === "playing" && root.lyricsData.type === "synced"
    onTriggered: {
      root.currentElapsed += Math.max(0.0, Math.min(progressAnim.frameTime, root.maxFrameStepSec))
      root.updateProgress(false)
    }
  }

  // Zero-CPU single-shot timer for line transitions when duration sweep is turned off.
  // It sleeps completely for the entire line duration and fires only once at the line boundary.
  Timer {
    id: lineAdvanceTimer
    interval: 1000
    repeat: false
    running: false
    onTriggered: {
      if (!root.showDurationSweep && root.lyricsData && root.lyricsData.state === "playing") {
        root.currentElapsed = root.activeLineEnd + 0.02
        root.updateProgress(false)
        root.scheduleNextLineTimer()
      }
    }
  }

  Process {
    id: lyricsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyLyrics(text)
    }
    onExited: {
      if (root.refreshPending && root.opened) {
        root.refreshPending = false
        Qt.callLater(root.refreshLyrics)
      }
    }
  }

  // Persistent MPD "idle player" listener: pushes an immediate refresh on
  // seek/play/pause/track-change instead of waiting for the next poll tick.
  Process {
    id: idleWatcher
    stdout: SplitParser {
      onRead: data => root.refreshLyrics()
    }
    onExited: {
      if (root.opened) idleWatcherRetry.restart()
    }
  }

  Timer {
    id: idleWatcherRetry
    interval: 3000
    repeat: false
    onTriggered: {
      if (root.opened) {
        idleWatcher.command = ["bash", root.pluginPath + "/scripts/lyrics.sh", "idle"]
        idleWatcher.running = true
      }
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

          if (event.key === Qt.Key_P) {
            root.toggleDurationSweep()
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
          height: Math.max(headerIcon.implicitHeight, headerTextCol.implicitHeight, headerActions.implicitHeight)

          Text {
            id: headerIcon
            text: "󰝚"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Button {
              id: sweepToggleBtn
              visible: root.lyricsData && root.lyricsData.type === "synced"
              iconText: "󰔛"
              iconSize: Style.font.iconSmall
              foreground: root.showDurationSweep ? root.accent : Qt.darker(root.foreground, 1.6)
              selected: root.showDurationSweep
              horizontalPadding: Style.space(4)
              verticalPadding: Style.space(2)
              tooltipText: root.showDurationSweep ? "Disable line duration sweep (P)" : "Enable line duration sweep (P)"
              onClicked: root.toggleDurationSweep()
            }

            Button {
              id: closeBtn
              iconText: "󰅙"
              iconSize: Style.font.iconSmall
              foreground: root.foreground
              horizontalPadding: Style.space(4)
              verticalPadding: Style.space(2)
              tooltipText: "Close"
              onClicked: root.close()
            }
          }

          Column {
            id: headerTextCol
            anchors.left: headerIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: headerActions.left
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
                  font.pixelSize: Style.font.caption
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
            model: root.currentLines
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
              if (root.lyricsData.type === "synced") {
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
                height: parent.height

                // Active line word background fill (sweeps along with progress).
                // Uses Loader so that when turned off, no Item/Rectangle is created,
                // zero bindings evaluate, and zero CPU/RAM is consumed.
                Loader {
                  id: wordBgLoader
                  active: root.showDurationSweep && lineDelegate.isSyncedActive && lineTextItem.contentWidth > 0
                  visible: active
                  anchors.centerIn: parent
                  width: Math.min(parent.width, lineTextItem.contentWidth + Style.space(16))
                  height: Math.min(parent.height - Style.space(2), lineTextItem.contentHeight + Style.space(6))
                  sourceComponent: Component {
                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: Math.max(0, Math.min(parent.width, parent.width * root.lineProgress))
                      radius: Style.space(6)
                      color: Util.alpha(root.accent, 0.28)
                      border.color: Util.alpha(root.accent, 0.65)
                      border.width: 1
                    }
                  }
                }

                Text {
                  id: lineTextItem
                  anchors.centerIn: parent
                  width: parent.width
                  text: lineDelegate.displayText
                  color: (lineDelegate.isSyncedActive && !root.showDurationSweep) ? root.accent : root.foreground
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
                    ColorAnimation { duration: 200 }
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
            visible: !root.lyricsData || root.lyricsData.type === "none" || !root.currentLines || root.currentLines.length === 0
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
        Item {
          width: parent.width
          height: Math.max(hintText.implicitHeight, dismissText.implicitHeight)

          Text {
            id: hintText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.lyricsData.type === "synced" ? "Click line to seek • p toggle sweep" : (root.lyricsData.type === "plain" ? "Vim: j/k to scroll, d/u half page, gg/G top/bottom" : "")
            color: Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            id: dismissText
            anchors.right: parent.right
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




