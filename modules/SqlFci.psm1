# SqlFci.psm1 - Install SQL 2022 FCI on Node1, then Add Node2
Set-StrictMode -Version Latest

function Get-SqlServicePassword {
    param(
        [Parameter(Mandatory)]$Config
    )
    
    Write-Host "Determining SQL Server service account password..." -ForegroundColor Yellow
    
    # Priority: Secret Manager (not implemented here) -> Plaintext -> Prompt
    if ($Config.SQL.ServicePasswordSecretName -and $Config.SQL.ServicePasswordSecretName -ne "") {
        Write-Host "Retrieving password from AWS Secrets Manager..." -ForegroundColor Yellow
        # TODO: Implement Secrets Manager integration
        Write-Warning "Secrets Manager integration not implemented yet. Using alternative method."
    }
    
    if ($Config.SQL.ServicePasswordPlaintext -and $Config.SQL.ServicePasswordPlaintext -ne "") {
        Write-Warning "Using plaintext password from configuration (not recommended for production)"
        return (ConvertTo-SecureString $Config.SQL.ServicePasswordPlaintext -AsPlainText -Force)
    }
    
    Write-Host "Enter password for service account: $($Config.SQL.ServiceAccount)" -ForegroundColor Yellow
    return (Read-Host -AsSecureString -Prompt "SQL Service Account Password")
}

function Test-SqlClusteredInstancePresent {
    param(
        [Parameter(Mandatory)][string]$FciVnn
    )
    
    try {
        # Check if the SQL FCI cluster resource exists
        $clRes = Get-ClusterResource -Name $FciVnn -ErrorAction SilentlyContinue
        if ($clRes) { 
            Write-Info "SQL FCI cluster resource found: $($clRes.Name)"
            return $true 
        }
        
        # Alternative check - look for any SQL Server cluster resource
        $sqlResources = Get-ClusterResource | Where-Object { $_.ResourceType -eq "SQL Server" }
        if ($sqlResources) {
            Write-Info "Found existing SQL Server cluster resources: $($sqlResources.Name -join ', ')"
            return $true
        }
        
    } catch {
        Write-Warning "Error checking for existing SQL FCI: $($_.Exception.Message)"
    }
    
    return $false
}

# Export functions
Export-ModuleMember -Function Get-SqlServicePassword, Test-SqlClusteredInstancePresent
