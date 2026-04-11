param(
    [int]$BackendPort = 8000,
    [int]$SolverPort = 8889,
    [int]$Grok2ApiPort = 8011,
    [int]$CLIProxyAPIPort = 8317,
    [int]$FullStop = 1
)

$ErrorActionPreference = "Stop"
$ports = @($BackendPort, $SolverPort)
if ($FullStop -ne 0) {
    $ports += @($Grok2ApiPort, $CLIProxyAPIPort)
}
$ports = $ports | Where-Object { $_ -gt 0 } | Select-Object -Unique

Write-Host "[INFO] Ports to stop: $($ports -join ', ')"

function Get-ProcessIdsByPorts {
    param([int[]]$TargetPorts)
    $result = @()
    $connections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in $TargetPorts }
    foreach ($conn in $connections) {
        if ($conn.OwningProcess) {
            $result += [int]$conn.OwningProcess
        }
    }
    return $result | Select-Object -Unique
}

function Get-ProcessIdsByNames {
    param([string[]]$Names)
    $result = @()
    foreach ($name in $Names) {
        try {
            $items = Get-Process -Name $name -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $result += [int]$item.Id
            }
        } catch {}
    }
    return $result | Select-Object -Unique
}

function Wait-ProcessExit {
    param(
        [int]$ProcessId,
        [int]$TimeoutSeconds = 6
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            return $true
        }
        Start-Sleep -Milliseconds 250
    }
    return -not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Stop-ProcessTreeSafe {
    param([int]$ProcessId)

    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
        return $true
    }

    Write-Host "[INFO] Trying graceful stop for PID=$ProcessId"
    try {
        & taskkill.exe /PID $ProcessId /T *> $null
    } catch {
        Write-Warning "taskkill graceful stop returned an error: $($_.Exception.Message)"
    }
    if (Wait-ProcessExit -ProcessId $ProcessId -TimeoutSeconds 6) {
        Write-Host "[OK] Stopped PID=$ProcessId"
        return $true
    }

    Write-Warning "PID=$ProcessId did not exit in time, switching to force stop"
    try {
        & taskkill.exe /PID $ProcessId /T /F *> $null
    } catch {
        Write-Warning "taskkill force stop returned an error: $($_.Exception.Message)"
    }
    if (Wait-ProcessExit -ProcessId $ProcessId -TimeoutSeconds 6) {
        Write-Host "[OK] Force stopped PID=$ProcessId"
        return $true
    }

    Write-Warning "taskkill could not fully stop PID=$ProcessId, trying Stop-Process -Force"
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
    } catch {
        Write-Warning "Stop-Process -Force failed: $($_.Exception.Message)"
    }
    if (Wait-ProcessExit -ProcessId $ProcessId -TimeoutSeconds 6) {
        Write-Host "[OK] Stop-Process force stopped PID=$ProcessId"
        return $true
    }

    Write-Warning "Failed to stop PID=$ProcessId"
    return $false
}

$connections = Get-ProcessIdsByPorts -TargetPorts $ports
$extraNames = @()
if ($FullStop -ne 0) {
    $extraNames += @("KiroAccountManager", "kiro-account-manager")
}
$extraPids = Get-ProcessIdsByNames -Names $extraNames
$targets = @($connections + $extraPids) | Where-Object { $_ } | Select-Object -Unique

if (-not $targets) {
    Write-Host "[INFO] No matching processes found"
    exit 0
}

foreach ($procId in $targets) {
    try {
        Stop-ProcessTreeSafe -ProcessId $procId | Out-Null
    } catch {
        Write-Warning "Stopping PID=$procId failed: $($_.Exception.Message)"
    }
}

Write-Host "[INFO] Stop completed"
