# City of Heroes (Ouroboros v2i2.1.0) on this PC: setup, start, stop and reset.
# Run it through start.bat, stop.bat or reset.bat. Plain ASCII on purpose: Windows
# PowerShell 5.1 reads scripts without a byte-order mark as ANSI.
#
# Other actions:  coh.ps1 account   create another account (servers must be running)
#                 coh.ps1 status    show the containers
# Unattended (for testing):
#   coh.ps1 start -ServerDir <dir> -ClientDir <dir> -AccountName <name> -AccountPassword <pw>
#                 -NoLaunch -NoShortcuts -NoPause
#   coh.ps1 reset -Yes -NoPause
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'reset', 'account', 'status')]
    [string]$Action = 'start',
    [string]$ServerDir,
    [string]$ClientDir,
    [string]$AccountName,
    [string]$AccountPassword,
    [switch]$NoLaunch,
    [switch]$NoShortcuts,
    [switch]$NoPause,
    [switch]$Yes
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $Root 'docker-compose.yml'
$EnvFile = Join-Path $Root '.env'
$SettingsFile = Join-Path $Root 'settings.json'
$Version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -TotalCount 1).Trim()
$Image = "coh-server:$Version"
$ImageFile = Join-Path $Root "image\coh-server-$Version.tar.xz"
$Project = 'coh-local'
$GameDataVolume = 'coh-local-gamedata'
$GameContainer = 'coh-local-game-1'
$ImportContainer = 'coh-local-import'
$PlayShortcut = 'City of Heroes (local).lnk'
$StopShortcut = 'Stop City of Heroes servers.lnk'

# ------------------------------------------------------------------ output
function Say([string]$Text) { Write-Host $Text }
function Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Warn([string]$Text) { Write-Host "WARNING: $Text" -ForegroundColor Yellow }
function Fail([string]$Text) {
    Write-Host ''
    Write-Host "ERROR: $Text" -ForegroundColor Red
    exit 1
}
function Finish {
    if (-not $NoPause) {
        Write-Host ''
        Read-Host 'Press Enter to close this window' | Out-Null
    }
    exit 0
}

# ------------------------------------------------------------------ docker
function Invoke-Compose {
    & docker compose --project-name $Project --project-directory $Root -f $ComposeFile --env-file $EnvFile @args
}

function Get-DockerOs {
    $os = & docker version --format '{{.Server.Os}}' 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    return "$os".Trim()
}

function Confirm-Docker {
    Step 'Checking Docker Desktop'
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Say 'Docker Desktop is not installed. Install it from'
        Say '  https://www.docker.com/products/docker-desktop/'
        Say 'then start it once, accept its terms, and run start.bat again.'
        if (-not $NoPause) { Start-Process 'https://www.docker.com/products/docker-desktop/' }
        Fail 'Docker Desktop is required.'
    }
    $os = Get-DockerOs
    if ($os -eq '') {
        $exe = @("$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
                 "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe") |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($exe) {
            Say 'Starting Docker Desktop (this can take a minute)...'
            Start-Process -FilePath $exe
        } else {
            Say 'Please start Docker Desktop.'
        }
        $deadline = (Get-Date).AddMinutes(4)
        while ($os -eq '' -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            $os = Get-DockerOs
        }
    }
    if ($os -eq 'windows') {
        Fail 'Docker Desktop is set to Windows containers. Right-click its icon near the clock, choose "Switch to Linux containers...", then run this again.'
    }
    if ($os -ne 'linux') {
        Fail 'Docker Desktop is not running. Open it, wait until it says "Engine running", then run this again.'
    }
    Say 'Docker Desktop is running.'
    $mem = & docker info --format '{{.MemTotal}}' 2>$null
    if ("$mem" -match '^\d+$' -and [double]$mem -lt 6GB) {
        Warn ("Docker Desktop has {0:N1} GB of memory. 8 GB or more is better; each zone you visit uses about 1 GB." -f ([double]$mem / 1GB))
    }
}

function Test-Volume([string]$Name) {
    & docker volume inspect $Name *> $null
    return ($LASTEXITCODE -eq 0)
}

