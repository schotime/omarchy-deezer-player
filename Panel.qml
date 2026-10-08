import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// This is deliberately an Omarchy-native control surface, not a recreation of
// Deezer's web styling. All colour, font and spacing values come from Color and
// Style, which the shell updates whenever the user changes theme.
BarWidget {
  id: root
  moduleName: "schotime.deezer-player"

  readonly property string binary: String(setting("command", "deezer-tui"))
  readonly property int refreshInterval: Math.max(1000, Number(setting("refreshIntervalMs", 2000)))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  // Deezer's brand purple, used for the bar logo while music is playing.
  readonly property color deezerPurple: "#A238FF"
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var mprisPlayer: {
    for (var i = 0; i < mprisPlayers.length; i++) {
      var player = mprisPlayers[i]
      var name = String(player.identity || player.desktopEntry || "").toLowerCase()
      if (name.indexOf("deezer") !== -1) return player
    }
    return null
  }
  readonly property string artworkUrl: mprisPlayer ? String(mprisPlayer.trackArtUrl || "") : ""

  property string playbackStatus: "offline"
  property string title: "Deezer is not running"
  property string artist: "Launch deezer-tui to start listening"
  property string album: ""
  property real position: 0
  property real duration: 0
  property int volume: 0
  property string lastError: ""
  property bool opened: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The Deezer logo (assets/deezer.svg, white), tinted to `color` the same way
  // the tray recolors symbolic icons.
  component DeezerLogo: Item {
    id: logo
    property color color: root.foreground

    Image {
      id: logoImage
      anchors.fill: parent
      source: Qt.resolvedUrl("assets/deezer.svg")
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      smooth: true
      // Kept as a hidden layer so the effect can sample it as a texture.
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: logoImage
      source: logoImage
      colorization: 1.0
      colorizationColor: logo.color
    }
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  function runAction(action, argument) {
    if (actionProcess.running) return
    actionProcess.action = action
    actionProcess.argument = argument === undefined ? "" : String(argument)
    actionProcess.running = true
  }

  // Seek to a fraction (0..1) of the current track.
  function seekTo(fraction) {
    if (duration <= 0 || actionProcess.running) return
    var seconds = Math.floor(Math.max(0, Math.min(1, fraction)) * duration)
    seconds = Math.min(seconds, Math.max(0, Math.floor(duration) - 1))
    // Move the bar right away; the next status poll confirms it.
    position = seconds
    runAction("--seek", seconds)
  }

  // Transport controls drive whichever player the shell's media service
  // considers active, like the stock media widget and the keyboard media keys.
  // Without the service they fall back to deezer-tui's own CLI.
  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property bool activeIsDeezer: activePlayer !== null && activePlayer === mprisPlayer
  readonly property bool mediaPlaying: activePlayer ? activePlayer.isPlaying : playbackStatus === "playing"
  readonly property bool canControl: mediaService ? activePlayer !== null : playbackStatus !== "offline"

  function mediaAction(action) {
    if (mediaService && activePlayer) {
      mediaService.runAction(action, false, mediaService.playerKey(activePlayer))
      Qt.callLater(root.refresh)
      return
    }
    var cli = { playPause: "--toggle", next: "--next", previous: "--prev" }
    if (cli[action]) root.runAction(cli[action])
  }

  function scriptPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  // The screen corner the bar icon sits in, e.g. "bottom-right": the bar's edge,
  // plus which half of the bar the icon is in.
  function tuiCorner() {
    var edge = bar ? String(bar.position || "top") : "top"
    var window = button.QsWindow.window
    var nearStart = false
    if (window && window.contentItem) {
      var middle = button.mapToItem(window.contentItem, button.width / 2, button.height / 2)
      nearStart = vertical ? middle.y < window.contentItem.height / 2 : middle.x < window.contentItem.width / 2
    }
    if (vertical) return (nearStart ? "top" : "bottom") + "-" + edge
    return edge + "-" + (nearStart ? "left" : "right")
  }

  function openTui() {
    // Keep one TUI window: open-tui.sh slides the drop-down in or out, or
    // focuses a terminal running deezer-tui by hand, before launching.
    if (bar) bar.run("bash " + Util.shellQuote(scriptPath("open-tui.sh")) + " " + Util.shellQuote(root.binary) + " " + Util.shellQuote(tuiCorner()) + " " + Util.shellQuote(bar.position || "top"))
    root.close()
  }

  // Any focus change may have left the drop-down TUI behind. The delay lets
  // follow-mouse focus cross other windows on the way into the drop-down, and
  // hide-tui.sh asks Hyprland whether it is showing, so nothing here goes stale.
  Timer {
    id: hideTimer
    interval: 400
    onTriggered: if (!hideProcess.running) hideProcess.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "activewindowv2") hideTimer.restart()
    }
  }

  Process {
    id: hideProcess
    command: ["bash", root.scriptPath("hide-tui.sh")]
  }

  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value) || 0))
    return Math.floor(seconds / 60) + ":" + ("0" + (seconds % 60)).slice(-2)
  }

  function applyStatus(text) {
    try {
      var data = JSON.parse(String(text))
      playbackStatus = String(data.status || "offline")
      var track = data.track || null
      title = track ? String(track.title || "Unknown track") : "Nothing playing"
      artist = track ? String(track.artist || "") : "Start deezer-tui, then choose music"
      album = track ? String(track.album || "") : ""
      position = Number(data.position_secs || 0)
      duration = Number(data.duration_secs || (track ? track.duration : 0) || 0)
      volume = Number(data.volume_percent || 0)
      lastError = String(data.error || "")
    } catch (error) {
      playbackStatus = "offline"
      title = "Deezer is not running"
      artist = "Launch deezer-tui to start listening"
      album = ""
      position = 0
      duration = 0
      lastError = ""
    }
  }

  onOpenedChanged: if (opened) {
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    command: [root.binary, "--status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: actionProcess
    property string action: ""
    property string argument: ""
    command: argument === "" ? [root.binary, action] : [root.binary, action, argument]
    onExited: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      // The Loader resizes its item to the full icon canvas, so the logo sits
      // inside a wrapper. It is sized to the painted bounds of the bar's
      // music-note glyph at the bar icon font size, so it matches the
      // neighbouring glyph icons and follows theme size changes.
      Item {
        TextMetrics {
          id: referenceGlyph
          font.family: button.fontFamily
          font.pixelSize: Math.max(1, Math.round(button.fontSize))
          text: "󰝚"
        }

        DeezerLogo {
          anchors.centerIn: parent
          width: Math.max(referenceGlyph.tightBoundingRect.width, referenceGlyph.tightBoundingRect.height)
          height: width
          color: root.playbackStatus === "playing" ? root.deezerPurple : button.foreground
        }
      }
    }
    active: root.playbackStatus === "playing"
    tooltipText: root.title + (root.artist ? " — " + root.artist : "")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openTui()
      else if (buttonCode === Qt.MiddleButton) root.mediaAction("playPause")
      else root.toggle()
    }
    // Same as the stock media widget: scroll up for previous, down for next.
    onWheelMoved: function(delta) {
      if (delta > 0) root.mediaAction("previous")
      else if (delta < 0) root.mediaAction("next")
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(310))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.mediaAction("playPause")
      onTextKey: function(key) {
        if (key === "n") root.mediaAction("next")
        else if (key === "b") root.mediaAction("previous")
        else if (key === "r") root.refresh()
        else if (key === "o") root.openTui()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(12)

          Rectangle {
            width: Style.space(52)
            height: width
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            clip: true

            Image {
              anchors.fill: parent
              visible: root.artworkUrl !== ""
              source: root.artworkUrl
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }

            DeezerLogo {
              anchors.centerIn: parent
              width: Style.font.display
              height: width
              visible: root.artworkUrl === ""
              color: root.accent
            }
          }

          Column {
            width: parent.width - Style.space(64)
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: root.title
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.artist
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              visible: root.album !== ""
              width: parent.width
              text: root.album
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(4)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
          visible: root.duration > 0

          Rectangle {
            width: parent.width * Math.min(1, root.position / root.duration)
            height: parent.height
            radius: parent.radius
            color: root.accent
          }

          // The bar is only a few pixels tall, so the click target extends
          // above and below it.
          MouseArea {
            anchors.fill: parent
            anchors.topMargin: -Style.space(6)
            anchors.bottomMargin: -Style.space(6)
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) { root.seekTo(mouse.x / width) }
          }
        }

        Row {
          width: parent.width
          visible: root.duration > 0
          Text { id: currentTime; text: root.formatTime(root.position); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Item { width: parent.width - currentTime.implicitWidth - rightTime.implicitWidth; height: 1 }
          Text { id: rightTime; text: root.formatTime(root.duration); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        }

        // Transport controls on the left, Open TUI pinned to the right edge.
        Item {
          width: parent.width
          height: Math.max(transport.implicitHeight, openTuiButton.implicitHeight)

          Row {
            id: transport
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Button { text: "󰒮"; enabled: root.canControl; onClicked: root.mediaAction("previous") }
            Button { text: root.mediaPlaying ? "󰏤" : "󰐊"; enabled: root.canControl; onClicked: root.mediaAction("playPause") }
            Button { text: "󰒭"; enabled: root.canControl; onClicked: root.mediaAction("next") }
          }

          Button {
            id: openTuiButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Open TUI"
            onClicked: root.openTui()
          }
        }

        // The track details above are Deezer's; say so when the buttons are
        // steering some other player.
        Text {
          visible: root.activePlayer !== null && !root.activeIsDeezer
          width: parent.width
          text: "Controls: " + (root.activePlayer ? (root.activePlayer.identity || root.activePlayer.desktopEntry || "media player") : "")
            + (root.activePlayer && root.activePlayer.trackTitle ? " — " + root.activePlayer.trackTitle : "")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          visible: root.playbackStatus === "offline"
          width: parent.width
          text: "Right-click the bar icon or use Open TUI to launch deezer-tui."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
