# Aws.psm1 - Lightweight AWS interactions used here (validation only)
Set-StrictMode -Version Latest

function Test-FSxSharesAccessible {
    param(
        [Parameter(Mandatory)]$Config
    )
    
    $fsx = $Config.FSx
    $paths = @(
        "\\{0}\{1}" -f $fsx.DnsAlias, $fsx.Shares.Data,
        "\\{0}\{1}" -f $fsx.DnsAlias, $fsx.Shares.Backup,
        "\\{0}\{1}" -f $fsx.DnsAlias, $fsx.Shares.Witness
    )
    
    $allOk = $true
    
    Write-Host "Validating FSx shares accessibility..." -ForegroundColor Yellow
    
    foreach ($p in $paths) {
        Write-Host "Testing path: $p" -ForegroundColor Gray
        
        try {
            if (-not (Test-Path $p)) {
                Write-Warning "FSx path not accessible: $p"
                $allOk = $false
            } else {
                Write-Success "FSx path accessible: $p"
            }
        } catch {
            Write-Warning "Error testing FSx path $p : $($_.Exception.Message)"
            $allOk = $false
        }
    }
    
    if ($allOk) {
        Write-Success "All FSx shares are accessible"
    } else {
        Write-Host "Some FSx shares are not accessible. Please verify:" -ForegroundColor Red
        Write-Host "  1. FSx file system is created and running" -ForegroundColor Red
        Write-Host "  2. DNS alias '$($fsx.DnsAlias)' resolves correctly" -ForegroundColor Red
        Write-Host "  3. Required SMB shares exist: $($fsx.Shares.Data), $($fsx.Shares.Backup), $($fsx.Shares.Witness)" -ForegroundColor Red
        Write-Host "  4. Security groups allow SMB traffic (port 445)" -ForegroundColor Red
        Write-Host "  5. Domain credentials have access to the shares" -ForegroundColor Red
    }
    
    return $allOk
}

function Ensure-AwsCliPresent {
    Write-Host "Checking for AWS CLI availability..." -ForegroundColor Yellow
    
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Warning "AWS CLI not found in PATH. S3 media download will be skipped."
        Write-Host "If you plan to use S3 media source, please install AWS CLI v2:" -ForegroundColor Yellow
        Write-Host "  - Download from: https://aws.amazon.com/cli/" -ForegroundColor Yellow
        Write-Host "  - Or use alternative media sources (UNC or LocalISO)" -ForegroundColor Yellow
        return $false
    }
    
    Write-Success "AWS CLI is available"
    
    # Test AWS credentials if possible
    try {
        $identity = aws sts get-caller-identity --output json 2>$null | ConvertFrom-Json
        if ($identity) {
            Write-Success "AWS credentials configured for user: $($identity.Arn)"
        }
    } catch {
        Write-Warning "AWS CLI found but credentials may not be configured"
    }
    
    return $true
}

function Test-AwsConnectivity {
    param(
        [Parameter(Mandatory)]$Config
    )
    
    Write-Host "Testing AWS connectivity for region: $($Config.Project.Region)" -ForegroundColor Yellow
    
    try {
        # Test basic AWS connectivity
        if (Get-Command aws -ErrorAction SilentlyContinue) {
            $result = aws ec2 describe-regions --region $Config.Project.Region --output json 2>$null
            if ($result) {
                Write-Success "AWS connectivity verified for region $($Config.Project.Region)"
                return $true
            }
        }
        
        Write-Warning "Unable to verify AWS connectivity"
        return $false
    } catch {
        Write-Warning "AWS connectivity test failed: $($_.Exception.Message)"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Test-FSxSharesAccessible, Ensure-AwsCliPresent, Test-AwsConnectivity
