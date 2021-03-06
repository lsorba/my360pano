@echo off

rem Script to stitch panoramic videos produced by Samsung Gear360.
rem Could be adopted to use with other cameras after creating pto file
rem (Huging template)

rem For help see:
rem https://github.com/ultramango/gear360pano

rem Names:
rem dec, DEC, decoding - means video to images
rem enc, ENC, encoding - means stitched images to video

set SCRIPTNAME=%0
set SCRIPTPATH=%~dp0
set FRAMESTEMPDIR=frames
set STITCHEDTEMPDIR=frames_stitched
set OUTDIR=%SCRIPTPATH%\html\data
set FFMPEGPATH=c:\Program Files\ffmpeg\bin
set HUGINPATH=C:\Program Files\Hugin\bin
set HUGINPATH32=C:\Program Files (x86)\Hugin\bin
set FFMPEGQUALITYDEC=-q:v 2
set FFMPEGQUALITYENC=-c:v libx265 -crf 18
rem %% is an escape character (note: this will fail on wine's cmd.exe)
set IMAGETMPLDEC=image%%05d.jpg
set IMAGETMPLENC=image%%05d_pano.jpg
set PTOTMPL4096=gear360video4096.pto
set PTOTMPL3840=gear360video3840.pto
set PTOTMPL2560=gear360video2560.pto
set PTOTMPL=%SCRIPTPATH%\%PTOTMPL3840%
set TMPAUDIO=tmpaudio.aac
set TMPVIDEO=tmpvideo.mp4
set DEBUG=""


rem Process arguments
set PARAMCOUNT=0
rem We need this due to stupid parameter substitution
setlocal enabledelayedexpansion
:PARAMLOOP
rem Small hack as substring doesn't work on %1 (need to use delayed sub.?)
set _TMP=%1
set FIRSTCHAR=%_TMP:~0,1%
rem No arguments?
rem call :PRINT_DEBUG Current arg: %_TMP%
if "%_TMP%" == "" goto PARAMDONE
rem Process arguments
if "%FIRSTCHAR%" == "/" (
  set SWITCH=!_TMP:~1,2!
  rem call :PRINT_DEBUG Current switch: !SWITCH!
  rem Switch processing
  if /i "!SWITCH!" == "h" (
    rem call :PRINT_DEBUG Printing help
    goto NOARGS
  )
  if /i "!SWITCH!" == "o" (
    shift
    rem call :PRINT_DEBUG Setting output directory to: %2
    set OUTDIR=%2
  )
  if /i "!SWITCH!" == "t" (
    shift
    rem call :PRINT_DEBUG Setting temporary dir: %2
    if not exist "%2" (
      echo Directory "%2" does not exist, using system default
    ) else (
      set MYTEMPDIR=%2
    )
  )
) else (
  if %PARAMCOUNT% EQU 0 (
    rem call :PRINT_DEBUG Input file: %_TMP%
    set VIDINNAME=%_TMP%
  )
  if %PARAMCOUNT% EQU 1 (
    rem call :PRINT_DEBUG Setting PTO: %_TMP%
    set OUTVIDNAME=%_TMP%
  )
  set /a PARAMCOUNT+=1
)
shift & goto PARAMLOOP
:PARAMDONE

rem Start timer
set start=%time%

rem Check arguments
IF "%VIDINNAME%" == "" goto NOARGS

rem Check if second argument present, if not, set some default for output filename
rem This is here, because for whatever reason OUTVIDNAME gets overriden by
rem the last iterated filename if this is at the beginning (for loop is buggy?)
if "%OUTVIDNAME%" neq "" goto SETNAMEOK
call :MAKEOUTNAME %VIDINNAME%

:SETNAMEOK
rem Check ffmpeg...
if not exist "%FFMPEGPATH%/ffmpeg.exe" goto NOFFMPEG
rem Check Hugin...
if exist "%HUGINPATH%/nona.exe" goto HUGINOK
rem 64 bits not found? Check x86
if not exist "%HUGINPATH32%/nona.exe" goto NOHUGIN

:HUGINOK

rem Temporary directory set?
if "%MYTEMPDIR%" == "" set MYTEMPDIR=%TEMP%

rem Create temporary directories
set FRAMESTEMP=%MYTEMPDIR%\%FRAMESTEMPDIR%
set STITCHEDTEMP=%MYTEMPDIR%\%STITCHEDTEMPDIR%
if not exist "%FRAMESTEMP%" mkdir %FRAMESTEMP%
if not exist "%STITCHEDTEMP%" mkdir %STITCHEDTEMP%

rem Execute commands (as simple as it is)
echo "Converting video to images..."
"%FFMPEGPATH%\ffmpeg.exe" -y -i %VIDINNAME% %FRAMESTEMP%\%IMAGETMPLDEC%
if %ERRORLEVEL% EQU 1 GOTO FFMPEGERROR

rem Detect video size and match Hugin template file
set TMPVIDSIZE=%MYTEMPDIR%\vidsize.tmp
"%FFMPEGPATH%\ffprobe.exe" -v error ^
                           -of csv ^
                           -select_streams v:0 ^
                           -show_entries stream=height,width ^
                           %VIDINNAME% > %TMPVIDSIZE%

for /f "tokens=1-18* delims=," %%A in (%TMPVIDSIZE%) do (
  set VIDSIZE=%%~B:%%~C
)
del %TMPVIDSIZE%

if "%VIDSIZE%"=="4096:2048" set PTOTMPL=%SCRIPTPATH%\%PTOTMPL4096%
if "%VIDSIZE%"=="3840:1920" set PTOTMPL=%SCRIPTPATH%\%PTOTMPL3840%
if "%VIDSIZE%"=="2560:1280" set PTOTMPL=%SCRIPTPATH%\%PTOTMPL2560%

rem Detect framerate
set TMPFPS=%MYTEMPDIR%\vidfps.tmp
"%FFMPEGPATH%\ffprobe.exe" -v error ^
                           -of csv ^
                           -select_streams v:0 ^
                           -show_entries stream=r_frame_rate ^
                           %VIDINNAME% > %TMPFPS%

for /f "tokens=1-18* delims=," %%A in (%TMPFPS%) do (
  set VIDFPS=%%~B
)
del %TMPFPS%

rem Stitching
echo "Stitching frames..."
call "%SCRIPTPATH%\gear360pano.cmd" /m /o "%STITCHEDTEMP%" "%FRAMESTEMP%\*.jpg" "%PTOTMPL%"

echo "Reencoding video..."
"%FFMPEGPATH%\ffmpeg.exe" -y -f image2 -i %STITCHEDTEMP%\%IMAGETMPLENC% -r %VIDFPS% -s %VIDSIZE% %FFMPEGQUALITYENC% %OUTVIDNAME%
if %ERRORLEVEL% EQU 1 GOTO FFMPEGERROR

rem Check if there's audio
set TMPHASAUDIO=%MYTEMPDIR%\hasaudio.tmp
"%FFMPEGPATH%\ffprobe.exe" -v error -of default=nw=1:nk=1 -select_streams a -show_entries stream=codec_type %VIDINNAME% > %TMPHASAUDIO%
set /p HASAUDIO=<%TMPHASAUDIO%
del %TMPHASAUDIO%

if "%HASAUDIO%" neq "" (
  echo "Extracting audio..."
  "%FFMPEGPATH%\ffmpeg.exe" -y -i %VIDINNAME% -vn -acodec copy %STITCHEDTEMP%\%TMPAUDIO%
  if %ERRORLEVEL% EQU 1 GOTO FFMPEGERROR

  echo "Merging audio..."
  "%FFMPEGPATH%\ffmpeg.exe" -y -i %OUTVIDNAME% -i %STITCHEDTEMP%\%TMPAUDIO% -c:v copy -c:a aac -strict experimental %OUTVIDNAME%
  if %ERRORLEVEL% EQU 1 GOTO FFMPEGERROR
)

rem Clean-up (f - force, read-only & dirs, q - quiet)
del /f /q %FRAMESTEMP%
del /f /q %STITCHEDTEMP%

echo Video written to %OUTVIDNAME%
goto eof

rem Filename extraction works only with %1, we need this workaround
:MAKEOUTNAME
set OUTVIDNAME=%OUTDIR%\%~n1_pano.mp4
exit /b 0

:NOARGS
echo Script to stitch raw panoramic videos.
echo Raw meaning two fisheye images side by side.
echo.
echo Script originally writen for Samsung Gear 360.
echo.
echo Usage:
echo %0 [options] infile [outfile]
echo.
echo Where inputfile is a panoramic video, outfile
echo is optional. Video file will be written
echo to a file with appended _pano, ex.: dummy.mp4 will
echo be stitched to dummy_pano.mp4.
echo.
echo /o will set the output directory of panoramas
echo    default: html/data
echo /s optimise for speed (lower quality)
echo /t set temporary directory (default: system's
echo    temporary directory)
echo /h prints this help
goto eof

:NOFFMPEG
echo ffmpeg was not found in %FFMPEGPATH%, download from: https://ffmpeg.zeranoe.com/builds/
echo and unpack to program files directory (name it ffmpeg)
goto eof

:NOHUGIN
echo Hugin was not found in %HUGINPATH% nor %HUGINPATH32%,
echo download from: https://http://hugin.sourceforge.net/
echo and install in default directory
goto eof

:FFMPEGERROR
echo ffmpeg failed, video not created
goto eof

:PRINT_DEBUG
if %DEBUG% == "yes" (
  echo DEBUG: %1 %2 %3 %4 %5 %6 %7 %8 %9
)
exit /b 0

:eof
