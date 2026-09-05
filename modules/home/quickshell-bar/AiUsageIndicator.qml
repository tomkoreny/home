import Quickshell
import QtQuick
import QtQuick.Effects

Item {
    id: aiLimitsHost
    required property var root

    property bool tooltipVisible: false

    width: aiLimitsRow.implicitWidth + 12
    height: parent.height

    Row {
        id: aiLimitsRow

        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: [
                {
                    providerId: "openai-codex",
                    logo: "@openaiLogo@"
                },
                {
                    providerId: "anthropic",
                    logo: "@anthropicLogo@"
                }
            ]

            Row {
                id: providerLimit

                required property var modelData
                anchors.verticalCenter: parent.verticalCenter

                spacing: 4

                Item {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: providerLogoSource

                        anchors.fill: parent
                        source: providerLimit.modelData.logo
                        sourceSize.width: 14
                        sourceSize.height: 14
                        fillMode: Image.PreserveAspectFit
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: providerLogoSource
                        source: providerLogoSource
                        colorization: 1
                        colorizationColor: root.aiProviderColor(providerLimit.modelData.providerId)
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -1

                    Repeater {
                        model: root.aiBarLimits(providerLimit.modelData.providerId)

                        Text {
                            required property var modelData

                            text: `${root.aiWindowIcon(modelData.windowId)} ${root.aiRemainingText(modelData)} ${root.aiResetText(modelData)}`
                            color: root.aiRemainingColor(modelData.remaining)
                            font.family: "@fontFamily@"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.aiUsageStale
            text: "󰅖"
            color: "@muted@"
            font.family: "@fontFamily@"
            font.pixelSize: 11
        }
    }

    MouseArea {
        id: aiLimitsMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.refreshAiUsage(true)
        onContainsMouseChanged: {
            if (containsMouse) {
                aiTooltipDelay.restart();
            } else {
                aiTooltipDelay.stop();
                aiLimitsHost.tooltipVisible = false;
            }
        }
    }

    Timer {
        id: aiTooltipDelay

        interval: 500
        onTriggered: {
            if (aiLimitsMouse.containsMouse)
                aiLimitsHost.tooltipVisible = true;
        }
    }

    PopupWindow {
        anchor.item: aiLimitsHost
        anchor.rect.x: aiLimitsHost.width - implicitWidth
        anchor.rect.y: aiLimitsHost.height + 6
        anchor.rect.width: 1
        anchor.rect.height: 1
        implicitWidth: aiTooltipText.implicitWidth + 20
        implicitHeight: aiTooltipText.implicitHeight + 16
        color: "@opaqueSurface@"
        visible: aiLimitsHost.tooltipVisible

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "transparent"
            border.width: 1
            border.color: "@border@"
        }

        Text {
            id: aiTooltipText

            anchors.centerIn: parent
            text: root.aiUsageTooltip()
            color: "@text@"
            font.family: "@fontFamily@"
            font.pixelSize: 12
            lineHeight: 1.25
        }
    }
}