function Confirm-Image {
    & docker image inspect $Image *> $null
    if ($LASTEXITCODE -eq 0) { return }
    if (-not (Test-Path -LiteralPath $ImageFile)) {
        Fail "The server image file is missing: $ImageFile. Download the kit again."
    }
    Step "Loading the server image ($Version)"
    Say 'This takes a minute or two.'
    & docker load -i $ImageFile
    if ($LASTEXITCODE -ne 0) { Fail 'Could not load the server image.' }
}

# ------------------------------------------------------------------ settings
function Read-Settings {
    $s = [pscustomobject]@{ serverDir = ''; clientDir = ''; account = ''; setupComplete = $false }
    if (Test-Path -LiteralPath $SettingsFile) {
        try {
            $j = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $s.($p.Name) = $p.Value }
        } catch {
            Warn 'settings.json could not be read; setup will ask again.'
        }
    }
    return $s
}

function Save-Settings($s) {
    [IO.File]::WriteAllText($SettingsFile, ($s | ConvertTo-Json))
}

# The database password is fixed when the database is first created, so keep it.
function Write-EnvFile {
    $pw = ''
    if (Test-Path -LiteralPath $EnvFile) {
        foreach ($line in Get-Content -LiteralPath $EnvFile) {
            if ($line -match '^COH_PG_PASSWORD=(.+)$') { $pw = $Matches[1].Trim() }
        }
    } elseif (Test-Volume "${Project}_pgdata") {
        Fail ('The file .env is missing, but a database from an earlier setup exists. If you moved or ' +
              're-downloaded the kit, copy .env and settings.json from your old kit folder into this one ' +
              '(or extract the new download over the old folder). To start over instead, run reset.bat.')
    }
    if ($pw -eq '') {
        $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
        $bytes = New-Object byte[] 24
        (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
        $pw = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    }
    $text = "# Written by start.bat; keep it with the database.`nCOH_VERSION=$Version`nCOH_PG_PASSWORD=$pw`n"
    [IO.File]::WriteAllText($EnvFile, $text)
}

# ------------------------------------------------------------------ folders
function Read-Folder([string]$What) {
    Say "Paste the path of the $What, or press Enter to pick it in a window."
    $typed = Read-Host 'Folder'
    if ("$typed".Trim() -ne '') { return "$typed".Trim().Trim('"') }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Select the $What"
        $dlg.ShowNewFolderButton = $false
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $result = $dlg.ShowDialog($owner)
        $owner.Dispose()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    } catch {
        Warn 'The folder window could not open; paste the path instead.'
    }
    return ''
}

function Resolve-ServerDir([string]$Path) {
    if ("$Path".Trim() -eq '') { return '' }
    foreach ($p in @($Path, (Join-Path $Path 'Server'))) {
        if ((Test-Path -LiteralPath (Join-Path $p 'version.ini')) -and
            (Test-Path -LiteralPath (Join-Path $p 'piggs\texts.pigg')) -and
            (Test-Path -LiteralPath (Join-Path $p 'data\server\db\servers.cfg'))) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }
    return ''
}

