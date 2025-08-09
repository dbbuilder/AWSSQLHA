# Monitoring.psm1 - CloudWatch agent install & configure
Set-StrictMode -Version Latest

function Ensure-CloudWatchAgent {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential
    )
    
    Write-Host "Installing and configuring CloudWatch Agent on $ComputerName..." -ForegroundColor Yellow
    
    $url = $Config.Monitoring.AgentDownloadUrl
    $cfgPath = $Config.Monitoring.CloudWatchConfigPath

    try {
        Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
            param($url, $cfgPath, $computerName)
            
            $msi = "C:\Temp\amazon-cloudwatch-agent.msi"
            $agentPath = "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.exe"
            $configDir = "C:\ProgramData\Amazon\AmazonCloudWatchAgent"
            $configFile = "$configDir\config.json"
            
            # Create temp directory if it doesn't exist
            if (-not (Test-Path "C:\Temp")) { 
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null 
            }

            # Check if CloudWatch Agent is already installed
            if (-not (Test-Path $agentPath)) {
                Write-Host "CloudWatch Agent not found. Downloading from: $url"
                
                try {
                    # Download the CloudWatch Agent MSI
                    Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing -ErrorAction Stop
                    Write-Host "CloudWatch Agent downloaded successfully"
                    
                    # Install the CloudWatch Agent silently
                    Write-Host "Installing CloudWatch Agent..."
                    $installResult = Start-Process "msiexec.exe" -ArgumentList "/i `"$msi`" /qn /l*v C:\Temp\cloudwatch-install.log" -Wait -PassThru
                    
                    if ($installResult.ExitCode -ne 0) {
                        throw "CloudWatch Agent installation failed with exit code: $($installResult.ExitCode)"
                    }
                    
                    Write-Host "CloudWatch Agent installed successfully"
                    
                } catch {
                    throw "Failed to download or install CloudWatch Agent: $($_.Exception.Message)"
                }
            } else {
                Write-Host "CloudWatch Agent is already installed"
            }
            
            Write-Host "CloudWatch Agent configuration completed on $computerName"
            
        } -ArgumentList $url, $cfgPath, $ComputerName
        
        Write-Success "CloudWatch Agent successfully configured on $ComputerName"
        
    } catch {
        throw [System.Exception]::new("Failed to install CloudWatch Agent on $ComputerName : $($_.Exception.Message)")
    }
}

# Export functions
Export-ModuleMember -Function Ensure-CloudWatchAgent
