@echo off
setlocal

set "SRC=%~dp0.."
set "DEST_ROOT=%USERPROFILE%\86Box Vms"
set "VM_NAME=dos-synth"

:parse_args
if "%~1"=="" goto done_args
if /I "%~1"=="--name" (
    set "VM_NAME=%~2"
    shift
    shift
    goto parse_args
)
set "DEST_ROOT=%~1"
shift
goto parse_args
:done_args

set "DEST=%DEST_ROOT%\%VM_NAME%"

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
