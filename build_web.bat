@echo off
set PATH=C:\flutter\bin;%PATH%
cd /d "c:\Users\sohil.d\Downloads\Hehe\new game"
echo Starting build...
flutter build web --release --base-href "/UPSC/"
echo Build exit code: %ERRORLEVEL%
