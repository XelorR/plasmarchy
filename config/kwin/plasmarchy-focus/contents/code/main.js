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
        var pid = (window && !window.deleted && window.pid) ? window.pid : 0;
        var caption = (window && !window.deleted && window.caption) ? window.caption : "";
        // Keep the class as the first token for backward compatibility.
        // Also publish the window caption because it is often the only place
    // that exposes the current Dolphin/Konsole/Kate location.
    // Preserve the original PLASMARCHY-FOCUS line.
    print("PLASMARCHY-FOCUS " + cls + " " + pid + " " + caption);

    // A diagnostics line may be parsed by context-aware launchers.
    print("PLASMARCHY-WINDOW " + pid + " " + cls + " | " + caption);
    }
}

workspace.windowActivated.connect(report);
report(workspace.activeWindow);
print("PLASMARCHY-FOCUS-LOADED");
