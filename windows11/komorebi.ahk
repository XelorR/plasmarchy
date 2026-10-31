#Requires AutoHotkey v2.0
#SingleInstance Force
; Plasmarchy for Windows 11.
;
; Win (Meta) is the leader key, matching Omarchy/Plasmarchy on KDE Plasma.
; Window manipulation is delegated to komorebic.exe; this file only translates
; the Omarchy key map and implements terminal-aware clipboard chords.
;
; Install target: %USERPROFILE%\komorebi.ahk (or $env:KOMOREBI_CONFIG_HOME).

SetWorkingDir(A_ScriptDir)
Persistent

KomorebicPath := FindExecutable(["komorebic-no-console.exe", "komorebic.exe"])

; ---------------------------------------------------------------------------
; Process discovery

FindExecutable(names, extraDirs := []) {
    dirs := [
        A_ScriptDir,
        EnvGet("USERPROFILE"),
        EnvGet("LOCALAPPDATA") . "\Microsoft\WinGet\Links",
        EnvGet("LOCALAPPDATA") . "\Microsoft\WindowsApps",
        EnvGet("LOCALAPPDATA") . "\Programs",
        EnvGet("LOCALAPPDATA") . "\Programs\komorebi",
        EnvGet("LOCALAPPDATA") . "\PowerToys",
        EnvGet("LOCALAPPDATA") . "\Microsoft\PowerToys",
        EnvGet("ProgramFiles"),
        EnvGet("ProgramFiles(x86)"),
        EnvGet("ProgramFiles") . "\komorebi",
        EnvGet("ProgramFiles(x86)") . "\komorebi",
        EnvGet("ProgramFiles") . "\PowerToys",
        EnvGet("ProgramFiles(x86)") . "\PowerToys"
    ]
    for d in extraDirs
        dirs.Push(d)

    for name in names {
        for d in dirs {
            if (d = "")
                continue
            p := d . "\" . name
            if FileExist(p)
                return p
        }
        for d in StrSplit(EnvGet("PATH"), ";") {
            if (d = "")
                continue
            p := d . "\" . name
            if FileExist(p)
                return p
        }
    }
    return ""
}

RunKomorebi(args) {
    global KomorebicPath
    if (KomorebicPath = "") {
        TrayTip("komorebic.exe not found. Re-run install-windows.ps1.", "Plasmarchy", 1)
        return
    }
    try {
        Run('"' . KomorebicPath . '" ' . args, , "Hide")
    } catch {
        TrayTip("Could not run komorebic: " . args, "Plasmarchy", 1)
    }
}

OpenApp(target) {
    try {
        Run(target)
    } catch {
        TrayTip("Not installed or not on PATH: " . target, "Plasmarchy", 1)
    }
}

OpenUrl(url) {
    try {
        Run(url)
    } catch {
        TrayTip("Could not open: " . url, "Plasmarchy", 1)
    }
}

; ---------------------------------------------------------------------------
; Keyboard/terminal helpers

ReleaseModifiers() {
    ; KGlobalAccel on Linux fires while the physical Meta key is down; Windows
    ; behaves the same way. Hotkeys also leave Ctrl/Alt/Shift physically down.
    ; Release every modifier before injecting a different chord, otherwise
    ; Win+Ctrl+C becomes Ctrl+Win+C in the target application.
    Send("{LWin up}{RWin up}{LCtrl up}{RCtrl up}{LAlt up}{RAlt up}{LShift up}{RShift up}")
    Sleep(30)
}

IsWindowsTerminal() {
    ; Windows Terminal and the terminals with Ctrl+Shift+C/V bindings.
    ; OpenConsole.exe is the Windows Terminal console host; conhost.exe is the
    ; legacy console host and keeps Ctrl+C/V.
    exe := WinGetProcessName("A")
    return exe ~= "i)^(WindowsTerminal|WindowsTerminalPreview|wt|OpenConsole|Alacritty|wezterm-gui|mintty|Tabby|Hyper)\.exe$"
}

IsBrowser() {
    exe := WinGetProcessName("A")
    return exe ~= "i)^(chrome|msedge|brave|firefox|zen|librewolf|floorp|waterfox|opera|vivaldi)\.exe$"
}

SendTerminalAware(key) {
    ReleaseModifiers()
    ; Windows Terminal / Alacritty / WezTerm / mintty use Ctrl+Shift+C/V.
    ; Legacy conhost and cmd/powershell.exe consoles use Ctrl+C/V.
    if IsWindowsTerminal()
        Send("^+" . key)
    else
        Send("^" . key)
}

