# Common.psm1 - Logging, JSON loader, retries, remote exec helpers
Set-StrictMode -Version Latest

function New-Log {
    param([string]$BasePath)
    
    try {
        if (-not (Test-Path $BasePath)) { 
            New-Item -ItemType Directory -Path $BasePath -Force | Out-Null 
        }
        $global:LogFile = Join-Path $BasePath ("deploy-{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Start-Transcript -Path $global:LogFile -Force | Out-Null
        Write-Host "Logging to $global:LogFile" -ForegroundColor Green
    } catch {
        Write-Warning "Unable to start transcript: $($_.Exception.Message)"
    }
}

function Stop-Log {
    try { 
        Stop-Transcript | Out-Null 
    } catch { 
        # Transcript may not be running - ignore error
    }
}

function Import-Settings {
    param([Parameter(Mandatory)][string]$Path)
    
    # Validate file exists
    if (-not (Test-Path $Path)) { 
        throw [System.Exception]::new("Settings file not found: $Path") 
    }
    
    try {
        $json = Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw [System.Exception]::new(("Failed to parse JSON from {0}. {1}" -f $Path, $_.Exception.Message))
    }

    # Minimal validation - check required fields
    if (-not $json.Project.Region) { 
        throw [System.Exception]::new("Missing Project.Region in settings.json") 
    }
    if (-not $json.SQL.FciName) { 
        throw [System.Exception]::new("Missing SQL.FciName in settings.json") 
    }
    if (-not $json.Cluster.Name) { 
        throw [System.Exception]::new("Missing Cluster.Name in settings.json") 
    }
    
    Write-Host "Configuration loaded successfully from $Path" -ForegroundColor Green
    return $json
}

function Retry-Command {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$MaxRetries = 5,
        [int]$DelaySeconds = 10,
        [string]$RetryMessage = "Retrying..."
    )
    
    $attempt = 0
    while ($true) {
        try {
            $attempt++
            return & $ScriptBlock
        } catch {
            if ($attempt -ge $MaxRetries) { 
                throw [System.Exception]::new("Command failed after $MaxRetries attempts. Last error: $($_.Exception.Message)")
            }
            Write-Warning "$RetryMessage Attempt $attempt/$MaxRetries failed: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Invoke-Remote {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 1800,
        [hashtable]$ArgumentList = @{}
    )
    
    $sess = $null
    try {
        Write-Host "Establishing remote session to $ComputerName..." -ForegroundColor Yellow
        $sess = New-PSSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
        
        Write-Host "Executing remote command on $ComputerName..." -ForegroundColor Yellow
        $result = Invoke-Command -Session $sess -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
        
        Write-Host "Remote command completed successfully on $ComputerName" -ForegroundColor Green
        return $result
    } catch {
        throw [System.Exception]::new(("Remote call to {0} failed: {1}" -f $ComputerName, $_.Exception.Message))
    } finally {
        if ($sess) { 
            Remove-PSSession -Session $sess -ErrorAction SilentlyContinue 
        }
    }
}

function Test-UncPathAccessible {
    param([Parameter(Mandatory)][string]$Path)
    
    try {
        return Test-Path -Path $Path
    } catch {
        Write-Warning "Unable to test path $Path : $($_.Exception.Message)"
        return $false
    }
}

function Ensure-WindowsFeature {
    param(
        [Parameter(Mandatory)][string]$FeatureName
    )
    
    try {
        $feature = Get-WindowsFeature -Name $FeatureName
        if (-not $feature.Installed) {
            Write-Host "Installing Windows feature: $FeatureName..." -ForegroundColor Yellow
            Install-WindowsFeature -Name $FeatureName -IncludeManagementTools -ErrorAction Stop | Out-Null
            Write-Host "Successfully installed feature: $FeatureName" -ForegroundColor Green
        } else {
            Write-Host "Feature already installed: $FeatureName" -ForegroundColor Cyan
        }
    } catch {
        throw [System.Exception]::new("Failed to install Windows feature $FeatureName : $($_.Exception.Message)")
    }
}

function Write-Section {
    param([string]$Text)
    
    $border = "=" * 60
    Write-Host "`n$border" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$border`n" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    
    Write-Host "Step: $Text" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Text)
    
    Write-Host "✓ $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    
    Write-Host "ℹ $Text" -ForegroundColor Blue
}

# Export functions
Export-ModuleMember -Function New-Log, Stop-Log, Import-Settings, Retry-Command, Invoke-Remote, Test-UncPathAccessible, Ensure-WindowsFeature, Write-Section, Write-Step, Write-Success, Write-Info
