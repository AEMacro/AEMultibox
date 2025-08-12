#Requires AutoHotkey v2.0
#SingleInstance Force

; ================================
; Version and Update Configuration
; ================================
global SCRIPT_VERSION := "1.0.1"  ; INCREMENT THIS WITH EACH RELEASE
global UPDATE_CHECK_URL := "https://api.github.com/repos/AEMacro/AEMultibox/releases/latest"
global MANUAL_CHECK_URL := "https://github.com/AEMacro/AEMultibox/releases/latest"
global UPDATE_CHECK_ON_START := true
global UPDATE_CHECK_INTERVAL := 3600000  ; Check every hour (in milliseconds)

; Determine if running as compiled EXE or script
global IS_COMPILED := A_IsCompiled
global FILE_EXTENSION := IS_COMPILED ? ".exe" : ".ahk"

; ================================
; Admin / startup
; ================================
global USE_MEMORY_READING := true

; Check for updates before anything else (if enabled)
if (UPDATE_CHECK_ON_START) {
    CheckForUpdates(false)  ; false = automatic check (silent if no update)
}

if !A_IsAdmin {
    result := MsgBox(
        "This script works best with administrator privileges to read game memory for accurate combat detection.`n`n" .
        "Would you like to run as administrator?`n`n" .
        "(If you choose No, the script will use cursor color detection instead)",
        "Admin Recommended", 0x34)
    if (result == "Yes") {
        try {
            if (IS_COMPILED) {
                Run '*RunAs "' . A_ScriptFullPath . '"'
            } else {
                Run '*RunAs "' . A_AhkPath . '" /restart "' . A_ScriptFullPath . '"'
            }
        } catch {
            MsgBox("Failed to elevate. Falling back to cursor color detection.", "Notice", 0x30)
            USE_MEMORY_READING := false
        }
        ExitApp
    } else {
        USE_MEMORY_READING := false
    }
}

SetTitleMatchMode(2)
DetectHiddenWindows true
CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"

; ================================
; Globals
; ================================
global TargetExeName := "AshenEmpires.exe"
global TargetExe := "ahk_exe " . TargetExeName
global Window1Class := "Sandbox:Ashen_empires:WindowsClass"
global Window2Class := "WindowsClass"

; memory addresses
global GlobalManagerAddress := 0x744074
global CombatModeOffset := 0x2A8
global ChatBaseOffset := 0x323084
global ChatFinalOffset := 0x6AC

; state
global isLooping := false
global USE_CHAT_DETECTION := true
global FOLLOW_ENABLED := true

global windowChatModes := Map()

global qPressInverted := false
global lastQPressTime := 0
global doublePressDuration := 300

global selectedFKey := "F8"
global followDirection := "Switching To Sandbox (Main follows Alt)"

global windowCombatStates := Map()
global windowProcessHandles := Map()
global moduleBaseAddresses := Map()

global lastWindowCount := -1
global lastCombatStatus := ""
global lastWindow1Status := ""
global lastWindow2Status := ""
global lastChatStatus := ""

; ================================
; Auto-Update Functions
; ================================
CheckForUpdates(isManual := true) {
    global SCRIPT_VERSION, UPDATE_CHECK_URL, MANUAL_CHECK_URL, IS_COMPILED, FILE_EXTENSION
    
    ; Create a temporary file for the response
    tempFile := A_Temp . "\ae_update_check.json"
    
    try {
        ; Download the release info
        Download(UPDATE_CHECK_URL, tempFile)
        
        ; Read the JSON response
        jsonText := FileRead(tempFile)
        
        ; Parse version from tag_name (assumes format like "v1.0.0")
        if (RegExMatch(jsonText, '"tag_name"\s*:\s*"v?([^"]+)"', &match)) {
            latestVersion := match[1]
            
            ; Compare versions
            if (CompareVersions(latestVersion, SCRIPT_VERSION) > 0) {
                ; Parse download URL based on file type
                downloadUrl := ""
                searchPattern := IS_COMPILED ? '"browser_download_url"\s*:\s*"([^"]+\.exe)"' : '"browser_download_url"\s*:\s*"([^"]+\.ahk)"'
                
                if (RegExMatch(jsonText, searchPattern, &urlMatch)) {
                    downloadUrl := urlMatch[1]
                }
                
                ; Parse release notes
                releaseNotes := ""
                if (RegExMatch(jsonText, '"body"\s*:\s*"([^"]*)"', &notesMatch)) {
                    releaseNotes := StrReplace(notesMatch[1], "\r\n", "`n")
                    releaseNotes := StrReplace(releaseNotes, "\n", "`n")
                }
                
                ; Show update dialog
                message := "A new version is available!`n`n"
                message .= "Current Version: " . SCRIPT_VERSION . "`n"
                message .= "Latest Version: " . latestVersion . "`n`n"
                
                if (releaseNotes != "") {
                    message .= "Release Notes:`n" . releaseNotes . "`n`n"
                }
                
                message .= "Would you like to update now?"
                
                result := MsgBox(message, "Update Available", 0x34)
                
                if (result == "Yes") {
                    if (downloadUrl != "") {
                        PerformUpdate(downloadUrl)
                    } else {
                        ; Fallback to manual download
                        fileType := IS_COMPILED ? "EXE" : "AHK"
                        MsgBox("Automatic download URL not found for " . fileType . " file. Opening release page...", "Update", 0x40)
                        Run(MANUAL_CHECK_URL)
                    }
                }
            } else if (isManual) {
                MsgBox("You are running the latest version (" . SCRIPT_VERSION . ")", "No Updates", 0x40)
            }
        } else if (isManual) {
            MsgBox("Could not parse version information from GitHub.", "Update Check Failed", 0x30)
        }
        
    } catch as err {
        if (isManual) {
            MsgBox("Failed to check for updates: " . err.Message . "`n`nPlease check your internet connection or try again later.", "Update Check Failed", 0x30)
        }
    } finally {
        ; Clean up temp file
        try FileDelete(tempFile)
    }
}

