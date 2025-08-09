# SQL Server 2022 FCI on Windows Server Standard across Two AWS AZs (AWS EC2 + FSx Multi-AZ)

## 1. Overview

This document is a complete, repeatable runbook and automation package for deploying **SQL Server 2022 Failover Cluster Instance (FCI)** on **Windows Server Standard** across **two AWS Availability Zones**, using **Amazon FSx for Windows Multi-AZ** as shared storage.

The automation is **JSON-driven**, **idempotent**, and **fully logged**.

---

## 2. Architecture

```
VPC
├─ Subnet-A (AZ-a)            ── Subnet-B (AZ-b)
│   └─ EC2: SQLNODE1              └─ EC2: SQLNODE2
│      Windows 2022                  Windows 2022
│      SQL FCI node                  SQL FCI node
│
└─ FSx for Windows File Server (Multi-AZ)  ← shared storage + file witness
    └─ SMB shares: \\fsx\sqldata, \\fsx\sqlbackup, \\fsx\witness
```

- **Client connections** use the SQL FCI **virtual network name (VNN)** with `MultiSubnetFailover=True`.
- **Failover Cluster Instance (FCI)** provides instance-level high availability with automatic failover.

---

## 3. Requirements & Assumptions

- AWS account with permissions for EC2, FSx, Directory Service, CloudWatch
- Windows Server 2022 AMI (Base)
- AWS Managed Microsoft AD or self-managed AD
- Security Group rules allowing:
  - TCP 1433 (SQL), TCP 445 (SMB), TCP 135 (RPC), TCP 49152–65535 (RPC dynamic), UDP 3343 (Cluster HB), ICMP optional
- SQL Server 2022 Standard media (ISO, UNC path, or S3)
- Service account or gMSA for SQL Server and Agent services

---

## 4. Folder Structure

```powershell
# Create folder structure
mkdir d:\dev2\clients\sqlserverHA
mkdir d:\dev2\clients\sqlserverHA\modules
mkdir d:\dev2\clients\sqlserverHA\config
mkdir d:\dev2\clients\sqlserverHA\logs
mkdir d:\dev2\clients\sqlserverHA\monitoring

# Create empty files (Windows-friendly 'touch' equivalent)
type nul > d:\dev2\clients\sqlserverHA\Start-FciDeployment.ps1
type nul > d:\dev2\clients\sqlserverHA\config\settings.json
type nul > d:\dev2\clients\sqlserverHA\monitoring\cloudwatch-config.json
type nul > d:\dev2\clients\sqlserverHA\modules\Common.psm1
type nul > d:\dev2\clients\sqlserverHA\modules\Aws.psm1
type nul > d:\dev2\clients\sqlserverHA\modules\WindowsCluster.psm1
type nul > d:\dev2\clients\sqlserverHA\modules\SqlFci.psm1
type nul > d:\dev2\clients\sqlserverHA\modules\Monitoring.psm1
type nul > d:\dev2\clients\sqlserverHA\modules\Validate.psm1
```

## 5. PowerShell Prerequisites

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force

