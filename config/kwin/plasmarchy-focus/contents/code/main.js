// Publish the active window class to the user journal so that the
// plasmarchy-cmd clipboard helper can choose the right terminal chord without
// a slow synchronous KWin query.  The helper reads the last line:
//
//   PLASMARCHY-FOCUS <resourceClass>
//
// Only changes are logged; an initial line is emitted when the script loads.

var lastClass = null;

function activeClass(window) {
    if (!window) {
        window = workspace.activeWindow;
    }
    if (!window || window.deleted) {
        return "";
    }
    return window.resourceClass || window.resourceName || "";
}

function report(window) {
    var cls = activeClass(window);
    if (cls !== lastClass) {
        lastClass = cls;
        print("PLASMARCHY-FOCUS " + cls);
    }
}

workspace.windowActivated.connect(report);
report(workspace.activeWindow);
print("PLASMARCHY-FOCUS-LOADED");