CopyUrl() {
    if !IsBrowser() {
        TrayTip("The active window is not a supported browser.", "Plasmarchy", 1)
        return
    }
    ; This hotkey is Alt+Shift+L, so both modifiers must be released before
    ; sending Ctrl+L / Ctrl+C.
    ReleaseModifiers()
    Send("^l")
    Sleep(60)
    Send("^c")
}

DownloadClipboard() {
    url := Trim(A_Clipboard)
    if (url = "" || !(url ~= "i)^https?://")) {
        TrayTip("Put an http(s) URL on the clipboard first.", "Plasmarchy", 1)
        return
    }
    ytdlp := FindExecutable(["yt-dlp.exe"])
    if (ytdlp = "") {
        TrayTip("yt-dlp.exe is not installed or not on PATH.", "Plasmarchy", 1)
        return
    }
    TerminalRun('"' . ytdlp . '" "' . url . '"')
}

TerminalRun(command) {
    wt := FindExecutable(["wt.exe"])
    if (wt != "")
        Run('"' . wt . '" ' . command)
    else
        Run(command)
}

TerminalLinux(command) {
    wsl := FindExecutable(["wsl.exe"])
    if (wsl != "")
        TerminalRun('"' . wsl . '" -e ' . command)
    else
        TerminalRun(command)
}

OpenTerminal() {
    wt := FindExecutable(["wt.exe"])
    if (wt != "")
        Run('"' . wt . '"')
    else
        Run("powershell.exe")
}

OpenTerminalTmux() {
    TerminalLinux("tmux new -A -s Work")
}

OpenRun() {
    ReleaseModifiers()
    ; PowerToys Run registers Alt+Space globally. If PowerToys is not running,
    ; Windows opens the window system menu, so detect and start it when possible.
    if ProcessExist("PowerToys.exe") || ProcessExist("PowerToys.PowerLauncher.exe") {
        Send("!Space")
        return
    }
    launcher := FindExecutable(["PowerToys.PowerLauncher.exe"])
    if (launcher != "") {
        Run('"' . launcher . '"')
        Sleep(250)
    }
    Send("!Space")
}

TaskView() {
    ; Opens Task View without depending on the Win+Tab hotkey, which is
    ; intentionally rebound to the next Komorebi workspace.
    Run("explorer.exe shell:::{3080F90E-D7AD-11D9-BD98-0000947B0257}")
}

OpenPrivateBrowser() {
    candidates := [
        [EnvGet("ProgramFiles") . "\Mozilla Firefox\firefox.exe", "-private-window"],
        [EnvGet("ProgramFiles") . "\Google\Chrome\Application\chrome.exe", "--incognito"],
        [EnvGet("ProgramFiles") . "\BraveSoftware\Brave-Browser\Application\brave.exe", "--incognito"],
        [EnvGet("ProgramFiles(x86)") . "\Microsoft\Edge\Application\msedge.exe", "--inprivate"],
        [EnvGet("LOCALAPPDATA") . "\Programs\Opera\opera.exe", "--private"],
        [EnvGet("LOCALAPPDATA") . "\Vivaldi\Application\vivaldi.exe", "--incognito"],
        [EnvGet("LOCALAPPDATA") . "\Programs\Zen Browser\zen.exe", "-private-window"]
    ]
    for c in candidates {
        if FileExist(c[1]) {
            Run('"' . c[1] . '" ' . c[2])
            return
        }
    }
    OpenBrowser()
}

OpenBrowser() {
    ; Let the default browser resolve the URL; this avoids hard-coding a browser.
    OpenUrl("https://www.google.com")
}

OpenScreenshotRegion() {
    Run("ms-screenclip:")
}

SendAltBacktick(shifted) {
    ReleaseModifiers()
    if shifted
        Send("!+{SC029}")
    else
        Send("!{SC029}")
}

StartGameBarRecording() {
    ReleaseModifiers()
    Send("#!r")
}

OpenColorPicker() {
    exe := FindExecutable(["PowerToys.ColorPickerUI.exe"])
    if (exe = "") {
        TrayTip("PowerToys Color Picker was not found.", "Plasmarchy", 1)
        return
    }
    Run('"' . exe . '"')
}

OpenTextExtractor() {
    exe := FindExecutable(["PowerToys.TextExtractor.exe"])
    if (exe = "") {
        TrayTip("PowerToys Text Extractor was not found.", "Plasmarchy", 1)
        return
    }
    Run('"' . exe . '"')
}

ShowTime() {
    TrayTip("Time: " . FormatTime(A_Now, "HH:mm"), "Plasmarchy", 1)
}

