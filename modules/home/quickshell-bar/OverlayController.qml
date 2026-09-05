import QtQuick

QtObject {
    id: root

    property string activeSurface: ""

    signal dismissRequested(string except)

    function claim(surface: string): void {
        dismissRequested(surface);
        activeSurface = surface;
    }

    function dismissAll(): void {
        dismissRequested("");
        activeSurface = "";
    }

    function release(surface: string): void {
        if (activeSurface === surface)
            activeSurface = "";
    }
}
