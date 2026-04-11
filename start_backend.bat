@echo off
setlocal

set "ENV_NAME=%APP_CONDA_ENV%"
if "%ENV_NAME%"=="" set "ENV_NAME=any-auto-register"
set "HOST=%HOST%"
if "%HOST%"=="" set "HOST=0.0.0.0"
set "PORT=%PORT%"
if "%PORT%"=="" set "PORT=8000"
set "RESTART_EXISTING=%RESTART_EXISTING%"
if "%RESTART_EXISTING%"=="" set "RESTART_EXISTING=1"

where conda >nul 2>nul
if errorlevel 1 (
  echo [ERROR] conda command not found. Please install Miniconda/Anaconda first.
  exit /b 1
)

cd /d "%~dp0"
echo [INFO] Project root: %CD%
echo [INFO] Conda env: %ENV_NAME%
echo [INFO] Backend URL: http://localhost:%PORT%
echo [INFO] Press Ctrl+C to stop

if "%RESTART_EXISTING%"=="1" (
  echo [INFO] Cleaning old backend / solver processes first
  powershell -ExecutionPolicy Bypass -File "%~dp0stop_backend.ps1" -BackendPort %PORT% -SolverPort 8889 -FullStop 0
)

for /f "usebackq delims=" %%i in (`conda run --no-capture-output -n %ENV_NAME% python -c "import sys; print(sys.executable)"`) do set "PYTHON_EXE=%%i"

if not exist "%PYTHON_EXE%" (
  echo [ERROR] Failed to resolve python executable for conda env "%ENV_NAME%".
  exit /b 1
)

set "HOST=%HOST%"
set "PORT=%PORT%"
echo [INFO] Python: %PYTHON_EXE%
"%PYTHON_EXE%" main.py
