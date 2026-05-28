import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras

Item {
    id: launchpadButton

    required property var tasksRoot
    required property var dockRef

    readonly property var appGridApplet: {
        if (!Plasmoid || !Plasmoid.containment || !Plasmoid.containment.applets) return null;
        let applets = Plasmoid.containment.applets;
        for (let j = 0; j < applets.length; ++j) {
            let applet = applets[j];
            if (applet && (applet.pluginName === "dev.xarbit.appgrid" || applet.pluginName === "dev.xarbit.appgrid.panel")) {
                return applet;
            }
        }
        if (Plasmoid.containment.corona && Plasmoid.containment.corona.containments) {
            let containments = Plasmoid.containment.corona.containments;
            for (let i = 0; i < containments.length; ++i) {
                let appletsList = containments[i].applets;
                if (appletsList) {
                    for (let j = 0; j < appletsList.length; ++j) {
                        let applet = appletsList[j];
                        if (applet && (applet.pluginName === "dev.xarbit.appgrid" || applet.pluginName === "dev.xarbit.appgrid.panel")) {
                            return applet;
                        }
                    }
                }
            }
        }
        return null;
    }

    function getIconSource() {
        let applet = launchpadButton.appGridApplet;
        if (applet && applet.configuration) {
            let customImage = applet.configuration.customButtonImage;
            let useCustom = applet.configuration.useCustomButtonImage;
            let iconName = applet.configuration.icon;

            if (useCustom && customImage && customImage.length !== 0) {
                return customImage;
            }
            if (iconName && iconName !== "" && iconName !== "hidden") {
                return iconName;
            }
        }
        return "dev.xarbit.appgrid";
    }

    readonly property real _baseSize: Plasmoid.configuration.iconSize
    readonly property real _sigma: _baseSize * Plasmoid.configuration.amplitud
    readonly property real _zoom: (Plasmoid.configuration.magnification || 0) / 100

    property real zoomFactor: {
        if (!dockRef || _zoom <= 0) return 1.0;
        let mX = dockRef.smoothMouseX;
        if (mX < 0) return 1.0;

        // Use static unzoomed width to avoid binding loops
        let totalWidth = (tasksRoot.taskRepeater.count + 1) * _baseSize;
        let centerOffset = (tasksRoot.taskList.width - totalWidth) / 2;
        let iconCenter = centerOffset + (_baseSize / 2);

        let distance = Math.abs(mX - iconCenter);
        if (distance > _sigma * 3) return 1.0;

        let dynamicZoom = _zoom * entryProgress;
        return 1.0 + dynamicZoom * Math.exp(-(Math.pow(distance, 2) / (2 * Math.pow(_sigma, 2))));
    }

    property real entryProgress: (dockRef && dockRef.insideDock) ? 1.0 : 0.0
    Behavior on entryProgress {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    width: _baseSize * zoomFactor
    height: parent.height

    Item {
        id: iconBox
        width: _baseSize
        height: _baseSize
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 0

        scale: zoomFactor
        transformOrigin: Item.Bottom

        property int baseRenderSize: _baseSize * 2

        Kirigami.Icon {
            id: icon
            width: iconBox.baseRenderSize
            height: iconBox.baseRenderSize
            source: launchpadButton.getIconSource()
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Kirigami.Units.smallSpacing
            transformOrigin: Item.Bottom
            scale: 1 / (iconBox.baseRenderSize / iconBox.width)
        }

        Connections {
            target: launchpadButton.appGridApplet ? launchpadButton.appGridApplet.configuration : null
            ignoreUnknownSignals: true
            function onIconChanged() {
                icon.source = launchpadButton.getIconSource();
            }
            function onUseCustomButtonImageChanged() {
                icon.source = launchpadButton.getIconSource();
            }
            function onCustomButtonImageChanged() {
                icon.source = launchpadButton.getIconSource();
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            triggerAppGrid();
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            launchpadContextMenu.open();
        }
    }

    PlasmaExtras.Menu {
        id: launchpadContextMenu

        PlasmaExtras.MenuItem {
            text: i18n("AppGrid konfigurieren…")
            icon: "settings-configure"
            onClicked: {
                let applet = getAppGridApplet();
                if (applet) {
                    try {
                        let act = applet.internalAction("configure");
                        if (act) {
                            act.trigger();
                        } else if (typeof applet.action === "function") {
                            let act2 = applet.action("configure");
                            if (act2) act2.trigger();
                        }
                    } catch (e) {
                        console.error(e);
                    }
                }
            }
        }

        PlasmaExtras.MenuItem {
            text: {
                let applet = getAppGridApplet();
                return (applet && applet.configuration.icon === "hidden")
                    ? i18n("AppGrid-Symbol auf Panel einblenden")
                    : i18n("AppGrid-Symbol auf Panel ausblenden");
            }
            icon: {
                let applet = getAppGridApplet();
                return (applet && applet.configuration.icon === "hidden")
                    ? "view-visible"
                    : "view-hidden";
            }
            onClicked: {
                let applet = getAppGridApplet();
                if (applet) {
                    if (applet.configuration.icon === "hidden") {
                        applet.configuration.icon = "dev.xarbit.appgrid";
                    } else {
                        applet.configuration.icon = "hidden";
                    }
                }
            }
        }

        PlasmaExtras.MenuItem {
            text: i18n("WaveTask konfigurieren…")
            icon: "configure"
            onClicked: {
                let act = Plasmoid.internalAction("configure");
                if (act) act.trigger();
            }
        }
    }

    function getAppGridApplet() {
        return appGridApplet;
    }

    function triggerAppGrid() {
        let appGridApplet = getAppGridApplet();
        if (appGridApplet) {
            try {
                // In Plasma 6 / AppGrid, emitting the C++ activated signal triggers toggleWindow() in AppGrid's main.qml.
                // We check if the activated method is available and call it, falling back to other actions or expanded toggle.
                if (typeof appGridApplet.activated === "function") {
                    appGridApplet.activated();
                } else if (typeof appGridApplet.internalAction === "function") {
                    let act = appGridApplet.internalAction("trigger");
                    if (act) act.trigger();
                } else if (typeof appGridApplet.action === "function") {
                    let act = appGridApplet.action("trigger");
                    if (act) act.trigger();
                } else {
                    // Fallback to setting expanded property
                    appGridApplet.expanded = !appGridApplet.expanded;
                }

                // Force WaveTask to release any panel popup lock
                Plasmoid.expanded = false;

                // Force the dock out of hover state immediately
                if (dockRef) {
                    dockRef.insideDock = false;
                    dockRef.smoothMouseX = -1;
                }
            } catch (e) {
                console.error("Wavetask: Failed to trigger AppGrid applet", e);
            }
        } else {
            console.warn("Wavetask: AppGrid-Widget (desktop oder panel) konnte auf Ihrem Desktop nicht gefunden werden!");
        }
    }
}