function Resolve-ClientDir([string]$Path) {
    if ("$Path".Trim() -eq '') { return '' }
    foreach ($p in @($Path, (Join-Path $Path 'Client'))) {
        if (Test-Path -LiteralPath (Join-Path $p 'Ouroboros.exe')) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return ''
}

function Get-ServerDir {
    $path = $ServerDir
    while ($true) {
        if ("$path".Trim() -eq '') {
            Say ''
            Say 'Where are the Ouroboros v2i2.1.0 SERVER files? This is the "Server" folder that'
            Say 'contains data, piggs and version.ini (or the folder above it).'
            $path = Read-Folder 'Ouroboros Server folder'
        }
        $dir = Resolve-ServerDir $path
        if ($dir -ne '') {
            $ver = (Get-Content -LiteralPath (Join-Path $dir 'version.ini') -Raw)
            if ($ver -match 'v2i2\.1\.0') { Say "Server files: $dir"; return $dir }
            Warn ("That is Ouroboros " + $ver.Trim() + ". This kit needs v2i2.1.0 (Volume 2 Issue 1.1).")
        } else {
            Warn "No Ouroboros Server files (data, piggs, version.ini) in: $path"
        }
        if ($ServerDir) { Fail 'The -ServerDir folder is not usable.' }
        $path = ''
    }
}

function Get-ClientDir {
    $path = $ClientDir
    while ($true) {
        if ("$path".Trim() -eq '') {
            Say ''
            Say 'Where is the Ouroboros v2i2.1.0 game CLIENT? This is the folder with Ouroboros.exe.'
            $path = Read-Folder 'Ouroboros client folder'
        }
        $dir = Resolve-ClientDir $path
        if ($dir -ne '') {
            $vf = Join-Path $dir 'version.ini'
            if ((Test-Path -LiteralPath $vf) -and -not ((Get-Content -LiteralPath $vf -Raw) -match 'v2i2\.1\.0')) {
                Warn 'This client is not v2i2.1.0. Other versions may crash on these servers.'
            }
            Say "Game client: $dir"
            return $dir
        }
        Warn "No Ouroboros.exe in: $path"
        if ($ClientDir) { Fail 'The -ClientDir folder is not usable.' }
        $path = ''
    }
}

# ------------------------------------------------------------------ game data
function Test-GameData {
    if (-not (Test-Volume $GameDataVolume)) { return $false }
    $out = & docker run --rm -v "${GameDataVolume}:/gamedata:ro" --entrypoint cat $Image /gamedata/.coh-import-ok 2>$null
    return ($LASTEXITCODE -eq 0 -and "$out" -match 'v2i2\.1\.0')
}

function Import-GameData([string]$Dir) {
    Step 'Copying the game data into Docker'
    $sum = (Get-ChildItem -LiteralPath (Join-Path $Dir 'data'), (Join-Path $Dir 'piggs') -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    $totalMB = [math]::Max(1, [int]($sum / 1MB))
    Say ("{0:N1} GB to copy. This takes a few minutes; your Ouroboros folder is only read." -f ($totalMB / 1024))
    & docker volume create $GameDataVolume | Out-Null
    & docker rm -f $ImportContainer *> $null
    & docker run -d --name $ImportContainer -v "${GameDataVolume}:/gamedata" `
        --mount "type=bind,source=$Dir,target=/src,readonly" --entrypoint /opt/coh/coh $Image import | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'Could not start copying. Docker Desktop must be able to read that drive.' }
    while ($true) {
        $running = & docker inspect -f '{{.State.Running}}' $ImportContainer 2>$null
        $du = & docker exec $ImportContainer du -sm /gamedata 2>$null
        if ("$du" -match '^(\d+)') {
            $mb = [int]$Matches[1]
            Write-Progress -Activity 'Copying game data' -Status ("{0:N1} of {1:N1} GB" -f ($mb / 1024), ($totalMB / 1024)) `
                -PercentComplete ([math]::Min(100, [int](100 * $mb / $totalMB)))
        }
        if ("$running".Trim() -ne 'true') { break }
        Start-Sleep -Seconds 2
    }
    Write-Progress -Activity 'Copying game data' -Completed
    $code = "$(& docker inspect -f '{{.State.ExitCode}}' $ImportContainer)".Trim()
    $log = (& docker logs $ImportContainer 2>&1 | ForEach-Object { "$_" }) -join "`n"
    & docker rm -f $ImportContainer *> $null
    if ($code -ne '0') { Fail "Copying the game data failed:`n$log" }
    Say $log
}

