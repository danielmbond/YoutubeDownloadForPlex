#Download youtube videos rename them as plex friendly TV series and run plex scan

$downloadFolder = "H:\youtube\" #Path to downloaded youtube videos to
$exe = "$env:APPDATA\ytdownload\youtube-dl.exe" # http://youtube-dl.org/downloads/latest/youtube-dl.exe

#To get the subscription addresses subscribe to the youtube channel and go to https://www.youtube.com/subscription_manager?action_takeout=1
$MySubs = `
   'https://www.youtube.com/feeds/videos.xml?channel_id=UCS5Oz6CHmeoF7vSad0qqXfw', ` #DanTDM
   'https://www.youtube.com/feeds/videos.xml?channel_id=UChGJGhZ9SOOHvBB0Y4DOO_w', ` #Ryan ToysReview
   'https://www.youtube.com/feeds/videos.xml?channel_id=UCelMeixAOTs2OQAAi9wU8-g', ` #CookieSwirlC
   'https://www.youtube.com/feeds/videos.xml?channel_id=UCzTnzmwTgd-06-JJZNgBJBQ'  ` #Freak World / Annabelle and Victoria
   #'https://www.youtube.com/feeds/videos.xml?channel_id=UCOaMOXfe8EWH1GJyhqhXrAA'  #Denis / Roblox

$plexScan = 'C:\PROGRA~2\Plex\PLEXME~1\PLEXME~2.EXE'

$temp = $env:TEMP

# Check to see if a folder exists and try to create it if now.
function TestMakeFolder ($thePath) {
  if (!(Test-Path $thePath)) {
    try {
      New-Item $thePath -ItemType Directory
    } catch {
      $_
      break
    }
  }
}

function MatchGoodFilename ($filename) {
  $regex = '((?:.*[sS][0-9][0-9][eE][0-9][0-9]*))'
  if ($filename -match $regex) {
    return $true
  } else {
    return $false
  }
}

function AddLeadingZero ($inputNumber) {
  if ($inputNumber -lt 10) { #add a leading zero if the season number is less than 10
    $inputNumber = "0$inputNumber"
  }
  return $inputNumber
}

#function to move and rename youtube videos
function MoveFiles ($inputpath) {
  $youtubeBaseFolder = $inputpath
  $youtubeFolders = Get-ChildItem $youtubeBaseFolder -Recurse | ? { $_.PSIsContainer } | Select-Object FullName

  for ($i = 0; $i -lt $youtubeFolders.Count; $i++) {
    $shows = Get-ChildItem $youtubeFolders[$i].FullName
    $shows = $shows | Sort-Object -Property LastWriteTime
    $season = "";
    $episode = "";

    for ($j = 0; $j -lt $shows.Count; $j++) {

      if (!(MatchGoodFilename $shows[$j].FullName)) { #see if the file is already formated SxxExx
        $seasonNum = [math]::truncate(($j + 1) / 20) + 1 #increase the season number in increments of 20

        $season = AddLeadingZero $seasonNum
        $episode = AddLeadingZero ($j + 1)

        $basename = $shows[$j].BaseName

        #limit filenames to 30 characters
        if ($basename.Length -gt 30) {
          $basename = $basename.Substring(0,29).Trim()
        }

        #put filenames in the format Episode SxxExx
        $fullname = $shows[1].DirectoryName + "\" + $basename + " S" + $season + "E" + $episode + $shows[$j].Extension

        if (!(Test-Path $fullname)) {
          $fullname >> ($env:TEMP + "\ytlog.log")
          $shows[$j].MoveTo($fullname)
        }
      }
    }
  }
}

TestMakeFolder $downloadFolder

#check for youtube-dl.exe and try to download it if it doesn't exit
if (!(Test-Path $exe)) {
  $exePath = Split-Path -Path $exe
  if (!(Test-Path $exePath)) {
    TestMakeFolder $exePath
  }
  #https://blog.jourdant.me/post/3-ways-to-download-files-with-powershell
  try {
    $ytdurl = "http://youtube-dl.org/downloads/latest/youtube-dl.exe"
    $output = $exe
    $start_time = Get-Date

    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($ytdurl,$output)

    Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
  } catch {
    $_
    break
  }
}

$youtubeFolder = $downloadFolder.Replace("\","/") #youtube-dl.exe doesn't like backslashes
if ($youtubeFolder[$youtubeFolder.Length - 1] -ne "/") {
  $youtubeFolder = $youtubeFolder + "/"
}

#youtube downloader options
$options = " -o `"$youtubeFolder%(uploader)s/%(title)s.%(ext)s`" -f 22 "

foreach ($url in $MySubs)
{
  try {
    $url
    #https://gallery.technet.microsoft.com/scriptcenter/Parse-RSS-Feeds-With-db84ced2
    Invoke-WebRequest -Uri $url -OutFile "$temp\test.xml" #-ErrorAction Stop
    [xml]$Content = Get-Content "$temp\test.xml"
    $Feed = $Content.feed.entry
    foreach ($msg in $Feed) {
      $getFilenameArgs = " --get-filename -f 22 " + $msg.group.content.url
      $ytFilename = (cmd /c ($exe + $getFilenameArgs) 2`>`&1)
      $Matches = $null
      $regexRemoveAllAfterLastDash = "(?!.*-).*"
      $ytFilename -match $regexRemoveAllAfterLastDash | Out-Null

      if ($Matches.Count -gt 0) {
        $ytFilename = $ytFilename.Replace(("-" + $Matches[0]),"")
      }

      if ($ytFilename.Length -gt 24) {
        $ytFilename = $ytFilename.Substring(0,24) #reduce the filename to 24 characters max
      }

      if (Get-ChildItem -Recurse ($downloadFolder + $ytFilename + "*")) { #search for existing files and about download if found
        Write-Host File exists,skipping download.
      } else {
        $argList = $options + $msg.group.content.url
        Write-Host Downloading $msg.group.content.url
        Start-Process -FilePath $exe -ArgumentList $argList -Wait -NoNewWindow
      }
    } #EndForEach
  } #EndTry

  catch [System.Exception]{

    $WebReqErr = $error[0] | Select-Object * | Format-List -Force
    Write-Error "An error occurred while attempting to connect to the requested site.  The error was $WebReqErr.Exception"

  } #EndCatch
}

MoveFiles $downloadFolder

Invoke-Expression "$plexScan --scan --refresh --force" | Out-Null