PerformUpdate(downloadUrl) {
    global IS_COMPILED
    
    ; Create backup of current file
    backupPath := A_ScriptFullPath . ".backup"
    tempPath := A_ScriptFullPath . ".new"
    
    try {
        ; Show progress
        progress := Gui("+AlwaysOnTop -MinimizeBox", "Updating...")
        progress.Add("Text", "w300 Center", "Downloading update...")
        progressBar := progress.Add("Progress", "w300 h20 Range0-100", 0)
        statusText := progress.Add("Text", "w300 Center", "")
        progress.Show()
        
        ; Backup current file
        statusText.Text := "Creating backup..."
        FileCopy(A_ScriptFullPath, backupPath, 1)
        progressBar.Value := 20
        
        ; Download new version
        statusText.Text := "Downloading new version..."
        Download(downloadUrl, tempPath)
        progressBar.Value := 60
        
        ; Verify download
        if (!FileExist(tempPath)) {
            throw Error("Download failed - file not found")
        }
        
        ; Check if downloaded file is valid (basic size check)
        downloadedSize := FileGetSize(tempPath)
        if (downloadedSize < 1000) {  ; Less than 1KB is probably an error
            throw Error("Downloaded file appears to be invalid (too small)")
        }
        
        progressBar.Value := 80
        statusText.Text := "Preparing to restart..."
        
        ; Create batch file for replacement
        batchPath := A_Temp . "\update_ae_multibox.bat"
        
        ; Get the current PID for checking
        currentPID := ProcessExist()
        
        batchContent := "@echo off`r`n"
        batchContent .= "chcp 65001 > nul`r`n"  ; UTF-8 support
        batchContent .= "echo Waiting for application to close (PID: " . currentPID . ")...`r`n"
        batchContent .= "timeout /t 3 /nobreak > nul`r`n"  ; Initial wait
        
        ; More robust process checking
        batchContent .= ":waitloop`r`n"
        batchContent .= 'tasklist /FI "PID eq ' . currentPID . '" 2>NUL | find "' . currentPID . '" >NUL`r`n'
        batchContent .= 'if "%ERRORLEVEL%"=="0" (`r`n'
        batchContent .= "    echo Process still running, waiting...`r`n"
        batchContent .= "    timeout /t 1 /nobreak > nul`r`n"
        batchContent .= "    goto waitloop`r`n"
        batchContent .= ")`r`n"
        batchContent .= "`r`n"
        
        ; Additional safety wait
        batchContent .= "echo Process closed. Waiting additional 2 seconds for file release...`r`n"
        batchContent .= "timeout /t 2 /nobreak > nul`r`n"
        batchContent .= "`r`n"
        
        ; Check if old file still exists and is locked
        batchContent .= ":checklock`r`n"
        batchContent .= 'if exist "' . A_ScriptFullPath . '" (`r`n'
        batchContent .= '    2>nul (>>"' . A_ScriptFullPath . '" echo off) && (`r`n'
        batchContent .= "        echo File is unlocked, proceeding with update...`r`n"
        batchContent .= "    ) || (`r`n"
        batchContent .= "        echo File is still locked, waiting...`r`n"
        batchContent .= "        timeout /t 1 /nobreak > nul`r`n"
        batchContent .= "        goto checklock`r`n"
        batchContent .= "    )`r`n"
        batchContent .= ")`r`n"
        batchContent .= "`r`n"
        
        ; Delete old file first, then move new one
        batchContent .= "echo Updating application...`r`n"
        batchContent .= 'if exist "' . A_ScriptFullPath . '" del /f /q "' . A_ScriptFullPath . '"`r`n'
        batchContent .= "timeout /t 1 /nobreak > nul`r`n"
        batchContent .= 'move /y "' . tempPath . '" "' . A_ScriptFullPath . '"`r`n'
        batchContent .= "`r`n"
        
        ; Error checking
        batchContent .= 'if not exist "' . A_ScriptFullPath . '" (`r`n'
        batchContent .= "    echo ERROR: Failed to update file. Restoring backup...`r`n"
        batchContent .= '    if exist "' . backupPath . '" (`r`n'
        batchContent .= '        move /y "' . backupPath . '" "' . A_ScriptFullPath . '"`r`n'
        batchContent .= "    )`r`n"
        batchContent .= "    echo Update failed! Press any key to exit...`r`n"
        batchContent .= "    pause > nul`r`n"
        batchContent .= "    exit /b 1`r`n"
        batchContent .= ")`r`n"
        batchContent .= "`r`n"
        
        ; Start updated application
        batchContent .= "echo Starting updated application...`r`n"
        batchContent .= "timeout /t 1 /nobreak > nul`r`n"
        
        if (IS_COMPILED) {
            batchContent .= 'start "" "' . A_ScriptFullPath . '"`r`n'
        } else {
            batchContent .= 'start "" "' . A_AhkPath . '" "' . A_ScriptFullPath . '"`r`n'
        }
        
        batchContent .= "`r`n"
        batchContent .= "echo Cleaning up...`r`n"
        batchContent .= 'if exist "' . backupPath . '" del /f /q "' . backupPath . '"`r`n'
        batchContent .= 'timeout /t 2 /nobreak > nul`r`n'
        batchContent .= 'del /f /q "%~f0"`r`n'  ; Delete the batch file itself
        
        ; Write batch file
        FileAppend(batchContent, batchPath)
        
        ; Also create a VBScript for more reliable file operations
        vbsPath := A_Temp . "\update_ae_multibox.vbs"
        vbsContent := 'Set objFSO = CreateObject("Scripting.FileSystemObject")' . "`r`n"
        vbsContent .= 'Set objShell = CreateObject("WScript.Shell")' . "`r`n"
        vbsContent .= 'WScript.Sleep 3000' . "`r`n"  ; Wait 3 seconds
        vbsContent .= '' . "`r`n"
        
        ; Check if process is gone
        vbsContent .= 'strComputer = "."' . "`r`n"
        vbsContent .= 'Set objWMIService = GetObject("winmgmts:\\" & strComputer & "\root\cimv2")' . "`r`n"
        vbsContent .= 'Set colProcesses = objWMIService.ExecQuery("Select * from Win32_Process Where ProcessId = ' . ProcessExist() . '")' . "`r`n"
        vbsContent .= 'Do While colProcesses.Count > 0' . "`r`n"
        vbsContent .= '    WScript.Sleep 500' . "`r`n"
        vbsContent .= '    Set colProcesses = objWMIService.ExecQuery("Select * from Win32_Process Where ProcessId = ' . ProcessExist() . '")' . "`r`n"
        vbsContent .= 'Loop' . "`r`n"
        vbsContent .= '' . "`r`n"
        
        ; Additional wait
        vbsContent .= 'WScript.Sleep 2000' . "`r`n"
        vbsContent .= '' . "`r`n"
        
        ; Replace the file
        vbsContent .= 'On Error Resume Next' . "`r`n"
        vbsContent .= 'If objFSO.FileExists("' . StrReplace(A_ScriptFullPath, "\", "\\") . '") Then' . "`r`n"
        vbsContent .= '    objFSO.DeleteFile "' . StrReplace(A_ScriptFullPath, "\", "\\") . '", True' . "`r`n"
        vbsContent .= 'End If' . "`r`n"
        vbsContent .= 'WScript.Sleep 500' . "`r`n"
        vbsContent .= 'objFSO.MoveFile "' . StrReplace(tempPath, "\", "\\") . '", "' . StrReplace(A_ScriptFullPath, "\", "\\") . '"' . "`r`n"
        vbsContent .= '' . "`r`n"
        
        ; Start the new version
        vbsContent .= 'WScript.Sleep 1000' . "`r`n"
        if (IS_COMPILED) {
            vbsContent .= 'objShell.Run """' . StrReplace(A_ScriptFullPath, "\", "\\") . '"""' . "`r`n"
        } else {
            vbsContent .= 'objShell.Run """' . StrReplace(A_AhkPath, "\", "\\") . '""" ""' . StrReplace(A_ScriptFullPath, "\", "\\") . '"""' . "`r`n"
        }
        
        ; Clean up
        vbsContent .= 'If objFSO.FileExists("' . StrReplace(backupPath, "\", "\\") . '") Then' . "`r`n"
        vbsContent .= '    objFSO.DeleteFile "' . StrReplace(backupPath, "\", "\\") . '", True' . "`r`n"
        vbsContent .= 'End If' . "`r`n"
        vbsContent .= 'WScript.Sleep 1000' . "`r`n"
        vbsContent .= 'objFSO.DeleteFile WScript.ScriptFullName, True' . "`r`n"
        
        FileAppend(vbsContent, vbsPath)
        
        progressBar.Value := 100
        statusText.Text := "Restarting application..."
        
        Sleep(500)
        progress.Destroy()
        
        ; Try VBScript first, then batch as fallback
        try {
            Run('wscript.exe "' . vbsPath . '"', , "Hide")
        } catch {
            try {
                Run(batchPath, , "Hide")
            } catch {
                ; Last resort: show manual instructions
                MsgBox("Automatic update failed. The new version has been downloaded as:`n`n" . tempPath . 
                      "`n`nPlease manually:`n1. Close this application`n2. Delete the old file`n3. Rename the .new file to remove '.new'`n4. Run the updated version", 
                      "Manual Update Required", 0x30)
                return
            }
        }
        
        ; Give a moment for the script to start
        Sleep(100)
        ExitApp
        
    } catch as err {
        ; Restore backup if something went wrong
        if (FileExist(backupPath)) {
            try FileCopy(backupPath, A_ScriptFullPath, 1)
        }
        
        MsgBox("Update failed: " . err.Message . "`n`nYour application has not been changed.", "Update Error", 0x30)
        
        ; Clean up
        try FileDelete(tempPath)
        try FileDelete(backupPath)
        try progress.Destroy()
    }
}

CompareVersions(version1, version2) {
    ; Split versions into parts
    v1Parts := StrSplit(version1, ".")
    v2Parts := StrSplit(version2, ".")
    
    ; Pad with zeros if needed
    maxParts := Max(v1Parts.Length, v2Parts.Length)
    Loop (maxParts - v1Parts.Length)
        v1Parts.Push(0)
    Loop (maxParts - v2Parts.Length)
        v2Parts.Push(0)
    
    ; Compare each part
    Loop maxParts {
        v1Num := Integer(v1Parts[A_Index])
        v2Num := Integer(v2Parts[A_Index])
        
        if (v1Num > v2Num)
            return 1
        else if (v1Num < v2Num)
            return -1
    }
    
    return 0  ; Versions are equal
}

; ================================
; GUI
; ================================
global MyGui := Gui(, "AE Multi-Window Tool v" . SCRIPT_VERSION . (IS_COMPILED ? " (EXE)" : ""))
MyGui.Opt("+Resize -MaximizeBox +MinSize250x200")
MyGui.SetFont("s10", "Segoe UI")
MyGui.BackColor := "0xF0F0F0"

global Tab := MyGui.Add("Tab3", "w350", ["Main", "Settings", "Info"])

; Main tab
Tab.UseTab(1)
MyGui.SetFont("s11 Bold", "Segoe UI")
global StatusText := MyGui.Add("Text", "w330 Center", "Status: OFF")
StatusText.SetFont("cRed")

MyGui.SetFont("s9 Norm", "Segoe UI")
global WindowCountText := MyGui.Add("Text", "w330 Center y+5", "Windows Found: 0")

global CombatStatusText := MyGui.Add("Text", "w330 Center y+5", "Combat: Unknown")

global Window1CombatText := MyGui.Add("Text", "w330 Center y+5", "Main Window: Unknown")

global Window2CombatText := MyGui.Add("Text", "w330 Center y+5", "Sandbox Window: Unknown")

global ChatStatusText := MyGui.Add("Text", "w330 Center y+5", "Chat: Inactive")

MyGui.Add("Text", "xs y+10 w330", "─────────────────────────────")

global ChatDetectCheckbox := MyGui.Add("CheckBox", "x20 y+5 Checked", "Enable Memory Chat Detection")
ChatDetectCheckbox.OnEvent("Click", (*) => (USE_CHAT_DETECTION := ChatDetectCheckbox.Value))

global FollowCheckbox := MyGui.Add("CheckBox", "x20 y+5 Checked", "Enable Follow Feature (Tab key)")
FollowCheckbox.OnEvent("Click", (*) => (FOLLOW_ENABLED := FollowCheckbox.Value))

MyGui.SetFont("s8", "Segoe UI")
MyGui.Add("Text", "w330 Center y+10 cGray", "Press PgUp to Start/Stop")

; Settings tab
Tab.UseTab(2)
MyGui.SetFont("s9", "Segoe UI")
MyGui.Add("Text", "Section", "Follow Settings:")
MyGui.Add("Text", "xs y+10", "Follow Key:")

global FKeyDropdown := MyGui.Add("DropDownList", "w100 xs+80 yp-2", ["F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"])
FKeyDropdown.Text := "F8"
FKeyDropdown.OnEvent("Change", (*) => (selectedFKey := FKeyDropdown.Text))

MyGui.Add("Text", "xs y+10", "Send Key When:")

global DirectionDropdown := MyGui.Add("DropDownList", "w330 xs", ["Switching To Sandbox (Main follows Alt)", "Switching From Sandbox (Alt follows Main)"])
DirectionDropdown.Choose(1)
DirectionDropdown.OnEvent("Change", (*) => (followDirection := DirectionDropdown.Text))

MyGui.Add("Text", "xs y+10 w330", "─────────────────────────────")
MyGui.Add("Text", "xs y+5", "Q Key Behavior:")

global qPressInvertCheckbox := MyGui.Add("CheckBox", "xs+10 y+5", "Invert (Single=Active, Double=All)")
qPressInvertCheckbox.OnEvent("Click", (*) => (qPressInverted := qPressInvertCheckbox.Value))

MyGui.Add("Text", "xs y+10 w330", "─────────────────────────────")
MyGui.Add("Text", "xs y+5", "Right Alt + Key:")
MyGui.Add("Text", "xs+10 y+5 w310", "Hold Right Alt and press any key to send it to the other game window")

MyGui.Add("Text", "xs y+10 w330", "─────────────────────────────")
MyGui.Add("Text", "xs y+5", "Auto-Update:")
UpdateButton := MyGui.Add("Button", "xs+10 y+5 w100", "Check Now")
UpdateButton.OnEvent("Click", (*) => CheckForUpdates(true))
MyGui.Add("Text", "xs+120 yp+5", "Version: " . SCRIPT_VERSION . (IS_COMPILED ? " (EXE)" : " (Script)"))

; Info tab
Tab.UseTab(3)
MyGui.SetFont("s8", "Segoe UI")
MyGui.Add("Text", "w330", "HOTKEYS:")
MyGui.Add("Text", "w330", "• PgUp: Start/Stop (Global)")
MyGui.Add("Text", "w330", "• Tab: Switch Windows (if Follow enabled)")
MyGui.Add("Text", "w330", "• Q / Double Q: Toggles combat")
MyGui.Add("Text", "w330", "  (Default: Single=All, Double=Active)")
MyGui.Add("Text", "w330", "• Right Alt + Any Key: Send to other window")
MyGui.Add("Text", "w330", "• Enter: Toggle chat mode")
MyGui.Add("Text", "w330", "• Esc: Exit chat mode & combat")
MyGui.Add("Text", "w330", "")
MyGui.Add("Text", "w330", "VERSION: " . SCRIPT_VERSION)
MyGui.Add("Text", "w330", "TYPE: " . (IS_COMPILED ? "Compiled EXE" : "AutoHotkey Script"))

; Tab / Close handlers
Tab.UseTab()
Tab.OnEvent("Change", OnTabChange)
MyGui.OnEvent("Close", (*) => ExitApp())
MyGui.Show("w370 h340")

; ================================
; Init
; ================================
if (USE_MEMORY_READING)
    InitializeWindowHandles()
UpdateWindowCount()
SetTimer(CheckCombatState, 150)
SetTimer(UpdateChatDisplay, 100)

; Set up periodic update checks
if (UPDATE_CHECK_INTERVAL > 0) {
    SetTimer(() => CheckForUpdates(false), UPDATE_CHECK_INTERVAL)
}

; ================================
; Event Handlers / Helpers / Core
; ================================
OnTabChange(*) {
    global Tab, MyGui
    currentTab := Tab.Value
    targetHeight := 340
    if (currentTab == 2)
        targetHeight := 420  ; Increased for update button
    MyGui.GetPos(&x, &y, &w, &h)
    if (h != targetHeight)
        MyGui.Move(, , , targetHeight)
}

InitializeWindowHandles() {
    global windowProcessHandles, windowCombatStates, windowChatModes, TargetExe, Window1Class, Window2Class
    global moduleBaseAddresses
    windowProcessHandles.Clear()
    windowCombatStates.Clear()
    windowChatModes.Clear()
    moduleBaseAddresses.Clear()
    for hwnd in WinGetList(TargetExe) {
        try {
            className := WinGetClass("ahk_id " . hwnd)
            if (className != Window1Class && className != Window2Class)
                continue
            pid := WinGetPID("ahk_id " . hwnd)
            hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", false, "UInt", pid, "Ptr")
            if (hProcess) {
                windowProcessHandles[hwnd] := hProcess
                windowCombatStates[hwnd] := false
                windowChatModes[hwnd] := false
                moduleBaseAddresses[hwnd] := 0x400000
            }
        } catch {
            continue
        }
    }
}

CheckCombatState() {
    global windowProcessHandles, windowCombatStates, GlobalManagerAddress, CombatModeOffset
    global Window1CombatText, Window2CombatText, CombatStatusText, Window1Class, Window2Class
    global lastCombatStatus, lastWindow1Status, lastWindow2Status
    global windowChatModes, ChatBaseOffset, ChatFinalOffset, USE_CHAT_DETECTION
    global moduleBaseAddresses

    if (!USE_MEMORY_READING)
        return false

    anyInCombat := false
    newWindow1Status := ""
    newWindow2Status := ""

    for hwnd, hProcess in windowProcessHandles.Clone() {
        if !WinExist("ahk_id " . hwnd) {
            CleanupWindow(hwnd)
            continue
        }
        try {
            className := WinGetClass("ahk_id " . hwnd)
            if (className != Window1Class && className != Window2Class)
                continue

            ; read combat flag
            managerPtrAddress := GlobalManagerAddress
            objBuf := Buffer(4)
            ok := DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", managerPtrAddress, "Ptr", objBuf, "UInt", 4, "Ptr*", &bytesRead := 0)
            if (ok && bytesRead == 4) {
                objAddr := NumGet(objBuf, 0, "UInt")
                if (objAddr) {
                    combatAddr := objAddr + CombatModeOffset
                    combatBuf := Buffer(1)
                    ok2 := DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", combatAddr, "Ptr", combatBuf, "UInt", 1, "Ptr*", &bytesRead := 0)
                    if (ok2 && bytesRead == 1) {
                        isInCombat := (NumGet(combatBuf, 0, "UChar") != 0)
                        windowCombatStates[hwnd] := isInCombat
                        if (isInCombat)
                            anyInCombat := true
                    }
                }
            }

            ; read chat state (optional)
            if (USE_CHAT_DETECTION && moduleBaseAddresses.Has(hwnd)) {
                base := moduleBaseAddresses[hwnd]
                if (base > 0) {
                    basePtrBuf := Buffer(4)
                    if (DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", base + ChatBaseOffset, "Ptr", basePtrBuf, "UInt", 4, "Ptr*", &bytesRead) && bytesRead == 4) {
                        basePtr := NumGet(basePtrBuf, 0, "UInt")
                        if (basePtr > 0x10000 && basePtr < 0xFFFF0000) {
                            finalAddr := basePtr + ChatFinalOffset
                            chatBuf := Buffer(1)
                            if (DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", finalAddr, "Ptr", chatBuf, "UInt", 1, "Ptr*", &bytesRead) && bytesRead == 1) {
                                chatVal := NumGet(chatBuf, 0, "UChar")
                                windowChatModes[hwnd] := (chatVal == 0)
                            }
                        }
                    }
                }
            }

            statusText := (windowCombatStates.Has(hwnd) && windowCombatStates[hwnd]) ? "COMBAT" : "Safe"
            if (className == Window2Class)
                newWindow1Status := "Main Window: " . statusText
            else if (className == Window1Class)
                newWindow2Status := "Sandbox Window: " . statusText
        } catch {
            continue
        }
    }

    newCombatStatus := anyInCombat ? "Combat: ACTIVE (Memory)" : "Combat: Inactive (Memory)"
    if (newCombatStatus != lastCombatStatus) {
        CombatStatusText.Text := newCombatStatus
        CombatStatusText.SetFont(anyInCombat ? "cRed" : "cGreen")
        lastCombatStatus := newCombatStatus
    }
    if (newWindow1Status != "" && newWindow1Status != lastWindow1Status) {
        Window1CombatText.Text := newWindow1Status
        Window1CombatText.SetFont(InStr(newWindow1Status, "COMBAT") ? "cRed" : "cGreen")
        lastWindow1Status := newWindow1Status
    }
    if (newWindow2Status != "" && newWindow2Status != lastWindow2Status) {
        Window2CombatText.Text := newWindow2Status
        Window2CombatText.SetFont(InStr(newWindow2Status, "COMBAT") ? "cRed" : "cGreen")
        lastWindow2Status := newWindow2Status
    }

    return anyInCombat
}

CleanupWindow(hwnd) {
    global windowProcessHandles, windowCombatStates, windowChatModes, moduleBaseAddresses
    if (windowProcessHandles.Has(hwnd)) {
        try DllCall("CloseHandle", "Ptr", windowProcessHandles[hwnd])
        windowProcessHandles.Delete(hwnd)
    }
    if (windowCombatStates.Has(hwnd)) windowCombatStates.Delete(hwnd)
    if (windowChatModes.Has(hwnd)) windowChatModes.Delete(hwnd)
    if (moduleBaseAddresses.Has(hwnd)) moduleBaseAddresses.Delete(hwnd)
    UpdateWindowCount()
}

UpdateChatDisplay() {
    global windowChatModes, ChatStatusText, TargetExe, lastChatStatus
    try {
        if WinActive(TargetExe) {
            activeHwnd := WinGetID("A")
            isInChat := windowChatModes.Has(activeHwnd) && windowChatModes[activeHwnd]
            newChatStatus := "Chat: " . (isInChat ? "ACTIVE (This Window)" : "Inactive")
            if (newChatStatus != lastChatStatus) {
                ChatStatusText.Text := newChatStatus
                ChatStatusText.SetFont(isInChat ? "cRed" : "cBlack")
                lastChatStatus := newChatStatus
            }
        }
    } catch {
    }
}

SendTheKey() {
    global isLooping, windowCombatStates, windowChatModes, TargetExe, USE_MEMORY_READING
    if (!isLooping)
        return
    if WinActive(TargetExe) {
        activeHwnd := WinGetID("A")
        if (windowChatModes.Has(activeHwnd) && windowChatModes[activeHwnd])
            return
    }
    anyInCombat := false
    if (USE_MEMORY_READING) {
        for _, state in windowCombatStates {
            if (state) {
                anyInCombat := true
                break
            }
        }
    }
    if (!anyInCombat)
        return
    for hwnd in WinGetList(TargetExe) {
        try {
            if (USE_MEMORY_READING && (!windowCombatStates.Has(hwnd) || !windowCombatStates[hwnd]))
                continue
            if (windowChatModes.Has(hwnd) && windowChatModes[hwnd])
                continue
            ControlSend("{``}", , "ahk_id " . hwnd)
            Sleep(20)
        } catch {
            continue
        }
    }
}

UpdateWindowCount() {
    global lastWindowCount, WindowCountText, TargetExe, Window1Class, Window2Class
    count := 0
    for hwnd in WinGetList(TargetExe) {
        try {
            className := WinGetClass("ahk_id " . hwnd)
            if (className == Window1Class || className == Window2Class)
                count++
        } catch {
            continue
        }
    }
    if (count != lastWindowCount) {
        WindowCountText.Text := "Windows Found: " . count
        lastWindowCount := count
    }
}

SendToInactiveWindows(key) {
    global TargetExe, Window1Class, Window2Class, windowChatModes
    activeHwnd := WinGetID("A")
    for hwnd in WinGetList(TargetExe) {
        try {
            if (hwnd == activeHwnd)
                continue
            if (key == "q" && windowChatModes.Has(hwnd) && windowChatModes[hwnd])
                continue
            className := WinGetClass("ahk_id " . hwnd)
            if (className == Window1Class || className == Window2Class)
                ControlSend(key, , "ahk_id " . hwnd)
        } catch {
            continue
        }
    }
}

SendToOtherWindow(key) {
    global TargetExe, Window1Class, Window2Class
    activeHwnd := WinGetID("A")
    for hwnd in WinGetList(TargetExe) {
        try {
            if (hwnd == activeHwnd)
                continue
            className := WinGetClass("ahk_id " . hwnd)
            if (className == Window1Class || className == Window2Class) {
                ControlSend(key, , "ahk_id " . hwnd)
                return
            }
        } catch {
            continue
        }
    }
}

StartStopHandler(*) {
    global isLooping, StatusText
    isLooping := !isLooping
    if (isLooping) {
        if (USE_MEMORY_READING)
            InitializeWindowHandles()
        UpdateWindowCount()
        SetTimer(SendTheKey, 500)
        StatusText.Text := "Status: ON"
        StatusText.SetFont("cGreen")
        SoundBeep(800, 150)
    } else {
        SetTimer(SendTheKey, 0)
        StatusText.Text := "Status: OFF"
        StatusText.SetFont("cRed")
        SoundBeep(600, 150)
    }
}

ToggleChatState(hwnd) {
    global windowChatModes
    if (windowChatModes.Has(hwnd)) {
        windowChatModes[hwnd] := !windowChatModes[hwnd]
        UpdateChatDisplay()
    }
}

ClearCombatStates() {
    global windowCombatStates
    for hwnd in windowCombatStates
        windowCombatStates[hwnd] := false
}

; ================================
; Hotkeys
; ================================
PgUp::StartStopHandler()

#HotIf WinActive(TargetExe)

~*q:: {
    global lastQPressTime, doublePressDuration, qPressInverted, windowChatModes
    activeHwnd := WinGetID("A")
    if (windowChatModes.Has(activeHwnd) && windowChatModes[activeHwnd])
        return
    now := A_TickCount
    isDouble := (now - lastQPressTime <= doublePressDuration)
    lastQPressTime := isDouble ? 0 : now
    sendToOthers := (!qPressInverted && !isDouble) || (qPressInverted && isDouble)
    if (sendToOthers)
        SendToInactiveWindows("q")
    if (isDouble)
        SoundBeep(1000, 100)
}

~*Enter:: {
    global windowChatModes, USE_CHAT_DETECTION, TargetExe
    if (!WinActive(TargetExe))
        return
    if (!USE_CHAT_DETECTION) {
        activeHwnd := WinGetID("A")
        if (!windowChatModes.Has(activeHwnd))
            windowChatModes[activeHwnd] := false
        SetTimer(() => ToggleChatState(activeHwnd), 150)
    }
}

~*Esc:: {
    global windowChatModes, windowCombatStates, TargetExe, USE_MEMORY_READING, USE_CHAT_DETECTION
    if (!WinActive(TargetExe))
        return
    activeHwnd := WinGetID("A")
    if (!USE_CHAT_DETECTION) {
        if (windowChatModes.Has(activeHwnd) && windowChatModes[activeHwnd]) {
            windowChatModes[activeHwnd] := false
            UpdateChatDisplay()
        }
    }
    anyInCombat := false
    if (USE_MEMORY_READING) {
        for _, state in windowCombatStates {
            if (state) {
                anyInCombat := true
                break
            }
        }
    }
    if (anyInCombat) {
        Sleep(50)
        for hwnd in WinGetList(TargetExe) {
            try {
                if (hwnd == activeHwnd)
                    continue
                if (windowChatModes.Has(hwnd) && windowChatModes[hwnd])
                    continue
                ControlSend("q", , "ahk_id " . hwnd)
                Sleep(30)
            } catch {
                continue
            }
        }
        SetTimer(() => ClearCombatStates(), 200)
    }
}

~*Tab:: {
    global selectedFKey, followDirection, Window1Class, Window2Class, TargetExe, FOLLOW_ENABLED
    if (!FOLLOW_ENABLED)
        return
    static lastTab := 0
    if (A_TickCount - lastTab < 100)
        return
    lastTab := A_TickCount
    try {
        activeHwnd := WinGetID("A")
        if !activeHwnd
            return
        windows := WinGetList(TargetExe)
        other := 0
        for hwnd in windows {
            className := WinGetClass("ahk_id " . hwnd)
            if ((className == Window1Class || className == Window2Class) && hwnd != activeHwnd) {
                other := hwnd
                break
            }
        }
        if (other) {
            original := activeHwnd
            curClass := WinGetClass("ahk_id " . original)
            tgtClass := WinGetClass("ahk_id " . other)
            shouldSend := (followDirection == "Switching To Sandbox (Main follows Alt)" && tgtClass == Window1Class)
                        || (followDirection != "Switching To Sandbox (Main follows Alt)" && curClass == Window1Class)
            WinActivate("ahk_id " . other)
            if (shouldSend) {
                Sleep(50)
                ControlSend("{" . selectedFKey . "}", , "ahk_id " . original)
            }
            SoundBeep(700, 50)
        }
    } catch {
    }
}

; Right Alt + Key functionality
>!a::SendToOtherWindow("a")
>!b::SendToOtherWindow("b")
>!c::SendToOtherWindow("c")
>!d::SendToOtherWindow("d")
>!e::SendToOtherWindow("e")
>!f::SendToOtherWindow("f")
>!g::SendToOtherWindow("g")
>!h::SendToOtherWindow("h")
>!i::SendToOtherWindow("i")
>!j::SendToOtherWindow("j")
>!k::SendToOtherWindow("k")
>!l::SendToOtherWindow("l")
>!m::SendToOtherWindow("m")
>!n::SendToOtherWindow("n")
>!o::SendToOtherWindow("o")
>!p::SendToOtherWindow("p")
>!q::SendToOtherWindow("q")
>!r::SendToOtherWindow("r")
>!s::SendToOtherWindow("s")
>!t::SendToOtherWindow("t")
>!u::SendToOtherWindow("u")
>!v::SendToOtherWindow("v")
>!w::SendToOtherWindow("w")
>!x::SendToOtherWindow("x")
>!y::SendToOtherWindow("y")
>!z::SendToOtherWindow("z")
>!1::SendToOtherWindow("1")
>!2::SendToOtherWindow("2")
>!3::SendToOtherWindow("3")
>!4::SendToOtherWindow("4")
>!5::SendToOtherWindow("5")
>!6::SendToOtherWindow("6")
>!7::SendToOtherWindow("7")
>!8::SendToOtherWindow("8")
>!9::SendToOtherWindow("9")
>!0::SendToOtherWindow("0")
>!Space::SendToOtherWindow("{Space}")
>!Enter::SendToOtherWindow("{Enter}")
>!Escape::SendToOtherWindow("{Escape}")
>!Tab::SendToOtherWindow("{Tab}")
>!Backspace::SendToOtherWindow("{Backspace}")
>!Delete::SendToOtherWindow("{Delete}")
>!Up::SendToOtherWindow("{Up}")
>!Down::SendToOtherWindow("{Down}")
>!Left::SendToOtherWindow("{Left}")
>!Right::SendToOtherWindow("{Right}")
>!F1::SendToOtherWindow("{F1}")
>!F2::SendToOtherWindow("{F2}")
>!F3::SendToOtherWindow("{F3}")
>!F4::SendToOtherWindow("{F4}")
>!F5::SendToOtherWindow("{F5}")
>!F6::SendToOtherWindow("{F6}")
>!F7::SendToOtherWindow("{F7}")
>!F8::SendToOtherWindow("{F8}")
>!F9::SendToOtherWindow("{F9}")
>!F10::SendToOtherWindow("{F10}")
>!F11::SendToOtherWindow("{F11}")
>!F12::SendToOtherWindow("{F12}")

#HotIf