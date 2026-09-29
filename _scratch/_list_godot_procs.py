import subprocess

ps = (
    "Get-CimInstance Win32_Process -Filter \"Name like 'Godot%'\" | "
    "ForEach-Object { \"PID=$($_.ProcessId) MB=$([math]::Round($_.WorkingSetSize/1MB)) :: $($_.CommandLine)\" }"
)
r = subprocess.run(
    ["powershell", "-NoProfile", "-NonInteractive", "-Command", ps],
    capture_output=True, text=True, encoding="utf-8", errors="replace",
)
print("RC", r.returncode)
print(r.stdout)
print("ERR", r.stderr[:2000])
