# TODO.md

## SQL Server FCI HA Deployment - Implementation Checklist

### Stage 1: Foundation Setup ✅
- [x] Create project directory structure
- [x] Design JSON configuration system
- [x] Implement logging and error handling framework
- [x] Create PowerShell module structure
- [x] Document requirements and architecture

### Stage 2: Core Modules (IN PROGRESS)
- [x] Common.psm1 - Basic utilities and logging
- [x] Aws.psm1 - AWS service validation
- [ ] WindowsCluster.psm1 - Complete WSFC management
- [ ] SqlFci.psm1 - SQL Server FCI installation
- [ ] Monitoring.psm1 - CloudWatch integration
- [ ] Validate.psm1 - Testing and validation

### Stage 3: Integration & Testing
- [ ] Complete main orchestration script
- [ ] Implement comprehensive error handling
- [ ] Add retry logic for transient failures
- [ ] Create validation test suite
- [ ] Test failover scenarios

### Stage 4: Security & Best Practices
- [ ] Implement AWS Secrets Manager integration
- [ ] Add gMSA support for service accounts
- [ ] Enhance security group validation
- [ ] Add certificate-based authentication options
- [ ] Implement least-privilege access patterns

### Stage 5: Monitoring & Alerting
- [ ] Complete CloudWatch agent deployment
- [ ] Create custom metrics for SQL FCI
- [ ] Implement automated alerting
- [ ] Add performance baseline collection
- [ ] Create operational dashboards

### Stage 6: Documentation & Training
- [ ] Complete user guide
- [ ] Create troubleshooting guide
- [ ] Document operational procedures
- [ ] Add recovery procedures
- [ ] Create training materials

### Priority Tasks This Sprint
1. Complete WindowsCluster.psm1 module
2. Implement SQL FCI installation logic
3. Add comprehensive validation framework
4. Test end-to-end deployment process
5. Document troubleshooting procedures

### Known Issues to Address
- Password handling needs Secrets Manager integration
- Need better error messages for common failures
- Add pre-flight checks for all prerequisites
- Implement rollback procedures for failed deployments
