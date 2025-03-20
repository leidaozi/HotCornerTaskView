Step-by-Step Guide to Run this AHK Script at Startup:

Compile the AHK Script:

   	Open the AutoHotkey app (v2.0.19 U64).
    Right-click on your .ahk script and choose Compile Script (or use the AHK compiler directly).
    Click Browse for the source option and choose your .ahk file.
    For the Icon, you can choose any .ico file you want.
    For the Base bin, select v2.0.19 U64 AutoHotKey64.exe.
    After setting this up, just press Convert.
    After this, you will have a .exe version of your script, saved in the same folder as your original .ahk file.

Create a Shortcut of the Executable:

    Right-click on the .exe file and select Create Shortcut.
    The shortcut will be created in the same folder as the .exe file, but you can move it if needed.

Open the Run Dialog:

    Press Win + R (or just press the Windows key and R) to open the Run dialog.
    Type shell:startup in the Run box and press Enter. This will open the Startup folder.

Move the Shortcut to the Startup Folder:

  	Now that you have the Startup folder open, move the shortcut of the compiled .exe file into this folder.
    Simply drag the shortcut into the Startup folder window that just opened.
    This will ensure that the script will run automatically when the computer starts up.

Enable the Script in Task Manager (If Needed):

    Open Task Manager (press Ctrl + Shift + Esc or right-click on the taskbar and select Task Manager).
    Go to the Startup tab in Task Manager.
    Ensure that the script is enabled in the list (you should see your script listed there).
    If it's disabled, simply right-click on the script in the list and select Enable.
