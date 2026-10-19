@echo off
setlocal
rem Puts Thai text into the 4.7 beta client (English where the beta has no Thai yet). See README.md next to this file.
rem   Thai-Beta.bat           build the Thai text and switch the beta to it (run again after a beta update/hotfix)
rem   Thai-Beta.bat restore   back to the text language the client had before the first build
rem   Thai-Beta.bat --beta "D:\Games\<new beta folder>"   for a beta in another folder (also --live; add restore to undo)
rem Default paths: DEFAULT_BETA / DEFAULT_LIVE in thai_text.py. Close the game first.

rem find.exe by full path: from Git Bash, "find" is GNU find, which ignores the pipe and walks drive I:.
tasklist /FI "IMAGENAME eq StarRail.exe" | "%SystemRoot%\System32\find.exe" /I "StarRail.exe" >nul
if not errorlevel 1 (
    echo Close the game first.
    pause
    exit /b 1
)

python "%~dp0thai_text.py" %*
if errorlevel 1 (
    echo Failed.
    pause
    exit /b 1
)
pause
