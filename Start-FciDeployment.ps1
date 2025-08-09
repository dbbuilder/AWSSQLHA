<# 
    Start-FciDeployment.ps1
    Orchestrates end-to-end deployment for SQL Server 2022 FCI on WSFC using FSx (Multi-AZ)
    - JSON-driven
    - Idempotent (safe re-runs)
    - Logging + comments
#>

[CmdletBinding()]
param(
    [string]$SettingsPath = ".\config\settings.json",
    [switch]$SkipMonitoring
)

# Import modules
Import-Module "$PSScriptRoot\modules\Common.psm1"          -Force
Import-Module "$PSScriptRoot\modules\Aws.psm1"             -Force
Import-Module "$PSScriptRoot\modules\WindowsCluster.psm1"  -Force
Import-Module "$PSScriptRoot\modules\SqlFci.psm1"          -Force
Import-Module "$PSScriptRoot\modules\Monitoring.psm1"      -Force
Import-Module "$PSScriptRoot\modules\Validate.psm1"        -Force

try {
    New-Log -BasePath "$PSScriptRoot\logs"
    Write-Section "Load configuration"
    $Config = Import-Settings -Path $SettingsPath

    $Node1 = $Config.EC2.Node1Name
    $Node2 = $Config.EC2.Node2Name
    $ClusterName = $Config.Cluster.Name
    $FciVnn = $Config.SQL.FciName

    Write-Section "Gather credentials"
    $DomainAdmin = Get-Credential -Message "Enter domain admin credentials with rights to join/cluster/install SQL"

    Write-Section "Validate FSx paths"
    if (-not (Test-FSxSharesAccessible -Config $Config)) {
        throw [System.Exception]::new("FSx shares not accessible. Ensure \\fsx\\sqldata, \\fsx\\sqlbackup, \\fsx\\witness exist and are reachable from both nodes.")
    }

    Write-Section "Ensure required Windows features on both nodes"
    foreach ($n in @($Node1,$Node2)) {
        Invoke-Remote -ComputerName $n -Credential $DomainAdmin -ScriptBlock {
            Import-Module ServerManager
            # Ensure Failover Clustering & tooling
            function Ensure-WindowsFeatureLocal([string]$Name) {
                $f = Get-WindowsFeature -Name $Name
                if (-not $f.Installed) { Install-WindowsFeature -Name $Name -IncludeManagementTools | Out-Null }
            }
            Ensure-WindowsFeatureLocal "Failover-Clustering"
            Ensure-WindowsFeatureLocal "RSAT-Clustering"
            Ensure-WindowsFeatureLocal "RSAT-Clustering-PowerShell"
            Ensure-WindowsFeatureLocal "RSAT-AD-PowerShell"
        }
    }
    Write-Host "Windows features present."

    Write-Section "Create or validate WSFC"
    # Create cluster from Node1 (or any node)
    Invoke-Remote -ComputerName $Node1 -Credential $DomainAdmin -ScriptBlock {
        param($ClusterName,$Node1,$Node2)
        $existing = Get-Cluster -ErrorAction SilentlyContinue
        if ($existing -and $existing.Name -eq $ClusterName) {
            Write-Host "Cluster exists: $ClusterName"
            return
        }
        try {
            Test-Cluster -Node $Node1,$Node2 -ErrorAction Stop | Out-Null
        } catch {
            Write-Warning "Test-Cluster warnings: $($_.Exception.Message)"
        }
        New-Cluster -Name $ClusterName -Node $Node1,$Node2 -NoStorage -AdministrativeAccessPoint DNS -ErrorAction Stop | Out-Null
        Write-Host "Cluster created: $ClusterName"
    } -ArgumentList $ClusterName,$Node1,$Node2

    # Configure quorum
    Write-Section "Configure quorum (File Share Witness)"
    Invoke-Remote -ComputerName $Node1 -Credential $DomainAdmin -ScriptBlock {
        param($ClusterName,$Witness)
        $cl = Get-Cluster -Name $ClusterName -ErrorAction Stop
        $current = (Get-ClusterQuorum -Cluster $cl).QuorumResource
        if ($current -and $current -like "*File Share Witness*") {
            Write-Host "File Share Witness already configured."
            return
        }
        Set-ClusterQuorum -Cluster $cl -FileShareWitness $Witness -ErrorAction Stop
        Write-Host "File Share Witness set to $Witness"
    } -ArgumentList $ClusterName,$Config.Cluster.FileWitnessPath

    # DNS tuning for multi-subnet
    Write-Section "Tune cluster DNS (RegisterAllProvidersIP, HostRecordTTL)"
    Invoke-Remote -ComputerName $Node1 -Credential $DomainAdmin -ScriptBlock {
        param($ClusterName,$Rapi,$Ttl)
        $cl = Get-Cluster -Name $ClusterName -ErrorAction Stop
        if ((Get-ClusterParameter -Cluster $cl -Name "RegisterAllProvidersIP").Value -ne $Rapi) {
            Set-ClusterParameter -Cluster $cl -Name "RegisterAllProvidersIP" -Value $Rapi
        }
        if ((Get-ClusterParameter -Cluster $cl -Name "HostRecordTTL").Value -ne $Ttl) {
            Set-ClusterParameter -Cluster $cl -Name "HostRecordTTL" -Value $Ttl
        }
        Write-Host "DNS parameters set."
    } -ArgumentList $ClusterName,$Config.Cluster.RegisterAllProvidersIP,$Config.Cluster.DnsTtlSeconds

    # Basic firewall (in case local firewall enabled; security groups protect externally)
    Write-Section "Ensure local firewall rules for SQL/SMB/RPC"
    foreach ($n in @($Node1,$Node2)) {
        Invoke-Remote -ComputerName $n -Credential $DomainAdmin -ScriptBlock {
            $rules = @(
                @{ Name="SQL Server 1433"; Protocol="TCP"; Port=1433 },
                @{ Name="SMB 445";        Protocol="TCP"; Port=445  },
                @{ Name="RPC 135";        Protocol="TCP"; Port=135  }
            )
            foreach ($r in $rules) {
                if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
                    New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow -Protocol $r.Protocol -LocalPort $r.Port | Out-Null
                }
            }
            Write-Host "Firewall rules ensured on $env:COMPUTERNAME"
        }
    }

    # Install SQL FCI on Node1
    Write-Section "Install SQL FCI on Node1"
    Install-SqlFci-Node1 -Config $Config -Node1 $Node1 -Credential $DomainAdmin

    # Add Node2
    Write-Section "Add Node2 to SQL FCI"
    Add-SqlFci-Node2 -Config $Config -Node2 $Node2 -Credential $DomainAdmin

    # Ensure services are up on current owner
    Write-Section "Validate SQL service is running on active owner"
    $owner = (Get-ClusterResource -Name $FciVnn).OwnerNode.Name
    Ensure-SqlServicesUp -ActiveNode $owner

    # Monitoring (optional)
    if (-not $SkipMonitoring) {
        Write-Section "Install & configure CloudWatch Agent on both nodes"
        foreach ($n in @($Node1,$Node2)) {
            Ensure-CloudWatchAgent -Config $Config -ComputerName $n -Credential $DomainAdmin
        }
    } else {
        Write-Host "SkipMonitoring flag set; skipping CloudWatch Agent."
    }

    # Validation: Connectivity & Failover
    Write-Section "Validation - SQL connectivity via VNN"
    Test-FciSqlConnectivity -Config $Config

    if ($Config.Validation.FailoverTest) {
        Write-Section "Validation - Failover"
        Test-FciFailover -Config $Config

        # Re-test connectivity after failover
        if ($Config.Validation.ReconnectTest) {
            Write-Section "Validation - Connectivity after failover"
            Test-FciSqlConnectivity -Config $Config
        }
    }

    Write-Section "Completed successfully"
    Write-Host "SQL FCI deployment complete. Review logs at $global:LogFile"
}
catch {
    Write-Error ("FAILED: {0}" -f $_.Exception.Message)
    exit 1
}
finally {
    Stop-Log
}
