# REQUIREMENTS.md

## SQL Server 2022 FCI HA Deployment Requirements

### Purpose
Deploy a highly available SQL Server 2022 Failover Cluster Instance (FCI) across two AWS Availability Zones using Windows Server Failover Clustering (WSFC) and Amazon FSx for Windows as shared storage.

### Core Requirements

#### Infrastructure
- AWS VPC with subnets in at least two Availability Zones
- AWS Managed Microsoft Active Directory or self-managed AD
- Amazon FSx for Windows File Server (Multi-AZ) with SMB shares
- Two Windows Server 2022 EC2 instances in different AZs
- Security Groups configured for cluster and SQL traffic

#### Software Components
- Windows Server 2022 Standard Edition
- SQL Server 2022 Standard Edition
- PowerShell 5.1 or PowerShell 7+
- AWS CLI v2 (optional, for S3 media source)

#### Network Requirements
- Domain connectivity between all components
- Required ports open in Security Groups:
  - TCP 1433 (SQL Server)
  - TCP 445 (SMB for FSx)
  - TCP 135 (RPC Endpoint Mapper)
  - TCP 49152-65535 (RPC Dynamic Ports)
  - UDP 3343 (Cluster Heartbeat)
  - ICMP (recommended for diagnostics)

#### Security Requirements
- Domain service account for SQL Server services (or gMSA)
- Domain administrator credentials for installation
- Appropriate permissions on FSx shares
- IAM instance profile with CloudWatch and SSM permissions

#### Storage Requirements
- FSx file system with minimum 1TB capacity
- Separate SMB shares for:
  - SQL data files (sqldata)
  - SQL backup files (sqlbackup)
  - Cluster witness (witness)

### Success Criteria
- Cluster successfully created with both nodes
- SQL FCI installed and operational
- Automatic failover working between AZs
- CloudWatch monitoring configured
- All validation tests passing

### Deliverables
- Complete PowerShell automation scripts
- JSON configuration system
- Comprehensive logging and error handling
- Validation and testing framework
- Documentation and runbooks
