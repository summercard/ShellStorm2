@echo off
chcp 65001 >nul
cd /d "I:\工作项目\shellstrom2\ShellStorm2"
del /q "I:\工作项目\shellstrom2\ShellStorm2\tests\rec\rec_progress.log" 2>nul
if exist "I:\工作项目\shellstrom2\ShellStorm2\tests\rec\out" rd /s /q "I:\工作项目\shellstrom2\ShellStorm2\tests\rec\out"
mkdir "I:\工作项目\shellstrom2\ShellStorm2\tests\rec\out"
"I:\下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "I:\工作项目\shellstrom2\ShellStorm2" res://tests/rec/record_elite.tscn --resolution 1280x720 > "I:\工作项目\shellstrom2\ShellStorm2\tests\rec\godot_out.log" 2>&1
echo EXIT=%ERRORLEVEL%