ToggleDictation() {
    ReleaseModifiers()
    Send("#h")
}

EmojiPicker() {
    ReleaseModifiers()
    Send("#.")
}

LockScreen() {
    Run("rundll32.exe user32.dll,LockWorkStation")
}

PowerMenu() {
    ; Windows has no public API for the Ctrl+Alt+Del screen. SlideToShutDown
    ; is the closest built-in power overlay; the full menu remains on Win+X.
    Run("SlideToShutDown.exe")
}

; ---------------------------------------------------------------------------
; Layout switching for the Right Ctrl tap (F24 from kanata.kbd)

SwitchLayout() {
    hwnd := WinExist("A")
    if !hwnd
        return

    count := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0)
    if (count < 2)
        return

    buf := Buffer(count * A_PtrSize)
    DllCall("GetKeyboardLayoutList", "Int", count, "Ptr", buf.Ptr)

    threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
    current := DllCall("GetKeyboardLayout", "UInt", threadId, "Ptr")
    idx := 0
    Loop count {
        hkl := NumGet(buf, (A_Index - 1) * A_PtrSize, "Ptr")
        if (hkl = current) {
            idx := A_Index
            break
        }
    }

    if (idx = 0)
        next := NumGet(buf, 0, "Ptr")
    else
        next := NumGet(buf, Mod(idx, count) * A_PtrSize, "Ptr")

    ; WM_INPUTLANGCHANGEREQUEST = 0x0050. PostMessage is intentionally used
    ; instead of activating the layout on the AHK thread only.
    PostMessage(0x0050, 0, next, , "ahk_id " . hwnd)
}

; ---------------------------------------------------------------------------
; Session and shell

#Space::OpenRun()
#!Space::TaskView()
#g::TaskView()
#k::Run("ms-settings:keyboard")
#^l::LockScreen()
#Escape::PowerMenu()
#^i::Run("ms-settings:signinoptions")

#Tab::RunKomorebi("cycle-workspace next")
#+Tab::RunKomorebi("cycle-workspace previous")
^!Tab::RunKomorebi("cycle-monitor next")
^!+Tab::RunKomorebi("cycle-monitor previous")

