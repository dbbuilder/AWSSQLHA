# WindowsCluster.psm1 - WSFC install, create, quorum, DNS tuning, firewall
Set-StrictMode -Version Latest

function Ensure-ClusterFeature {
    Write-Host "Ensuring Failover Clustering features are installed..." -ForegroundColor Yellow
    
    # Core Failover Clustering feature
    Ensure-WindowsFeature -FeatureName "Failover-Clustering"
    
    # Management tools for clustering
    Ensure-WindowsFeature -FeatureName "RSAT-Clustering"
    Ensure-WindowsFeature -FeatureName "RSAT-Clustering-PowerShell"
    Ensure-WindowsFeature -FeatureName "RSAT-AD-PowerShell"
    
    Write-Success "All required clustering features are installed"
}

function Ensure-ClusterCreated {
    param(
        [Parameter(Mandatory)][string]$ClusterName,
        [Parameter(Mandatory)][string[]]$Nodes
    )
    
    Write-Host "Checking if cluster '$ClusterName' exists..." -ForegroundColor Yellow
    
    try {
        $existing = Get-Cluster -Name $ClusterName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Success "WSFC already exists: $ClusterName"
            
            # Verify all nodes are present
            $clusterNodes = (Get-ClusterNode -Cluster $existing).Name
            $missingNodes = $Nodes | Where-Object { $_ -notin $clusterNodes }
            
            if ($missingNodes) {
                Write-Warning "Missing nodes in cluster: $($missingNodes -join ', ')"
                foreach ($node in $missingNodes) {
                    Write-Host "Adding node $node to cluster..." -ForegroundColor Yellow
                    Add-ClusterNode -Name $node -Cluster $existing -ErrorAction Stop
                    Write-Success "Added node $node to cluster"
                }
            } else {
                Write-Success "All required nodes are present in the cluster"
            }
            return
        }
    } catch {
        Write-Warning "Error checking existing cluster: $($_.Exception.Message)"
    }
    
    Write-Host "Creating new cluster '$ClusterName' with nodes: $($Nodes -join ', ')..." -ForegroundColor Yellow
    
    # Run cluster validation (optional but recommended)
    try {
        Write-Host "Running cluster validation tests..." -ForegroundColor Yellow
        $validationReport = Test-Cluster -Node $Nodes -ErrorAction Stop
        Write-Success "Cluster validation completed successfully"
        
        # Log validation warnings if any
        if ($validationReport.Warnings) {
            Write-Warning "Cluster validation warnings found:"
            foreach ($warning in $validationReport.Warnings) {
                Write-Warning "  $warning"
            }
        }
    } catch {
        Write-Warning "Cluster validation reported issues: $($_.Exception.Message)"
        Write-Host "Proceeding with cluster creation anyway..." -ForegroundColor Yellow
    }

    try {
        # Create the cluster without storage, using DNS access point
        New-Cluster -Name $ClusterName -Node $Nodes -NoStorage -StaticAddress @() -AdministrativeAccessPoint DNS -ErrorAction Stop | Out-Null
        Write-Success "Successfully created cluster: $ClusterName"
        
        # Wait for cluster to stabilize
        Start-Sleep -Seconds 10
        
        # Verify cluster is operational
        $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
        if ($cluster.State -eq "Up") {
            Write-Success "Cluster is online and operational"
        } else {
            Write-Warning "Cluster state is: $($cluster.State)"
        }
        
    } catch {
        throw [System.Exception]::new("Failed to create cluster $ClusterName : $($_.Exception.Message)")
    }
}

# Export functions
Export-ModuleMember -Function Ensure-ClusterFeature, Ensure-ClusterCreated
