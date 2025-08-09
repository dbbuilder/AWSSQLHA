# Validate.psm1 - Failover test and basic SQL probe
Set-StrictMode -Version Latest

function Test-FciFailover {
    param(
        [Parameter(Mandatory)]$Config
    )
    
    $vnn = $Config.SQL.FciName
    
    Write-Host "Performing SQL FCI failover test..." -ForegroundColor Yellow
    
    try {
        # Get the current SQL Server cluster resource
        $res = Get-ClusterResource -Name $vnn -ErrorAction Stop
        $currentOwner = $res.OwnerNode.Name
        
        Write-Info "Current SQL FCI owner: $currentOwner"
        Write-Info "SQL resource state: $($res.State)"
        
        if ($res.State -ne "Online") {
            throw [System.Exception]::new("SQL clustered resource is not online. Current state: $($res.State)")
        }

        # Get all available nodes
        $nodes = (Get-ClusterNode).Name
        $targetNode = ($nodes | Where-Object { $_ -ne $currentOwner })[0]
        
        if (-not $targetNode) {
            Write-Warning "Only one node visible in cluster; cannot test failover."
            return $false
        }

        Write-Host "Initiating failover from $currentOwner to $targetNode..." -ForegroundColor Yellow
        
        # Find the SQL Server cluster group
        $clusterGroup = Get-ClusterGroup | Where-Object { 
            $_.GroupType -eq "SqlServer" -or 
            $_.Name -like "*SQL Server*" -or 
            $_.Name -eq $vnn 
        } | Select-Object -First 1
        
        if (-not $clusterGroup) {
            throw [System.Exception]::new("Could not find SQL Server cluster group")
        }
        
        Write-Info "Moving cluster group: $($clusterGroup.Name)"
        
        # Perform the failover
        Move-ClusterGroup -InputObject $clusterGroup -Node $targetNode -ErrorAction Stop
        
        Write-Host "Failover initiated. Waiting for resource to come online..." -ForegroundColor Yellow
        
        # Wait for the resource to come online
        $timeout = 120 # 2 minutes
        $waited = 0
        $interval = 5
        
        do {
            Start-Sleep -Seconds $interval
            $waited += $interval
            
            $res = Get-ClusterResource -Name $vnn -ErrorAction Stop
            Write-Host "Waiting for SQL resource... State: $($res.State), Owner: $($res.OwnerNode.Name)" -ForegroundColor Gray
            
        } while ($res.State -ne "Online" -and $waited -lt $timeout)

        if ($res.State -ne "Online") {
            throw [System.Exception]::new("SQL clustered resource did not come online within $timeout seconds.")
        }

        $newOwner = $res.OwnerNode.Name
        Write-Success "Failover completed successfully!"
        Write-Success "Previous owner: $currentOwner"
        Write-Success "New owner: $newOwner"
        
        return $true
        
    } catch {
        throw [System.Exception]::new("Failover test failed: $($_.Exception.Message)")
    }
}

function Test-FciSqlConnectivity {
    param(
        [Parameter(Mandatory)]$Config
    )
    
    $server = $Config.SQL.FciName
    $db = $Config.Validation.TestDatabase
    
    Write-Host "Testing SQL connectivity via FCI VNN: $server" -ForegroundColor Yellow
    
    # Create test T-SQL script
    $tsql = @"
-- Test connectivity and create validation database
IF DB_ID('$db') IS NULL
    CREATE DATABASE [$db]

USE [$db]

-- Create test table if it doesn't exist
IF OBJECT_ID('dbo.FciValidation','U') IS NULL
    CREATE TABLE dbo.FciValidation(
        Id int IDENTITY(1,1) PRIMARY KEY,
        TestTime datetime2 NOT NULL DEFAULT(SYSDATETIME()),
        NodeName nvarchar(50) NOT NULL DEFAULT(@@SERVERNAME),
        Message nvarchar(255) NOT NULL
    )

-- Insert a test record
INSERT INTO dbo.FciValidation (Message) 
VALUES ('Connectivity test from FCI validation - ' + CONVERT(varchar(50), SYSDATETIME(), 120))

-- Return recent test results
SELECT TOP(5) 
    Id,
    TestTime,
    NodeName,
    Message
FROM dbo.FciValidation 
ORDER BY Id DESC

-- Show current FCI information
SELECT 
    @@SERVERNAME as ServerName,
    @@VERSION as SqlVersion,
    SERVERPROPERTY('IsClustered') as IsClustered,
    SERVERPROPERTY('ComputerNamePhysicalNetBIOS') as PhysicalNode

PRINT 'SQL FCI connectivity test completed successfully'
"@

    try {
        # Create temporary SQL file
        $tempSqlFile = New-TemporaryFile
        $tempSqlFile = [System.IO.Path]::ChangeExtension($tempSqlFile.FullName, ".sql")
        Set-Content -Path $tempSqlFile -Value $tsql -Encoding UTF8
        
        Write-Host "Executing connectivity test via sqlcmd..." -ForegroundColor Gray
        Write-Host "Server: $server" -ForegroundColor Gray
        Write-Host "Database: $db" -ForegroundColor Gray
        
        # Execute using sqlcmd with integrated authentication
        $sqlcmdArgs = @(
            "-S", $server,
            "-E",  # Use Windows Authentication
            "-i", $tempSqlFile,
            "-b"   # Exit on error
        )
        
        # Run sqlcmd and capture output
        $output = & sqlcmd @sqlcmdArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        # Clean up temporary file
        if (Test-Path $tempSqlFile) {
            Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue
        }
        
        if ($exitCode -ne 0) {
            throw [System.Exception]::new("sqlcmd failed with exit code $exitCode. Output: $output")
        }
        
        Write-Success "SQL connectivity test passed"
        Write-Host "sqlcmd output:" -ForegroundColor Cyan
        Write-Host $output -ForegroundColor Gray
        
        return $true
        
    } catch {
        # Clean up temporary file on error
        if (Test-Path $tempSqlFile) {
            Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue
        }
        
        throw [System.Exception]::new("SQL connectivity test failed: $($_.Exception.Message)")
    }
}

# Export functions
Export-ModuleMember -Function Test-FciFailover, Test-FciSqlConnectivity