# ------------------------------------------------------------------ servers
function Wait-Ready([string]$Since) {
    Say 'Waiting for the servers (about a minute):'
    $deadline = (Get-Date).AddMinutes(15)
    $seen = 0
    while ((Get-Date) -lt $deadline) {
        # A restarted container keeps its earlier output; show only this start's lines.
        $lines = @(& docker logs --since $Since $GameContainer 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^\[coh ' })
        for ($i = $seen; $i -lt $lines.Count; $i++) { Say ('  ' + $lines[$i]) }
        $seen = [math]::Max($seen, $lines.Count)
        $health = "$(& docker inspect -f '{{.State.Health.Status}}' $GameContainer 2>$null)".Trim()
        $state = "$(& docker inspect -f '{{.State.Status}}' $GameContainer 2>$null)".Trim()
        if ($health -eq 'healthy') { return }
        if ($state -eq 'exited' -or $state -eq 'dead') {
            Fail 'The servers stopped while starting. Run start.bat again; if it keeps happening, see Troubleshooting in README.md.'
        }
        Start-Sleep -Seconds 3
    }
    Fail 'The servers did not become ready within 15 minutes. See Troubleshooting in README.md.'
}

function Start-Servers {
    Step 'Starting the servers'
    $since = (Get-Date).ToUniversalTime().AddSeconds(-5).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Invoke-Compose up -d
    if ($LASTEXITCODE -ne 0) { Fail 'Docker could not start the servers.' }
    Wait-Ready $since
}

function Read-Secret([string]$Prompt) {
    $s = Read-Host $Prompt -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function New-Account {
    Step 'Creating your game account'
    while ($true) {
        $name = $AccountName
        if (-not $name) {
            Say 'Choose an account name (3 to 14 letters or digits) and a password (4 to 14'
            Say 'characters, no spaces). You type these on the game''s login screen.'
            $name = Read-Host 'Account name'
        }
        $name = "$name".Trim().ToLower()
        if ($name -notmatch '^[a-z0-9]{3,14}$') {
            Warn 'Use 3 to 14 letters or digits.'
            if ($AccountName) { Fail 'Invalid -AccountName.' }
            continue
        }
        $pw = $AccountPassword
        if (-not $pw) {
            $pw = Read-Secret 'Password'
            if ($pw -cne (Read-Secret 'Type the password again')) { Warn 'The passwords do not match.'; continue }
        }
        if ($pw -notmatch '^[!-~]{4,14}$') {
            Warn 'Passwords are 4 to 14 characters: letters, digits or symbols, no spaces.'
            if ($AccountPassword) { Fail 'Invalid -AccountPassword.' }
            continue
        }
        $env:COH_NEW_PASSWORD = $pw
        $out = (& docker exec -e COH_NEW_PASSWORD $GameContainer coh create-account $name 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $code = $LASTEXITCODE
        Remove-Item Env:COH_NEW_PASSWORD -ErrorAction SilentlyContinue
        if ($code -eq 0) { Say "Account '$name' created."; return $name }
        if ($code -eq 3) { Say "The account '$name' already exists; log in with it."; return $name }
        Fail "Could not create the account:`n$out"
    }
}

function New-Shortcuts([string]$Client) {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut((Join-Path $desktop $PlayShortcut))
        $s.TargetPath = Join-Path $Root 'start.bat'
        $s.WorkingDirectory = $Root
        $s.IconLocation = (Join-Path $Client 'Ouroboros.exe') + ',0'
        $s.Description = 'Start the City of Heroes servers and the game'
        $s.Save()
        $t = $shell.CreateShortcut((Join-Path $desktop $StopShortcut))
        $t.TargetPath = Join-Path $Root 'stop.bat'
        $t.WorkingDirectory = $Root
        $t.Description = 'Save every character and stop the City of Heroes servers'
        $t.Save()
        Say "Desktop shortcuts: '$($PlayShortcut -replace '\.lnk$','')' and '$($StopShortcut -replace '\.lnk$','')'."
    } catch {
        Warn 'Could not create the desktop shortcuts; use start.bat and stop.bat instead.'
    }
}

function Start-Client([string]$Client) {
    $argList = @('-auth', '127.0.0.1', '-noversioncheck')
    if (Test-Path -LiteralPath (Join-Path $Client 'ouro')) { $argList += @('-patchdir', 'ouro') }
    Start-Process -FilePath (Join-Path $Client 'Ouroboros.exe') -ArgumentList $argList -WorkingDirectory $Client
}

# ------------------------------------------------------------------ actions
function Invoke-Start {
    Say "City of Heroes servers (Ouroboros v2i2.1.0, kit $Version)"
    Confirm-Docker
    $settings = Read-Settings
    Write-EnvFile
    Confirm-Image
    $firstRun = -not $settings.setupComplete
    if ($firstRun) {
        Step 'First-time setup'
        Say 'You need the Ouroboros v2i2.1.0 server files and game client (see README.md).'
        $settings.serverDir = Get-ServerDir
        $settings.clientDir = Get-ClientDir
        Save-Settings $settings
    } elseif (-not (Resolve-ClientDir $settings.clientDir)) {
        Warn "The game client is no longer in $($settings.clientDir)."
        $settings.clientDir = Get-ClientDir
        Save-Settings $settings
    }
    if (-not (Test-GameData)) {
        $dir = Resolve-ServerDir $settings.serverDir
        if ($dir -eq '') { $dir = Get-ServerDir; $settings.serverDir = $dir; Save-Settings $settings }
        Import-GameData $dir
    }
    Start-Servers
    if ($firstRun) {
        $settings.account = New-Account
        if (-not $NoShortcuts) { New-Shortcuts $settings.clientDir }
        $settings.setupComplete = $true
        Save-Settings $settings
    }
    Step 'Ready'
    Say 'The servers are running. Log in with your account name and password.'
    if ($settings.account) { Say "Your account: $($settings.account)" }
    if (-not $NoLaunch) {
        $answer = Read-Host 'Launch City of Heroes now? [Y/n]'
        if ("$answer".Trim() -eq '' -or "$answer" -match '^\s*[yY]') {
            Start-Client $settings.clientDir
            Say 'The game is starting.'
        }
    }
    Say ''
    Say 'When you finish playing, run stop.bat (or the "Stop City of Heroes servers" shortcut).'
    Say 'It saves every character before the servers stop.'
    Finish
}

function Invoke-Stop {
    if (-not (Test-Path -LiteralPath $EnvFile)) { Say 'Nothing is set up yet.'; Finish }
    if ((Get-DockerOs) -ne 'linux') { Say 'Docker Desktop is not running, so the servers are already stopped.'; Finish }
    Step 'Stopping the servers'
    Say 'Every character is saved first; this can take up to a few minutes.'
    Invoke-Compose stop
    if ($LASTEXITCODE -ne 0) { Fail 'Docker could not stop the servers.' }
    Say 'The servers are stopped. You can quit Docker Desktop from its icon near the clock.'
    Finish
}

function Invoke-Reset {
    Step 'Reset'
    Say 'This deletes the servers, the copy of the game data, every account and character,'
    Say 'and this kit''s settings. Your Ouroboros folders are not touched.'
    if (-not $Yes) {
        if ((Read-Host 'Type RESET to continue') -cne 'RESET') { Say 'Nothing was deleted.'; Finish }
    }
    Confirm-Docker
    if (Test-Path -LiteralPath $EnvFile) {
        Invoke-Compose down --volumes --remove-orphans
    } else {
        & docker rm -f "$Project-game-1" "$Project-postgres-1" *> $null
    }
    & docker rm -f $ImportContainer *> $null
    foreach ($v in @($GameDataVolume, "${Project}_pgdata", "${Project}_missionserver", "${Project}_logs")) {
        & docker volume rm $v *> $null
    }
    foreach ($img in @(& docker images coh-server --format '{{.Repository}}:{{.Tag}}')) {
        & docker rmi $img *> $null
    }
    Remove-Item -LiteralPath $EnvFile, $SettingsFile -ErrorAction SilentlyContinue
    $desktop = [Environment]::GetFolderPath('Desktop')
    Remove-Item -LiteralPath (Join-Path $desktop $PlayShortcut), (Join-Path $desktop $StopShortcut) -ErrorAction SilentlyContinue
    Say 'Done. Run start.bat to set everything up again.'
    Finish
}

switch ($Action) {
    'start' { Invoke-Start }
    'stop' { Invoke-Stop }
    'reset' { Invoke-Reset }
    'account' {
        if ((Get-DockerOs) -ne 'linux') { Fail 'Docker Desktop is not running. Run start.bat first.' }
        $null = New-Account
        Finish
    }
    'status' {
        Invoke-Compose ps
        Finish
    }
}
