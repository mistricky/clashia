import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property real uploadSpeed: 0
  property real downloadSpeed: 0
  property var uploadHistory: []
  property var downloadHistory: []
  property int historyMax: 60
  property real peakSpeed: 1024
  property real animProgress: 1
  property int sampleIntervalMs: 1000
  property string peakLabelText: ""
  property string uploadSpeedText: ""
  property string downloadSpeedText: ""
  property double sampleStartedAt: Date.now()
  property real smoothAnimProgress: 1
  readonly property real chartHeight: 100
  readonly property real legendHeight: Math.max(8, Style.fontSizeS)
  readonly property real totalPreferredHeight: chartHeight + legendHeight + Style.marginS

  Layout.fillWidth: true
  Layout.topMargin: -Style.marginM
  Layout.preferredHeight: totalPreferredHeight

  onAnimProgressChanged: trafficChart.requestPaint()
  onUploadSpeedChanged: restartChartAnimation()
  onDownloadSpeedChanged: restartChartAnimation()
  onUploadHistoryChanged: restartChartAnimation()
  onDownloadHistoryChanged: restartChartAnimation()
  onPeakSpeedChanged: trafficChart.requestPaint()

  function restartChartAnimation() {
    root.sampleStartedAt = Date.now();
    root.smoothAnimProgress = 0;
    animationTimer.start();
    trafficChart.requestPaint();
  }

  Timer {
    id: animationTimer
    interval: 16
    repeat: true
    running: false

    onTriggered: {
      var elapsed = Date.now() - root.sampleStartedAt;
      root.smoothAnimProgress = Math.max(0, Math.min(1, elapsed / Math.max(1, root.sampleIntervalMs)));
      trafficChart.requestPaint();

      if (root.smoothAnimProgress >= 1)
        stop();
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.marginS

    Canvas {
      id: trafficChart
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 100
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d");
        var w = width;
        var h = height;
        var progress = animationTimer.running ? root.smoothAnimProgress : root.animProgress;

        ctx.clearRect(0, 0, w, h);

        var upHist = root.uploadHistory;
        var downHist = root.downloadHistory;
        var maxPoints = root.historyMax;
        var peak = root.peakSpeed;

        if (peak <= 0) peak = 1024;

        ctx.strokeStyle = Qt.rgba(Color.mOnSurfaceVariant.r, Color.mOnSurfaceVariant.g, Color.mOnSurfaceVariant.b, 0.15);
        ctx.lineWidth = 1;

        for (var gi = 1; gi <= 3; gi++) {
          var gy = h - (h * gi / 4);
          ctx.beginPath();
          ctx.moveTo(0, gy);
          ctx.lineTo(w, gy);
          ctx.stroke();
        }

        function drawLine(data, color) {
          if (data.length < 2) return;

          var step = w / (maxPoints - 1);
          var scrollOffset = progress * step;
          var baseOffset = (maxPoints - data.length) * step - scrollOffset;

          ctx.strokeStyle = color;
          ctx.lineWidth = 1;
          ctx.lineJoin = "round";
          ctx.lineCap = "round";

          ctx.save();
          ctx.beginPath();
          ctx.rect(0, 0, w, h);
          ctx.clip();

          ctx.beginPath();

          var firstX = 0;
          var lastX = 0;

          for (var i = 0; i < data.length; i++) {
            var x = baseOffset + i * step;
            var y = h - (data[i] / peak) * h;

            if (y < 0) y = 0;

            if (i === 0) {
              firstX = x;
              ctx.moveTo(x, y);
            } else {
              ctx.lineTo(x, y);
              lastX = x;
            }
          }

          ctx.stroke();
          ctx.lineTo(lastX, h);
          ctx.lineTo(firstX, h);
          ctx.closePath();

          var parsed = Qt.color(color);
          var gradient = ctx.createLinearGradient(0, 0, 0, h);
          gradient.addColorStop(0, Qt.rgba(parsed.r, parsed.g, parsed.b, 0.2));
          gradient.addColorStop(1, Qt.rgba(parsed.r, parsed.g, parsed.b, 0.02));
          ctx.fillStyle = gradient;
          ctx.fill();

          ctx.restore();
        }

        drawLine(downHist, Color.mPrimary.toString());
        drawLine(upHist, "#4CAF50");

        var fadeW = w * 0.08;

        ctx.save();
        ctx.globalCompositeOperation = "destination-out";

        var leftGrad = ctx.createLinearGradient(0, 0, fadeW, 0);
        leftGrad.addColorStop(0, "rgba(0,0,0,1)");
        leftGrad.addColorStop(1, "rgba(0,0,0,0)");
        ctx.fillStyle = leftGrad;
        ctx.fillRect(0, 0, fadeW, h);

        var rightGrad = ctx.createLinearGradient(w - fadeW, 0, w, 0);
        rightGrad.addColorStop(0, "rgba(0,0,0,0)");
        rightGrad.addColorStop(1, "rgba(0,0,0,1)");
        ctx.fillStyle = rightGrad;
        ctx.fillRect(w - fadeW, 0, fadeW, h);

        ctx.restore();
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: root.peakLabelText
        font.pointSize: Style.fontSizeS * 0.85
        color: Qt.alpha(Color.mOnSurface, 0.6)
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        Layout.preferredWidth: 8
        Layout.preferredHeight: 8
        radius: 4
        color: "#4CAF50"
      }

      NText {
        text: root.uploadSpeedText
        font.pointSize: Style.fontSizeS * 0.85
        color: Color.mOnSurface
      }

      Rectangle {
        Layout.preferredWidth: 8
        Layout.preferredHeight: 8
        radius: 4
        color: Color.mPrimary
      }

      NText {
        text: root.downloadSpeedText
        font.pointSize: Style.fontSizeS * 0.85
        color: Color.mOnSurface
      }
    }
  }
}
