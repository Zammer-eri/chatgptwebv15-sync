Set shell = CreateObject("WScript.Shell")
scriptPath = Replace(WScript.ScriptFullName, "launch-hidden.vbs", "tray_app.py")
shell.Run "pythonw """ & scriptPath & """", 0
