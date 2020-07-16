@echo off
setlocal enableextensions enabledelayedexpansion

:: 8/12/2019
:: DP072885 - CMURPHY
:: branching script for svn maintenance operations
:: create feature branch from trunk, and fixes branch from release branch

:: revision A [8/12/2019]: Initial Release
:: revision B [9/24/2019]: Support eCOS and inMotion
:: revision C [10/14/2019]: Support team names

:: check command line
set argC=0
for %%x in (%*) do Set /A argC+=1
if not %argC%==8 (
    echo Creates feature/fixes branches as part of the Motion SDLC process immediately following eCOS release.
    echo Usage: make_new_branches project current_release_branch current_release_artifact branch artifact svn_dir quiet team_name
    echo * project: this is the project to maintain - supports eCOS, inMotion
    echo * current_release_branch: this is the current release branch in QA - will make a fixes branch from here
    echo * current_release_artifact: this is the artifact for SVN maintenance on the aforementioned release
    echo * branch: this is the name of the feature branch to create - will branch this from trunk
    echo * artifact: this is the teamforge SVN maintenance artifact to commit changes against for the feature branch
    echo * svn_dir: this is your svn directory for projects to check out to. Will check out the new branches here to update externals
    echo * quiet: quiet mode. Will not prompt for confirmation. Very spooky!
    echo "* team_name: will qualify all new branches with this subdirectory (e.g. FightingMongooses -> branches\FightingMongooses\9.11.1)"
    echo.
    echo Example scenario: 
    echo eCOS 9.8.2 is currently in QA. We want to create a 9.9.1 PRE branch.
    echo artf80794 is the 9.8.2 SVN Maintenance artifact, and 
    echo artf80747 is the 9.9.1 SVN Maintenance artifact.
    echo We keep our code in C:\DATA\Projects\svn, and I don't like being spooked, 
    echo so we set quiet mode to 0.
    echo.
    echo Example: make_new_branches eCOS 9.8.2 artf80794 9.9.1_OSS_PRE artf80747 C:\DATA\Projects\svn 0 FightingMongooses
    echo.
    GOTO END
)

:::: script parameters ::::

:: this is the project to maintain (eCOS or inMotion)
SET project=%1

:: check the specified project to make sure its supported
IF "%project%" == "eCOS" (
    GOTO PROJECT_OK
)
IF "%project%" == "inMotion" (
    GOTO PROJECT_OK
)
echo "Unsupported project '%project%' - only supports eCOS or inMotion"
GOTO :EOF
:PROJECT_OK

:: this is the current release branch in QA - will make a fixes branch from here
::SET current_release_branch=9.8.2
SET current_release_branch=%2
:: this is the artifact for SVN maintenance on the aforementioned release
::SET current_release_artifact=artf80794
SET current_release_artifact=%3

:: this is the name of the feature branch to create - will branch this from trunk
::SET branch=9.9.1_OSS_PRE
SET branch=%4
:: this is the teamforge artifact to commit changes against
::SET artifact=artf80747
SET artifact=%5
:: this is your svn directory for projects to check out to
::SET svn_dir=C:\DATA\Projects\svn
SET svn_dir=%6

:: quiet mode
::SET quiet=0
SET quiet=%7

:: this is your team name (branches are created in this subdirectory on the server)
::SET team_name=FightingMongooses
SET team_name=%8

:: empty team name becomes "cwd"
IF "%team_name%" == "" (
    SET team_name=.
)

:: dry run, don't actually do anything if ==1
SET dry_run=0

:::: script-level variables ::::

:: no release branch detected
SET no_release=0

:: introduction

echo Motion SVN  Mantenance script
echo Version 1.0.C, 2019-10-14
echo.
echo * Create the feature branches for the next release from trunk. (eCOS,Framework,CommonApps,Props)
echo * Create the fixes branches for the current release from the current release branch. (eCOS,Framework,CommonApps,Props)
echo * If the branches already exist, then they will be skipped.
echo.
echo * Supports eCOS and inMotion
echo.
echo Here is the current environment:
echo QA BRANCH:     [%current_release_branch%] - this is the current release branch in QA - will make a fixes branch from here
echo QA ARTIFACT:   [%current_release_artifact%] - this is the artifact for SVN maintenance on the aforementioned release
echo TARGET BRANCH: [%branch%] - this is the name of the feature branch to create - will branch this from trunk
echo TF ARTIFACT:   [%artifact%] - this is the teamforge artifact to commit changes against
echo SVN DIR:       [%svn_dir%] - this is your svn directory for projects to check out to
echo PROJECT:       [%project%] - this is the project to work with
echo TEAM NAME:     [%team_name%] - this is your team name (subdir in svn repo)

