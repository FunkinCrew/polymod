@echo off
setlocal

set "ROOT=%~dp0"
pushd "%ROOT%" >nul
if errorlevel 1 (
  echo ERROR: Could not open the Polymod repository directory.
  exit /b 1
)

where haxe >nul 2>nul
if errorlevel 1 goto missing_haxe

where haxelib >nul 2>nul
if errorlevel 1 goto missing_haxelib

for /f "tokens=1-3 delims=.-" %%A in ('haxe --version') do (
  set "HAXE_MAJOR=%%A"
  set "HAXE_MINOR=%%B"
  set "HAXE_PATCH=%%C"
)
if not defined HAXE_MAJOR goto invalid_haxe_version
if not defined HAXE_MINOR goto invalid_haxe_version
if not defined HAXE_PATCH goto invalid_haxe_version
if %HAXE_MAJOR% LSS 4 goto haxe_too_old
if %HAXE_MAJOR% GTR 4 goto check_dependencies_start
if %HAXE_MINOR% LSS 3 goto haxe_too_old
if %HAXE_MINOR% GTR 3 goto check_dependencies_start
if %HAXE_PATCH% LSS 7 goto haxe_too_old

:check_dependencies_start
call :check_dependencies
if errorlevel 1 goto setup_failed
if not defined NEEDS_DEPENDENCIES (
  echo All required libraries are available through Haxelib; skipping downloads.
  goto run_tests
)

echo One or more required Haxelib libraries are missing or unavailable.
echo Installing HMM and preparing the minimal test dependencies...
call haxelib --global path hmm >nul 2>nul
if errorlevel 1 (
  echo Installing HMM...
  call haxelib --global install hmm
  if errorlevel 1 goto setup_failed
)

pushd "tests" >nul
if errorlevel 1 goto setup_failed
call haxelib run hmm install --quiet
if errorlevel 1 goto setup_failed_pop
popd

call :check_dependencies
if errorlevel 1 goto setup_failed
if defined NEEDS_DEPENDENCIES goto dependencies_unavailable

:run_tests
echo Running Polymod HScript regression tests...
call haxe tests\run.hxml
if errorlevel 1 goto tests_failed

echo.
echo All Polymod tests passed.
echo.
pause
popd
exit /b 0

:setup_failed_pop
popd
:setup_failed
echo.
echo ERROR: Dependency setup failed. Check the Haxe/Haxelib output above.
echo Confirm your internet connection and that Haxe 4.3.7 or newer is installed.
echo.
pause
popd
exit /b 1

:dependencies_unavailable
echo.
echo ERROR: Some required libraries are still unavailable after setup.
echo Check the Haxelib output above, then run test.bat again.
echo.
pause
popd
exit /b 1

:tests_failed
echo.
echo ERROR: The test run failed. Review the test summary and errors above.
echo.
pause
popd
exit /b 1

:missing_haxe
echo ERROR: Haxe was not found on PATH.
echo Install Haxe 4.3.7 or newer from https://haxe.org/download/
echo Then reopen this window and verify that "haxe --version" works before retrying.
echo.
pause
popd
exit /b 1

:missing_haxelib
echo ERROR: Haxelib was not found on PATH.
echo Reinstall Haxe 4.3.7 or newer from https://haxe.org/download/
echo Ensure Haxelib is on PATH, reopen this window, and retry.
echo.
pause
popd
exit /b 1

:haxe_too_old
echo ERROR: Haxe 4.3.7 or newer is required. Detected Haxe %HAXE_MAJOR%.%HAXE_MINOR%.%HAXE_PATCH%.
echo Update Haxe from https://haxe.org/download/, reopen this window, and retry.
echo.
pause
popd
exit /b 1

:invalid_haxe_version
echo ERROR: Could not read the Haxe version. Run "haxe --version" to check your installation.
echo Install Haxe 4.3.7 or newer from https://haxe.org/download/, then retry.
echo.
pause
popd
exit /b 1

:check_dependencies
set "NEEDS_DEPENDENCIES="
pushd "tests" >nul
if errorlevel 1 exit /b 1
call :check_library polymod
call :check_library jsonpath
call :check_library jsonpatch
call :check_library thx.semver
call :check_library thx.core
popd
exit /b 0

:check_library
call haxelib path %~1 >nul 2>nul
if errorlevel 1 (
  echo Missing or unavailable library: %~1
  set "NEEDS_DEPENDENCIES=1"
)
exit /b 0
