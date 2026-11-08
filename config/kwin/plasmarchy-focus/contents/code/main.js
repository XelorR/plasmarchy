// Publish the active window class to the user journal so that the
// plasmarchy-cmd clipboard helper can choose the right terminal chord without
// a slow synchronous KWin query.  The helper reads the last line:
//
//   PLASMARCHY-FOCUS <resourceClass>
//
// Only changes are logged; an initial line is emitted when the script loads.

var lastClass = null;
var lastPid = 0;
var lastCaption = "";

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
    var pid = (window && !window.deleted && window.pid) ? window.pid : 0;
    var caption = (window && !window.deleted && window.caption) ? window.caption : "";
    // Report on each focus change or process change, not only on a class
    // change.  Same-app switching otherwise kept a stale source window.
    if (cls !== lastClass || pid !== lastPid || caption !== lastCaption) {
        lastClass = cls;
        lastPid = pid;
        lastCaption = caption;
        print("PLASMARCHY-FOCUS " + cls + " " + pid + " " + caption);
        print("PLASMARCHY-WINDOW " + pid + " " + cls + " | " + caption);
    }
}

workspace.windowActivated.connect(report);
report(workspace.activeWindow);
print("PLASMARCHY-FOCUS-LOADED");
