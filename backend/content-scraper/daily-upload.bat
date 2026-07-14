@echo off
REM ============================================================================
REM  UPSC Daily Upload - double-click this file
REM
REM  Put the day's PDFs in your Downloads folder (named as usual, e.g.
REM  "Daily Vocabulary 14-07-2026.pdf", "IE Delhi 14-07-2026.pdf",
REM  "TH Delhi 14-07-2026.pdf", "All English Editorials 14-7.pdf"),
REM  then double-click this file. It finds them, uploads the content, and
REM  shows a summary.
REM
REM  To scan a different folder, run from a terminal:
REM     daily-upload.bat --dir "D:\path\to\pdfs"
REM  To preview without uploading:
REM     daily-upload.bat --dry-run
REM ============================================================================

setlocal

REM Auto-detect the newest Firebase Admin key. Searches, in order: your Downloads
REM folder, the project root, and this scripts folder (keys are gitignored, so a
REM copy kept in the project is safe from being committed).
if not defined GOOGLE_APPLICATION_CREDENTIALS call :findkey "%USERPROFILE%\Downloads"
if not defined GOOGLE_APPLICATION_CREDENTIALS call :findkey "%~dp0..\.."
if not defined GOOGLE_APPLICATION_CREDENTIALS call :findkey "%~dp0."

if not defined GOOGLE_APPLICATION_CREDENTIALS (
  echo [ERROR] No Firebase Admin service-account JSON found in Downloads or the project folder.
  echo Put your Firebase Admin JSON ^(upsc-app-*-firebase-adminsdk-*.json^) in your
  echo Downloads folder, or set GOOGLE_APPLICATION_CREDENTIALS to its path, then retry.
  echo.
  pause
  exit /b 1
)

echo Using credentials: %GOOGLE_APPLICATION_CREDENTIALS%
echo.

node "%~dp0daily-ingest.js" %*

echo.
echo ----------------------------------------------------------------
echo Finished. You can close this window.
pause
endlocal
exit /b 0

:findkey
REM %~1 = directory to search for a Firebase Admin key (newest first).
for /f "delims=" %%F in ('dir /b /a-d /o-d "%~1\*firebase-adminsdk*.json" 2^>nul') do (
  if not defined GOOGLE_APPLICATION_CREDENTIALS set "GOOGLE_APPLICATION_CREDENTIALS=%~1\%%F"
)
goto :eof