:: prompt the user for confirmation if not in quiet mode
if %quiet% == 0 (
    set AREYOUSURE="N"
    set /P AREYOUSURE="Continue (Y/[N])? "
    IF /I NOT "!AREYOUSURE!" EQU "Y" GOTO END
)

:: check if the release branch exists yet
svn log https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%project%/branches/%current_release_branch% > nul
if errorlevel 1 (
    SET no_release=1
)

:: if no release yet, and not quiet, ask user for confirmation
if %quiet% == 0 (
if %no_release% == 1 (
    echo The %current_release_branch% release branch has not yet been created. Are you sure you want to continue?
    echo Feature branches will still be created, but the previous release has probably not been merged to trunk
    echo yet, and you will have to do it manually.
    echo Also, fixes branches will be skipped.

    set AREYOUSURE="N"
    set /P AREYOUSURE="Continue (Y/[N])? "
    IF /I NOT "!AREYOUSURE!" EQU "Y" GOTO END
)
)

if %dry_run% == 0 (
echo.
echo Verifying that checkout directories are clear. If not, they will be deleted first.
echo.
if %quiet% == 0 (
if exist %svn_dir%\%project%_%branch% (
    set AREYOUSURE="N"
    set /P AREYOUSURE="%svn_dir%\%project%_%branch% exists. It will be cleared for checkout. Ok (Y/[N])? "
    IF /I NOT "!AREYOUSURE!" EQU "Y" GOTO END
)
if exist %svn_dir%\CommonApps_%project%%branch% (
    set AREYOUSURE="N"
    set /P AREYOUSURE="%svn_dir%\CommonApps_%project%%branch% exists. It will be cleared for checkout. Ok (Y/[N])? "
    IF /I NOT "!AREYOUSURE!" EQU "Y" GOTO END
)
if exist %svn_dir%\Framework_%project%%branch% (
    set AREYOUSURE="N"
    set /P AREYOUSURE="%svn_dir%\Framework_%project%%branch% exists. It will be cleared for checkout. Ok (Y/[N])? "
    IF /I NOT "!AREYOUSURE!" EQU "Y" GOTO END
)
if exist %svn_dir%\props_%project%%branch% (
    set AREYOUSURE="N"
    set /P AREYOUSURE="%svn_dir%\props_%project%%branch% exists. It will be cleared for checkout. Ok (Y/[N])? "
    IF /I NOT "!AREYOUSURE!" EQU "Y" GOTO END
)
)

rmdir /Q/S %svn_dir%\%project%_%branch% 2> nul
rmdir /Q/S %svn_dir%\CommonApps_%project%%branch% 2> nul
rmdir /Q/S %svn_dir%\Framework_%project%%branch% 2> nul
rmdir /Q/S %svn_dir%\props_%project%%branch% 2> nul
)

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::CREATE NEW PRE BRANCHES:::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

echo.
echo Creating feature branches for %branch% under SVN maintenance artifact %artifact%
echo.
if %quiet% == 0 (timeout 5)
CALL :BRANCH_PROJ %project%           %team_name%/%branch% trunk %artifact%
:: format branch name like: eCOS9.10.1
CALL :BRANCH_PROJ CommonApps %team_name%/%project%%branch% trunk %artifact%
CALL :BRANCH_PROJ Framework  %team_name%/%project%%branch% trunk %artifact%
CALL :BRANCH_PROJ props      %team_name%/%project%%branch% trunk %artifact%


echo.
echo Checking out the new projects to %svn_dir%\%project%%branch% (+ CA, FW, and props)...
echo Please wait, this could take a minute...
echo.
if %quiet% == 0 (timeout 5)
:: checkout the full projects (could do a depth empty, but we need to merge anyway)
CALL :CO_BRANCH %project%/branches/%team_name%/%branch%/%project% %svn_dir%\%project%_%teamname%%branch%
CALL :CO_BRANCH CommonApps/branches/%team_name%/%project%%branch%/CommonApps %svn_dir%\CommonApps_%teamname%%project%%branch%
CALL :CO_BRANCH Framework/branches/%team_name%/%project%%branch%/Framework %svn_dir%\Framework_%teamname%%project%%branch%
CALL :CO_BRANCH props/branches/%team_name%/%project%%branch%/props %svn_dir%\props_%teamname%%project%%branch%