; App-specific Alt+Tab replacement. Windows has no native per-application
; switcher; Alt+` is the closest common convention. Release Win/Alt first.
#!Tab::SendAltBacktick(false)
#!+Tab::SendAltBacktick(true)

; ---------------------------------------------------------------------------
; Workspaces: Meta+<digit> focuses, Meta+Shift+<digit> moves and follows,
; Meta+Shift+Alt+<digit> moves without changing the current view.

#1::RunKomorebi("focus-workspace 0")
#2::RunKomorebi("focus-workspace 1")
#3::RunKomorebi("focus-workspace 2")
#4::RunKomorebi("focus-workspace 3")
#5::RunKomorebi("focus-workspace 4")
#6::RunKomorebi("focus-workspace 5")
#7::RunKomorebi("focus-workspace 6")
#8::RunKomorebi("focus-workspace 7")
#9::RunKomorebi("focus-workspace 8")

#+1::RunKomorebi("move-to-workspace 0")
#+2::RunKomorebi("move-to-workspace 1")
#+3::RunKomorebi("move-to-workspace 2")
#+4::RunKomorebi("move-to-workspace 3")
#+5::RunKomorebi("move-to-workspace 4")
#+6::RunKomorebi("move-to-workspace 5")
#+7::RunKomorebi("move-to-workspace 6")
#+8::RunKomorebi("move-to-workspace 7")
#+9::RunKomorebi("move-to-workspace 8")

#+!1::RunKomorebi("send-to-workspace 0")
#+!2::RunKomorebi("send-to-workspace 1")
#+!3::RunKomorebi("send-to-workspace 2")
#+!4::RunKomorebi("send-to-workspace 3")
#+!5::RunKomorebi("send-to-workspace 4")
#+!6::RunKomorebi("send-to-workspace 5")
#+!7::RunKomorebi("send-to-workspace 6")
#+!8::RunKomorebi("send-to-workspace 7")
#+!9::RunKomorebi("send-to-workspace 8")

; ---------------------------------------------------------------------------
; Tiling and focus

#Left::RunKomorebi("focus left")
#Right::RunKomorebi("focus right")
#Up::RunKomorebi("focus up")
#Down::RunKomorebi("focus down")

#+Left::RunKomorebi("move left")
#+Right::RunKomorebi("move right")
#+Up::RunKomorebi("move up")
#+Down::RunKomorebi("move down")

#^+Left::RunKomorebi("cycle-move-to-monitor previous")
#^+Right::RunKomorebi("cycle-move-to-monitor next")

#^Left::RunKomorebi("cycle-monitor previous")
#^Right::RunKomorebi("cycle-monitor next")

#t::RunKomorebi("toggle-float")
; Win+L is reserved by Windows and cannot be intercepted by AutoHotkey.
; kanata.kbd rewrites bare physical Win+L to F23 before Windows sees it, and
; the F23 handler below performs the Omarchy "next layout" action.
; Win+Ctrl+L remains the lock-screen shortcut; Kanata excludes modified
; chords so Win+Ctrl+L is not rewritten.
F23::RunKomorebi("cycle-layout next")
#!l::RunKomorebi("cycle-layout previous")
#j::RunKomorebi("flip-layout horizontal")

#f::RunKomorebi("toggle-monocle")
#!f::RunKomorebi("toggle-maximize")
#^f::RunKomorebi("toggle-maximize")

#=::RunKomorebi("resize-axis horizontal decrease")
#-::RunKomorebi("resize-axis horizontal increase")
#+=::RunKomorebi("resize-axis vertical increase")
#+-::RunKomorebi("resize-axis vertical decrease")

#w::RunKomorebi("close")
#q::RunKomorebi("close")

; ---------------------------------------------------------------------------
; Clipboard. These are deliberately terminal-aware: Windows Terminal uses
; Ctrl+Shift+C/V/X, legacy consoles use Ctrl+C/V.

#c::SendTerminalAware("c")
#x::SendTerminalAware("x")
#v::SendTerminalAware("v")

!+l::CopyUrl()
!+d::DownloadClipboard()

; ---------------------------------------------------------------------------
; Applications

#Enter::OpenTerminal()
#!Enter::OpenTerminalTmux()

#+Enter::OpenBrowser()
#+b::OpenBrowser()
#+!b::OpenPrivateBrowser()

#+f::OpenApp("explorer.exe")
#+SC035::OpenApp("keepassxc.exe")
#+q::OpenApp("calc.exe")
#+t::TerminalLinux("btop")
#+n::TerminalLinux("nvim")
#+c::OpenApp("outlookcal:")
#+e::OpenApp("thunderbird.exe")
#+!e::OpenApp("thunderbird.exe -compose")
#+a::OpenUrl("https://chatgpt.com/")
#+!a::OpenUrl("https://grok.com/")
#+g::OpenApp("signal.exe")
#+p::OpenUrl("https://photos.google.com/")
#+s::OpenUrl("https://maps.google.com/")
#+!g::OpenUrl("https://web.whatsapp.com/")
#+^g::OpenUrl("https://messages.google.com/web/")
#+o::OpenApp("obsidian://open")
#+w::OpenApp("notepad.exe")
#+x::OpenUrl("https://x.com/")
#+!x::OpenUrl("https://x.com/compose/post")
#+y::OpenUrl("https://www.youtube.com/")
#+d::TerminalLinux("lazydocker")
#+!m::OpenApp("vlc.exe")

#^x::ToggleDictation()
F9::ToggleDictation()

#^e::EmojiPicker()
#^t::Run("ms-settings:themes")
#^+Space::Run("ms-settings:themes")
#^w::Run("ms-settings:personalization-background")
#^Space::Run("ms-settings:personalization-background")

#^a::Run("ms-settings:sound")
#^b::Run("ms-settings:bluetooth")
#^n::Run("ms-settings:network")
#^d::Run("ms-settings:display")
#^p::Run("ms-settings:batterysaver")
#^s::OpenApp("localsend.exe")
#^c::OpenApp("snippingtool.exe")
#^h::OpenApp("msinfo32.exe")
#^r::OpenApp("outlookcal:")
#^SC034::OpenApp("HandBrake.exe")

#^!c::OpenScreenshotRegion()
#^!t::ShowTime()
#^!b::Run("ms-settings:batterysaver")
#^!w::OpenUrl("https://wttr.in/?format=3")
#^!r::OpenApp("outlookcal:")
#^!e::Run("ms-clock:")
#^!d::Run("ms-clock:")

#^Delete::Run("DisplaySwitch.exe /internal")
#^!Delete::Run("DisplaySwitch.exe /clone")

PrintScreen::OpenScreenshotRegion()
!PrintScreen::StartGameBarRecording()
#PrintScreen::OpenColorPicker()
#^PrintScreen::OpenTextExtractor()

; F24 is emitted by kanata.kbd when Right Ctrl is tapped. Holding Right Ctrl
; still produces Ctrl, because kanata maps the hold action to lctl.
F24::SwitchLayout()
