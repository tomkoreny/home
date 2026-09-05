import QtQuick
import QtQuick.Effects

Item {
    id: aiLimitsHost
    required property var root

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
    }

    HoverPopover {
        anchorItem: aiLimitsMouse
        hovered: aiLimitsMouse.containsMouse
        text: root.aiUsageTooltip()
        alignRight: true
    }
}
