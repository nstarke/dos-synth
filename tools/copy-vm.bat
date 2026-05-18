@echo off
setlocal

set "SRC=%~dp0.."

if "%~1"=="" (
    set "DEST_ROOT=%USERPROFILE%\86Box Vms"
) else (
    set "DEST_ROOT=%~1"
)

set "DEST=%DEST_ROOT%\dos-synth"

if not exist "%DEST_ROOT%" (
    echo Error: 86Box installation directory does not exist: %DEST_ROOT%
    exit /b 1
)

if not exist "%DEST%" mkdir "%DEST%"

copy /Y "%SRC%\86box.cfg" "%DEST%\" || exit /b 1
copy /Y "%SRC%\dos-synth.vhd" "%DEST%\" || exit /b 1
xcopy /Y /I /E "%SRC%\nvr" "%DEST%\nvr\" || exit /b 1

echo VM copied to %DEST%
endlocal
