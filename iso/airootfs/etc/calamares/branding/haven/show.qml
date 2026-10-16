import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 9000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    function onActivate() { }
    function onLeave() { }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0f1720" }
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#e6edf3"; font.pixelSize: 22
            text: "<b>Your Windows games, ready to play</b><br><br>Steam and Proton come installed. Thousands of Windows games run straight from your library."
        }
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0f1720" }
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#e6edf3"; font.pixelSize: 22
            text: "<b>Private by default</b><br><br>No telemetry. Encrypted DNS. A firewall that blocks unwanted connections. A different network ID on every Wi-Fi."
        }
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0f1720" }
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#e6edf3"; font.pixelSize: 22
            text: "<b>Tuned for games</b><br><br>The Haven kernel uses the BORE scheduler, a 1000Hz timer and NTSYNC — the Windows sync system, built into the kernel."
        }
    }
}
