import Quickshell
import QtQuick

// Arctis Pro Wireless base settings. The base cannot report its settings, so
// every control shows the value last sent from this PC.
Scope {
    id: root

    required property var service
    required property Item anchorItem
    required property var overlayController
    readonly property string overlayName: "headset"
    property bool shown: false

    readonly property var eqPresets: [
        "Balanced", "Immersion", "Performance", "Entertainment", "Music", "Voice", "Profile 1"
    ]

    function reveal(): void {
        overlayController.claim(overlayName);
        shown = true;
    }

    function close(): void {
        shown = false;
        overlayController.release(overlayName);
    }

    function toggle(): void {
        if (shown)
            close();
        else
            reveal();
    }

    function value(name: string): var {
        return service.settings[name] ?? null;
    }

    Connections {
        target: root.overlayController

        function onDismissRequested(except: string): void {
            if (except !== root.overlayName && root.shown)
                root.close();
        }
    }

    // One labelled settings row; the control goes in as its child.
    component SettingRow: Item {
        id: settingRow

        required property string label
        default property alias control: controlSlot.data

        width: parent.width
        height: Math.max(labelText.implicitHeight, controlSlot.childrenRect.height)

        Text {
            id: labelText

            width: 104
            anchors.top: parent.top
            anchors.topMargin: 6
            text: settingRow.label
            color: "@subdued@"
            font.family: "@fontFamily@"
            font.pixelSize: 12
        }

        Item {
            id: controlSlot

            anchors.left: labelText.right
            anchors.right: parent.right
            height: childrenRect.height
        }
    }

    component Choice: Rectangle {
        id: choice

        required property string label
        required property bool selected
        signal picked()

        width: choiceText.implicitWidth + 16
        height: 26
        radius: 8
        color: selected ? "@accentSurface@" : choiceMouse.containsMouse ? "@surface@" : "transparent"
        border.width: 1
        border.color: selected ? "@accent@" : "@border@"

        Text {
            id: choiceText

            anchors.centerIn: parent
            text: choice.label
            color: choice.selected ? "@accent@" : "@text@"
            font.family: "@fontFamily@"
            font.pixelSize: 12
            font.weight: choice.selected ? Font.DemiBold : Font.Normal
        }

        MouseArea {
            id: choiceMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.picked()
        }
    }

    component StepButton: Rectangle {
        id: stepButton

        required property string symbol
        required property bool available
        signal pressed()

        width: 26
        height: 26
        radius: 8
        color: stepMouse.containsMouse && available ? "@accentSurface@" : "@surface@"
        border.width: 1
        border.color: "@border@"
        opacity: available ? 1 : 0.4

        Text {
            anchors.centerIn: parent
            text: stepButton.symbol
            color: "@text@"
            font.family: "@fontFamily@"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: stepMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: stepButton.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (stepButton.available)
                    stepButton.pressed();
            }
        }
    }

    // Steps a 0..maximum setting; `format` turns the raw value into the
    // base menu's wording.
    component Stepper: Row {
        id: stepper

        required property string setting
        required property int maximum
        required property var format
        readonly property var current: root.value(setting)

        spacing: 6

        function step(delta: int): void {
            // An unknown value starts from the bottom of the range.
            const next = current === null ? 0 : Math.max(0, Math.min(maximum, current + delta));
            if (next !== current)
                root.service.setSetting(setting, next);
        }

        StepButton {
            symbol: "−"
            available: stepper.current === null || stepper.current > 0
            onPressed: stepper.step(-1)
        }

        Text {
            width: 72
            height: 26
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: stepper.current === null ? "—" : stepper.format(stepper.current)
            color: "@text@"
            font.family: "@fontFamily@"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        StepButton {
            symbol: "+"
            available: stepper.current === null || stepper.current < stepper.maximum
            onPressed: stepper.step(1)
        }
    }

    PopupWindow {
        anchor.item: root.anchorItem
        anchor.rect.x: root.anchorItem ? root.anchorItem.width - implicitWidth : 0
        anchor.rect.y: root.anchorItem ? root.anchorItem.height + 8 : 0
        anchor.rect.width: 1
        anchor.rect.height: 1
        implicitWidth: 380
        implicitHeight: card.implicitHeight
        color: "transparent"
        visible: root.shown && root.anchorItem !== null

        Rectangle {
            id: card

            width: parent.width
            implicitHeight: content.implicitHeight + 24
            radius: 14
            color: "@opaqueSurface@"
            border.width: 1
            border.color: "@border@"

            Column {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 8

                    Column {
                        width: parent.width - closeButton.width - 8
                        spacing: 2

                        Text {
                            text: "Arctis Pro Wireless"
                            color: "@text@"
                            font.family: "@fontFamily@"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            text: root.service.tooltip().replace("\n", " · ")
                            color: "@subdued@"
                            elide: Text.ElideRight
                            font.family: "@fontFamily@"
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        id: closeButton

                        width: 22
                        text: "󰅖"
                        color: "@subdued@"
                        horizontalAlignment: Text.AlignHCenter
                        font.family: "@fontFamily@"
                        font.pixelSize: 14

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                SettingRow {
                    label: "Equalizer"

                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.eqPresets

                            Choice {
                                required property string modelData
                                required property int index
                                label: modelData
                                selected: root.value("eq") === index
                                onPicked: root.service.setSetting("eq", index)
                            }
                        }
                    }
                }

                SettingRow {
                    label: "Sidetone"

                    Stepper {
                        setting: "sidetone"
                        maximum: 9
                        // The base menu shows ten levels on a 0–10 scale.
                        format: value => `${Math.round(value * 10 / 9)}`
                    }
                }

                SettingRow {
                    label: "Mic mute LED"

                    Stepper {
                        setting: "micLed"
                        maximum: 10
                        format: value => `${value * 10}%`
                    }
                }

                SettingRow {
                    label: "Auto-off"

                    Stepper {
                        setting: "autoOff"
                        maximum: 12
                        format: value => value === 0 ? "Never" : `${value * 10} min`
                    }
                }

                SettingRow {
                    label: "Volume limiter"

                    Row {
                        spacing: 6

                        Repeater {
                            model: ["Off", "On"]

                            Choice {
                                required property string modelData
                                required property int index
                                label: modelData
                                selected: root.value("volumeLimiter") === index
                                onPicked: root.service.setSetting("volumeLimiter", index)
                            }
                        }
                    }
                }

                SettingRow {
                    label: "Screen brightness"

                    Stepper {
                        setting: "oledBrightness"
                        maximum: 10
                        format: value => `${value}/10`
                    }
                }

                SettingRow {
                    label: "Screen mode"

                    Row {
                        spacing: 6

                        Repeater {
                            model: ["Dim", "Off", "Screensaver"]

                            Choice {
                                required property string modelData
                                required property int index
                                label: modelData
                                selected: root.value("screenMode") === index
                                onPicked: root.service.setSetting("screenMode", index)
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.service.settingError !== ""
                    text: root.service.settingError
                    color: "@muted@"
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }

                Text {
                    width: parent.width
                    text: "Shows what was last set here. Changes made on the base's own menu don't appear."
                    color: "@subdued@"
                    wrapMode: Text.Wrap
                    font.family: "@fontFamily@"
                    font.pixelSize: 11
                }
            }
        }
    }
}
