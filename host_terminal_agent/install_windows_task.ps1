[CmdletBinding()]
param(
    [string]$TaskName = "AI-Deep Monitor - Terminal hote protege"
)

$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    throw "Ce script est reserve a Windows."
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$agentPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "agent.py")).Path
$jobsPath = Join-Path $projectRoot "host_terminal_jobs"
$pythonCommand = Get-Command python.exe -ErrorAction Stop
$pythonPath = $pythonCommand.Source
$account = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

New-Item -ItemType Directory -Path $jobsPath -Force | Out-Null

# Une réinstallation doit réellement charger la nouvelle politique. On arrête
# uniquement l'agent dont la ligne de commande contient ce chemin absolu précis.
$existingAgents = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in @("python.exe", "pythonw.exe") -and
    $_.CommandLine -and
    $_.CommandLine.Contains($agentPath)
}
foreach ($agentProcess in $existingAgents) {
    Stop-Process -Id $agentProcess.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($existingAgents) {
    Start-Sleep -Milliseconds 500
}
$remainingAgent = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in @("python.exe", "pythonw.exe") -and
    $_.CommandLine -and
    $_.CommandLine.Contains($agentPath)
}
$lockPath = Join-Path $jobsPath ".agent.lock"
if (-not $remainingAgent -and (Test-Path -LiteralPath $lockPath)) {
    Remove-Item -LiteralPath $lockPath -Force
}

$arguments = '"{0}" --jobs-dir "{1}"' -f $agentPath, $jobsPath
$action = New-ScheduledTaskAction `
    -Execute $pythonPath `
    -Argument $arguments `
    -WorkingDirectory $projectRoot
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal `
    -UserId $account `
    -LogonType S4U `
    -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 99 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

$installedTask = $false
try {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Description "Agent local restreint du terminal de diagnostic AI-Deep Monitor" `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    $installedTask = $true
    Write-Host "Agent installe comme tache planifiee : $TaskName"
} catch {
    Write-Warning "Tache planifiee non autorisee. Installation dans le demarrage utilisateur."
}

if (-not $installedTask) {
    $startupDirectory = [Environment]::GetFolderPath("Startup")
    $launcherPath = Join-Path $startupDirectory "AI-Deep-Monitor-Terminal.vbs"
    $pythonWindowless = Join-Path (Split-Path -Parent $pythonPath) "pythonw.exe"
    if (-not (Test-Path -LiteralPath $pythonWindowless)) {
        $pythonWindowless = $pythonPath
    }
    $escapedPython = $pythonWindowless.Replace('"', '""')
    $escapedAgent = $agentPath.Replace('"', '""')
    $escapedJobs = $jobsPath.Replace('"', '""')
    $escapedRoot = $projectRoot.Replace('"', '""')
    $launcher = @"
Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = "$escapedRoot"
shell.Run Chr(34) & "$escapedPython" & Chr(34) & " " & Chr(34) & "$escapedAgent" & Chr(34) & " --jobs-dir " & Chr(34) & "$escapedJobs" & Chr(34), 0, False
"@
    [System.IO.File]::WriteAllText($launcherPath, $launcher, [System.Text.UTF8Encoding]::new($false))
    $startArguments = '"{0}" --jobs-dir "{1}"' -f $agentPath, $jobsPath
    Start-Process `
        -FilePath $pythonWindowless `
        -ArgumentList $startArguments `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden
    Write-Host "Agent installe dans le demarrage utilisateur : $launcherPath"
}

Write-Host "Agent demarre avec des droits limites et sans stockage du mot de passe."
