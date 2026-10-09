@echo off
rem Fallback: runs the Stacks What-If demo in its own window (files print in the terminal).
rem The main way is VS Code: open the stacks-whatif-demo folder and press Ctrl + `.
where wt.exe >nul 2>nul
if %errorlevel%==0 (
  start "" wt.exe -w new nt --title "Stacks What-If demo" -d "%~dp0." pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Demo.ps1" %*
) else (
  start "Stacks What-If demo" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Demo.ps1" %*
)