# AWS Tools
Install-Module -Name AWS.Tools.Installer -Scope CurrentUser -Force
Install-AWSToolsModule AWS.Tools.Common,AWS.Tools.CloudWatch,AWS.Tools.CloudWatchLogs -Scope CurrentUser -Force
```

## 6. Configuration Files

### 6.1 settings.json

The main configuration file that drives the entire deployment:

```json
{
  "Project": {
    "Name": "sql-fci-aws",
    "Region": "us-west-2",
    "VpcId": "vpc-xxxxxxxx",
    "Subnets": {
      "AzA": "subnet-aaaaaaa",
      "AzB": "subnet-bbbbbbb"
    },
    "SecurityGroupId": "sg-xxxxxxxx",
    "KeyPairName": "my-keypair",
    "IamInstanceProfile": "EC2-SSM-CloudWatch"
  },
  "Directory": {
    "Id": "d-xxxxxxxxxx",
    "DnsName": "corp.example.com",
    "NetbiosName": "CORP"
  },
  "EC2": {
    "InstanceType": "m6i.xlarge",
    "AmiId": "",
    "Node1Name": "SQLNODE1",
    "Node2Name": "SQLNODE2",
    "AdminUser": "Administrator"
  },
  "SQL": {
    "FciName": "SQLFCI01",
    "InstanceName": "MSSQLSERVER",
    "ServiceAccount": "CORP\\sqlsvc",
    "ServicePasswordSecretName": "",
    "ServicePasswordPlaintext": "",
    "Collation": "SQL_Latin1_General_CP1_CI_AS",
    "ProductKey": "",
    "MediaSource": {
      "Type": "S3",
      "S3Uri": "s3://my-bucket/sql/SQLServer2022",
      "UncPath": "\\\\fsx\\sqlmedia\\SQLServer2022",
      "LocalIsoPath": "D:\\en_sql_server_2022.iso"
    }
  },
  "FSx": {
    "DnsAlias": "fsx",
    "Shares": {
      "Data": "sqldata",
      "Backup": "sqlbackup",
      "Witness": "witness"
    }
  },
  "Paths": {
    "SqlDataRoot": "\\\\fsx\\sqldata",
    "SqlBackupRoot": "\\\\fsx\\sqlbackup",
    "SqlTempDbRoot": "\\\\fsx\\sqldata\\tempdb"
  },
  "Cluster": {
    "Name": "sql-fci-cluster",
    "FileWitnessPath": "\\\\fsx\\witness",
    "DnsTtlSeconds": 120,
    "RegisterAllProvidersIP": 1
  },
  "Monitoring": {
    "CloudWatchNamespace": "SQL-FCI",
    "CreateSampleAlarms": true,
    "CloudWatchConfigPath": ".\\monitoring\\cloudwatch-config.json",
    "AgentDownloadUrl": "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi"
  },
  "Validation": {
    "FailoverTest": true,
    "ReconnectTest": true,
    "TestDatabase": "FciValidationDb"
  }
}
```

### 6.2 cloudwatch-config.json

CloudWatch agent configuration for monitoring SQL Server and cluster metrics:

```json
{
  "metrics": {
    "append_dimensions": { "InstanceId": "${aws:InstanceId}" },
    "aggregation_dimensions": [["InstanceId"]],
    "metrics_collected": {
      "LogicalDisk": {
        "measurement": ["% Free Space", "Avg. Disk sec/Read", "Avg. Disk sec/Write"],
        "resources": ["*"],
        "interval": 60
      },
      "Memory": {
        "measurement": ["% Committed Bytes In Use"],
        "metrics_collection": 60
      },
      "SQLServer:SQL Statistics": {
        "measurement": ["Batch Requests/sec", "SQL Compilations/sec", "SQL Re-Compilations/sec"],
        "resources": ["*"],
        "interval": 60
      },
      "SQLServer:Buffer Manager": {
        "measurement": ["Page life expectancy", "Buffer cache hit ratio"],
        "resources": ["*"],
        "interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "windows_events": {
        "collect_list": [
          { "event_name": "Application", "levels": ["ERROR", "WARNING", "INFORMATION"] },
          { "event_name": "System", "levels": ["ERROR", "WARNING"] },
          { "event_name": "Microsoft-Windows-FailoverClustering/Operational", "levels": ["ERROR", "WARNING", "INFORMATION"] }
        ]
      }
    },
    "log_stream_name": "{instance_id}",
    "force_flush_interval": 15
  }
}
```

## 7. PowerShell Modules

- **Common.psm1** – logging, config loader, retry, remote exec
- **Aws.psm1** – FSx validation, AWS CLI check
- **WindowsCluster.psm1** – WSFC install/config/quorum/DNS/firewall
- **SqlFci.psm1** – SQL FCI install on Node1, Add Node2
- **Monitoring.psm1** – CloudWatch agent install/config
- **Validate.psm1** – Failover & connectivity tests

## 8. Orchestrator Script

**Start-FciDeployment.ps1** drives the process:

1. Load configuration from settings.json
2. Prompt for domain admin credentials
3. Validate FSx paths
4. Install Failover Clustering features on both nodes
5. Create or verify WSFC
6. Configure File Share Witness
7. Tune DNS for multi-subnet
8. Ensure firewall rules
9. Install SQL FCI on Node1
10. Add Node2 to FCI
11. Start SQL service on active node
12. Install CloudWatch Agent (optional)
13. Validate SQL connectivity and perform failover test

## 9. Running the Deployment

```powershell
cd d:\dev2\clients\sqlserverHA
.\Start-FciDeployment.ps1
```

- **Re-run safe**: The script checks each step before running it again.
- **Logs**: Stored in `.\logs\deploy-YYYYMMDD_HHMMSS.log` with transcript.

## 10. Validation

- **Connectivity test** inserts a row into a test table via sqlcmd
- **Failover test** moves SQL cluster group to secondary node, then verifies online status and connectivity

## 11. Security & Best Practices

- Use gMSA or Secrets Manager for SQL service account password retrieval
- Secure FSx shares with least-privilege ACLs
- Scope inbound traffic via AWS Security Groups
- Enable Cluster-Aware Updating (CAU) for patching

## 12. Connection Strings

Use the FCI name in your applications:

```
Server=SQLFCI01; Database=master; Integrated Security=True; MultiSubnetFailover=True
```

## 13. Next Steps / Extensions

- Automate EC2 and FSx provisioning
- Integrate Secrets Manager for credentials
- Add CloudFormation/Terraform wrapper
- Enhance monitoring with CloudWatch alarms