echo.
echo Merging release branches into feature branches...
echo If a merge failure occurs (unexpected), you can terminate the merge conflict resolution with q.
echo That will leave your working copy in a conflicted state, which you can resolve later, then commit using %artifact%.
echo.
if %quiet% == 0 (timeout 5)
CALL :MERGE_PROJ %project%      %current_release_branch%          %team_name%/%branch% %artifact% %svn_dir%\%project%_%teamname%%branch%
:: always merge from eCOSX.X.X release branches, since those are the only ones that exist
CALL :MERGE_PROJ CommonApps eCOS%current_release_branch% %team_name%/%project%%branch% %artifact% %svn_dir%\CommonApps_%teamname%%project%%branch%
CALL :MERGE_PROJ Framework  eCOS%current_release_branch% %team_name%/%project%%branch% %artifact% %svn_dir%\Framework_%teamname%%project%%branch%
CALL :MERGE_PROJ props      eCOS%current_release_branch% %team_name%/%project%%branch% %artifact% %svn_dir%\props_%teamname%%project%%branch%


echo.
echo Updating the externals on %project%\%branch%...
echo.
if %quiet% == 0 (timeout 5)
CALL :SET_EXTERNAL %project% %branch% %artifact% %team_name%

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::CREATE FIXES BRANCHES::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

if %no_release% == 1 (
    echo The %current_release_branch% release branch has not yet been created. Skipping fixes branch creation.
    GOTO END
)

:: prompt the user for confirmation if not in quiet mode
if %quiet% == 0 (
    echo.
    echo Ready to create fixes branches for %current_release_branch%. Skip this if you do not want fixes branches.
    echo.

    set AREYOUSURE="N"
    set /P AREYOUSURE="Continue (Y/[N])? "
    IF /I NOT "!AREYOUSURE!" EQU "Y" GOTO END
)

echo.
echo Creating fixes branches for %current_release_branch% under SVN maintenance artifact %current_release_artifact%
echo.
if %quiet% == 0 (timeout 5)
CALL :BRANCH_PROJ %project%           %team_name%/%current_release_branch%_fixes     %current_release_branch% %current_release_artifact% %team_name%
CALL :BRANCH_PROJ CommonApps %team_name%/%project%%current_release_branch%_fixes eCOS%current_release_branch% %current_release_artifact% %team_name%
CALL :BRANCH_PROJ Framework  %team_name%/%project%%current_release_branch%_fixes eCOS%current_release_branch% %current_release_artifact% %team_name%
CALL :BRANCH_PROJ props      %team_name%/%project%%current_release_branch%_fixes eCOS%current_release_branch% %current_release_artifact% %team_name%


