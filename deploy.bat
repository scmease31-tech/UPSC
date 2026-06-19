@echo off
set PATH=C:\flutter\bin;%PATH%
cd /d "c:\Users\sohil.d\Downloads\Hehe\new game"

echo === Deploying to GitHub Pages ===

set TEMP_DIR=%TEMP%\upsc-ghpages
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"

xcopy "build\web\*" "%TEMP_DIR%\" /s /e /q /y

cd /d "%TEMP_DIR%"
git init
git checkout -b gh-pages
git add -A
git commit -m "Deploy with web compatibility fixes"
git remote add origin https://github.com/sohildobariya31-blip/UPSC.git
git push origin gh-pages --force

echo === Deploy complete ===
