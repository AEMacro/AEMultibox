AE Multibox - AutoHotkey Script for Ashen Empires
Overview

AE Multibox is a powerful AutoHotkey (AHK) v2.0 script designed to enhance the multi-boxing experience for the game Ashen Empires. It provides tools for synchronized actions, combat assistance, and streamlined window management when playing with multiple characters simultaneously.

The script's core functionality relies on reading the game's memory to accurately detect combat status and chat activity, allowing for more reliable automation than simple pixel or color detection methods. It is built to be robust, user-friendly, and configurable through a simple GUI.

Features

    Memory-Based Combat Detection: The script reads memory to determine if any of your game instances are in combat, ensuring that assistance actions are only performed when needed.

    Automated Key Sending: When combat is detected, the script can automatically send a designated key (~) to all game windows that are in combat.

    Smart Chat Detection: The script can detect when you are typing in the chat box and will pause actions for that specific window to prevent interference.

    Follow Feature: Easily make one character follow another with a press of the Tab key. The follow key and behavior are customizable.

    Multi-Window Key Broadcasting:

        Q-Key Toggling: A single press of 'Q' sends the key to the active window, while a quick double-press sends it to all game windows. This can be inverted in the settings.

        Right-Alt Passthrough: Hold Right Alt plus almost any key to send that keystroke to the other game window without switching focus.

    User-Friendly GUI: A clean graphical interface to view status and change settings.

    Admin Privilege Handling: Prompts for administrator rights on startup, which is recommended for stable memory reading. It can fall back to a less reliable mode if admin rights are not granted.

Requirements

    AutoHotkey: Version 2.0 or higher (if using the .ahk script).

    Operating System: Windows.

    Game: Ashen Empires (AshenEmpires.exe).

    Administrator Privileges: Recommended for full functionality (memory reading).

Installation & Setup

    Download the Tool:

        Go to the Releases page of this repository. <!-- Replace with your repo URL -->

        Download the latest version. You can choose either the compiled .exe file or the .ahk script.

    For the .ahk script: If you don't have it, download and install AutoHotkey v2.0 from the official AutoHotkey website.

    Run the Tool:

        If you downloaded the .exe file, you can run it directly.

        If you downloaded the .ahk file, simply double-click it to run.

        The script will request to run as administrator. It is highly recommended to click "Yes".

How to Use
Main Controls

    PgUp: Starts or stops the main combat-assist loop. The GUI will show the current status (ON/OFF).

    Tab: Switches focus between your Ashen Empires windows. If the "Follow Feature" is enabled, this will also trigger the follow key press.

    Q Key:

        Single Press: Sends 'q' to the currently active window.

        Double Press: Sends 'q' to all game windows.

        This behavior can be inverted in the settings.

    Right Alt + [Key]: Sends the specified key to the other game window. For example, holding Right Alt and pressing 1 will send the 1 key to your inactive game client.

    Enter: Manually toggles chat mode for the active window. When in chat mode, combat assistance is paused for that window.

    Esc: Exits chat mode and clears the combat state for all windows.

The GUI

The application window provides three tabs:

    Main: Shows the current status of the script, the number of game windows found, and the combat/chat status of each window.

    Settings: Allows you to customize the script's behavior:

        Follow Key: Choose which F-key (F1-F12) is used for the follow command.

        Send Key When: Configure when the follow key is sent (e.g., when switching to your sandboxed window or from it).

        Q Key Behavior: Invert the single/double press logic.

    Info: Displays a summary of hotkeys and the script version.

License

This project is open-source. Feel free to use, modify, and distribute it as you see fi