echo.
echo Checking out the new project to %svn_dir%\%project%_%current_release_branch%_fixes...
echo.
if %quiet% == 0 (timeout 5)
:: checkout the full project (could do a depth empty, but we'll probably need it for development anyway)
CALL :CO_BRANCH %project%/branches/%current_release_branch%_fixes/%project% %svn_dir%\%project%_%current_release_branch%_fixes


echo.
echo Updating the externals on %project%\%current_release_branch%_fixes...
echo.
if %quiet% == 0 (timeout 5)
CALL :SET_EXTERNAL %project% %current_release_branch%_fixes %current_release_artifact% %team_name%

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:: end of main
:END 
echo.
echo Done! 
echo If successful, your new branch is available at %svn_dir%\%project%_%branch%
echo and your fixes branch is available at %svn_dir%\%project%\%current_release_branch%_fixes
endlocal
GOTO :EOF 









:: END OF MAIN ::
:: FUNCTIONS FOLLOW ::









::func branch_proj(bp_project,bp_branch,bp_artifact)
::create a branch of a project remotely
:BRANCH_PROJ
setlocal

:: bp_project - eCOS, CommonApps, Framework, props
SET bp_project=%1
:: bp_branch - 9.8.2, eCOS9.8.2
SET bp_branch_to=%2
:: bp_branch_from - trunk
SET bp_branch_from=%3
:: bp_artifact - artf12345
SET bp_artifact=%4

if NOT "%bp_branch_from%" == "trunk" (
    SET bp_branch_from=branches/%bp_branch_from%
)

echo Branching %bp_project%/branches/%bp_branch_to%
svn log https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%bp_project%/branches/%bp_branch_to% > nul 2>&1
if errorlevel 1 (
    if %dry_run%==1 (
        echo svn copy --parents https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%bp_project%/%bp_branch_from% ^
            https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%bp_project%/branches/%bp_branch_to% ^
        -m "[%bp_artifact%] : Creating the %bp_branch_to% feature branch from the HEAD revision of %bp_project% %bp_branch_from%"
    ) else (
        svn copy --parents https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%bp_project%/%bp_branch_from% ^
            https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%bp_project%/branches/%bp_branch_to% ^
        -m "[%bp_artifact%] : Creating the %bp_branch_to% feature branch from the HEAD revision of %bp_project% %bp_branch_from%"
        echo %bp_project%/branches/%bp_branch_to% created.
    )

) else (
    echo %bp_project%/branches/%bp_branch_to% exists.
)
endlocal
exit /b



::func merge_proj(project,from,to,artifact)
::merge the difference between two branches into a working copy and commit
:MERGE_PROJ
setlocal

:: [artf80747] : Merging eCOS 9.8.2 at the HEAD revision into the eCOS 9.9.1_OSS_PRE feature branch.
:: svn merge sourceURL1[@N] sourceURL2[@M] [WCPATH]

:: mp_project - eCOS, CommonApps, Framework, props
SET mp_project=%1
:: mp_branch_from - 9.8.2
SET mp_branch_from=%2
:: mp_branch - 9.9.1_OSS_PRE
SET mp_branch_to=%3
:: mp_artifact - artf12345
SET mp_artifact=%4
:: mp_dir
SET mp_dir=%5

echo merging WD %mp_dir% with %mp_project%/branches/%mp_branch_from%/%mp_project%

if %dry_run%==1 (
    echo cd %mp_dir%
    echo svn merge https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%mp_project%/branches/%mp_branch_from%/%mp_project% .
    echo svn commit . -m "[%mp_artifact%] : Merging %mp_project% %mp_branch_from% at the HEAD revision into the %mp_project% %mp_branch_to% feature branch."
) else (
    cd %mp_dir%
    svn merge https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%mp_project%/branches/%mp_branch_from%/%mp_project% .
    svn commit . -m "[%mp_artifact%] : Merging %mp_project% %mp_branch_from% at the HEAD revision into the %mp_project% %mp_branch_to% feature branch."
)

endlocal
exit /b



::func set_external(project,branch,artifact)
::sets the externals on a project
:SET_EXTERNAL
setlocal

:: se_project - eCOS, CommonApps, Framework, props
SET se_project=%1
:: se_branch - 9.9.1_OSS_PRE
SET se_branch=%2
:: se_artifact - artf12345
SET se_artifact=%3
:: team_name - FightingMongooses
SET team_name=%4


:: svn propset svn:externals "LocalPath https://svnserver/svn/myproject/tags/1.00/DISTRIBUZIONE89" wc
echo Setting the externals is manual for now. Here are the urls you should use. A notepad window has just opened for you to update the external URLs.
echo Copy these in, replacing the existing commonapps and framework URLs.
echo https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/CommonApps/branches/%team_name%/%project%%se_branch%/CommonApps/Java%%20Source
echo https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/Framework/branches/%team_name%/%project%%se_branch%/Framework/Java%%20Source

if "%project%" == "eCOS" (
    cd %svn_dir%\%se_project%_%se_branch%
)
if "%project%" == "inMotion" (
    cd %svn_dir%\%se_project%_%se_branch%\src\main
)

if %dry_run%==1 (
    :: open an editor for the user to finish it with
    set SVN_EDITOR=notepad
    echo svn pe svn:externals .

    echo svn commit --depth empty . -m "[%se_artifact%] : Updating the externals on the %se_branch% feature branch"

    echo Updating %svn_dir%\%se_project%_%se_branch% to grab new externals...
    echo svn update > nul
) else (
    :: open an editor for the user to finish it with
    set SVN_EDITOR=notepad
    svn pe svn:externals .

    svn commit --depth empty . -m "[%se_artifact%] : Updating the externals on the %se_branch% feature branch"

    echo Updating %svn_dir%\%se_project%_%se_branch% to grab new externals...
    svn update > nul
)

endlocal
exit /b



::func rm_branch(project,branch,artifact)
::deletes a branch (history is kept in repo)
:RM_BRANCH
setlocal

:: rm_project - eCOS, CommonApps, Framework, props
SET rm_project=%1
:: rm_branch - 9.8.2_OSS_PRE
SET rm_branch=%2
:: rm_artifact - artf12345 (svn artifact for )
SET rm_artifact=%3

if %dry_run%==1 (
    echo svn rm https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%rm_project%/branches/%rm_branch% -m "[%rm_artifact%] pruning branch %rm_project%/%rm_branch%"
) else (
    svn rm https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%rm_project%/branches/%rm_branch% -m "[%rm_artifact%] pruning branch %rm_project%/%rm_branch%"
)
endlocal
exit /b






::func co_branch(from,to)
::checks out a branch from motion repo
:CO_BRANCH
setlocal

:: co_from - svn repo path
SET co_from=%1
:: co_to - checkout directory
SET co_to=%2

echo Checking out %co_from% to %co_to%...

if %dry_run%==1 (
    echo svn checkout https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%co_from% %co_to% > nul
) else (
    svn checkout https://teamforge.corp.motion-ind.com/svn/repos/motionsvn/%co_from% %co_to% > nul
)
endlocal
exit /b