@if "%SCM_TRACE_LEVEL%" NEQ "4" @echo off

:: ----------------------
:: KUDU Deployment Script
:: Version: 1.0.15
:: ----------------------

:: Prerequisites
:: -------------

:: Verify node.js installed
where node 2>nul >nul
IF %ERRORLEVEL% NEQ 0 (
  echo Missing node.js executable, please install node.js, if already installed make sure it can be reached from current environment.
  goto error
)

:: Setup
:: -----

setlocal enabledelayedexpansion

SET ARTIFACTS=%~dp0%..\artifacts

IF NOT DEFINED DEPLOYMENT_SOURCE (
  SET DEPLOYMENT_SOURCE=%~dp0%.
)

IF NOT DEFINED DEPLOYMENT_TARGET (
  SET DEPLOYMENT_TARGET=%ARTIFACTS%\wwwroot
)

IF NOT DEFINED NEXT_MANIFEST_PATH (
  SET NEXT_MANIFEST_PATH=%ARTIFACTS%\manifest

  IF NOT DEFINED PREVIOUS_MANIFEST_PATH (
    SET PREVIOUS_MANIFEST_PATH=%ARTIFACTS%\manifest
  )
)

IF NOT DEFINED KUDU_SYNC_CMD (
  :: Install kudu sync
  echo Installing Kudu Sync
  call npm install kudusync -g --silent
  IF !ERRORLEVEL! NEQ 0 goto error

  :: Locally just running "kuduSync" would also work
  SET KUDU_SYNC_CMD=%appdata%\npm\kuduSync.cmd
)

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Deployment
:: ----------

:Deployment
echo Handling Vue webpack deployment.

:: 1. Install npm dependencies for app and build
echo 1. Installing npm packages for app and build in %~dp0% 
call :ExecuteCmd npm install
IF !ERRORLEVEL! NEQ 0 goto error

:: 2. Build
echo 2. Building app 
call :ExecuteCmd npm run build
IF !ERRORLEVEL! NEQ 0 goto error

:: 3. KuduSync dist directory files
IF /I "%IN_PLACE_DEPLOYMENT%" NEQ "1" (
  echo 3. Kudu syncing built app from dist folder to deployment target
  call :ExecuteCmd "%KUDU_SYNC_CMD%" -v 50 -f "%DEPLOYMENT_SOURCE%\dist" -t "%DEPLOYMENT_TARGET%" -n "%NEXT_MANIFEST_PATH%" -p "%PREVIOUS_MANIFEST_PATH%" -i ".git;.hg;.deployment;deploy.cmd"
  IF !ERRORLEVEL! NEQ 0 goto error
)

:: 4. Purge CDN cache of all caches files
:: Requires an application to be setup in the Azure Active Directory on the same tenant, 
:: with a client id and key/secret, and permissions to the Azure CDN Endpoint (CDN Endpoint Contributor)
IF NOT DEFINED CLIENT_ID ( 
  echo 4. Skipping Azure CDN cache purge. App Setting "CLIENT_ID" was not found. Potentially this is a local test deployment run.
  goto end 
)
IF NOT DEFINED CLIENT_SECRET ( 
  echo 4. Skipping Azure CDN cache purge. App Setting "CLIENT_SECRET" was not found. Potentially this is a local test deployment run.
  goto end 
)

echo 4. Purging CDN of all cached files
SET ARM_CLIENT_CMD="%DEPLOYMENT_SOURCE%\build\armclient\ARMClient.exe"

SET TENANT_ID="979c7556-2382-40a9-a730-7af1e4233b55"
::SET CLIENT_ID="comes-from-app-settings"
::SET CLIENT_SECRET="comes-from-app-settings"

call :ExecuteCmd "%ARM_CLIENT_CMD%" spn %TENANT_ID% %CLIENT_ID% %CLIENT_SECRET%
IF !ERRORLEVEL! NEQ 0 goto error

SET SUBSCRIPTION_ID="68667b16-e134-4e46-a29b-6f8ae4d90f50"
SET RESOURCE_GROUP="blip"
SET CDN_PROFILE="blip"
SET CDN_ENDPOINT="blip"

call :ExecuteCmd "%ARM_CLIENT_CMD%" post https://management.azure.com/subscriptions/%SUBSCRIPTION_ID%/resourceGroups/%RESOURCE_GROUP%/providers/Microsoft.Cdn/profiles/%CDN_PROFILE%/endpoints/%CDN_ENDPOINT%/purge?api-version=2016-10-02 "{ 'contentPaths': ['/*'] }"
IF !ERRORLEVEL! NEQ 0 goto error

call :ExecuteCmd "%ARM_CLIENT_CMD%" clearcache

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
goto end

:: Execute command routine that will echo out when error
:ExecuteCmd
setlocal
set _CMD_=%*
call %_CMD_%
if "%ERRORLEVEL%" NEQ "0" echo Failed exitCode=%ERRORLEVEL%, command=%_CMD_%
exit /b %ERRORLEVEL%

:error
endlocal
echo An error has occurred during web site deployment.
call :exitSetErrorLevel
call :exitFromFunction 2>nul

:exitSetErrorLevel
exit /b 1

:exitFromFunction
()

:end
endlocal
echo Finished successfully.
