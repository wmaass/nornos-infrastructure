# Nornos Security Model

## Overview

This document describes the security architecture and practices for the Nornos Health Platform.

## Threat Model

### Assets to Protect

| Asset | Sensitivity | Impact of Breach |
|-------|-------------|------------------|
| Genomic Data | Critical | Permanent privacy violation |
| Health Records | High | Medical identity theft |
| Authentication Tokens | High | Account takeover |
| Consent Records | High | Unauthorized data access |
| Audit Logs | Medium | Cover-up of breaches |

### Threat Actors

1. **External Attackers** - Hackers seeking valuable health data
2. **Malicious Insiders** - Employees with system access
3. **Unauthorized Healthcare Providers** - Doctors without valid consent
4. **Data Brokers** - Entities seeking to aggregate health data

## Security Controls

### 1. Authentication & Authorization

#### Multi-Factor Authentication (MFA)
- Required for all users (patients and doctors)
- Supported methods: TOTP, WebAuthn, SMS (fallback)
- Session timeout: 30 minutes inactive

#### JWT Token Security
```yaml
JWT Configuration:
  algorithm: RS256
  access_token_ttl: 15 minutes
  refresh_token_ttl: 7 days
  issuer: https://auth.nornos.io
  audience: nornos-api
```

#### Role-Based Access Control (RBAC)
```
Roles:
  - patient: Can access own data, grant consents
  - doctor: Can access consented patient data
  - admin: System administration (no patient data access)
  - auditor: Read-only access to audit logs
```

### 2. Data Encryption

#### Encryption at Rest
- Database: AES-256 (AWS RDS encryption)
- Object Storage: AES-256-GCM (S3 server-side encryption)
- Patient Vault: AES-256-GCM with patient-derived keys

#### Encryption in Transit
- TLS 1.3 for all external connections
- mTLS between internal services (optional)
- Certificate management via AWS ACM / Let's Encrypt

#### Key Management
```
Key Hierarchy:
  - Master Key (AWS KMS)
    └── Data Encryption Keys (per service)
        └── Patient Keys (derived from patient secret)
```

### 3. Network Security

#### Network Segmentation
```
VPC Architecture:
  - Public Subnets: Load balancers only
  - Private Subnets: Application services
  - Database Subnets: Databases, no internet access
```

#### Kubernetes Network Policies
- Default deny all ingress
- Explicit allow rules for service-to-service communication
- See: kubernetes/base/network-policies.yaml

#### Web Application Firewall (WAF)
- AWS WAF with OWASP rule set
- Rate limiting: 100 requests/minute per IP
- Bot protection enabled

### 4. Consent Enforcement

#### Consent Validation Flow
```
1. Doctor requests patient data
2. Relay server checks consent:
   - Is consent active?
   - Is requested field in allowed fields?
   - Is requesting doctor the grantee?
   - Has consent expired?
3. If all checks pass, fetch and filter data
4. Log access in audit trail
5. Notify patient of access
```

#### Consent Audit
Every data access is logged:
```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "event": "data_access",
  "patient_id": "patient_123",
  "accessor_id": "doctor_456",
  "consent_id": "consent_789",
  "fields_accessed": ["hrv", "sleep"],
  "ip_address": "192.168.1.1",
  "user_agent": "Mozilla/5.0...",
  "success": true
}
```

### 5. Secure Development

#### Code Security
- Dependabot for dependency updates
- CodeQL for static analysis
- Trivy for container scanning
- Checkov for IaC security

#### Secrets Management
- AWS Secrets Manager for production secrets
- Kubernetes Sealed Secrets for git-stored secrets
- No secrets in environment variables (use mounted files)

#### CI/CD Security
- Branch protection on main
- Required code review
- Signed commits (recommended)
- Image signing with cosign

### 6. Incident Response

#### Detection
- CloudWatch Logs for centralized logging
- GuardDuty for threat detection
- Custom alerts for suspicious patterns:
  - Multiple failed logins
  - Unusual data access patterns
  - Consent violations attempts

#### Response Playbook
1. **Identify** - Determine scope of incident
2. **Contain** - Isolate affected systems
3. **Eradicate** - Remove threat
4. **Recover** - Restore normal operations
5. **Learn** - Post-incident review

#### Notification
- GDPR: 72-hour notification to authorities
- Affected users notified within 7 days

## Compliance

### GDPR
- [x] Data minimization
- [x] Purpose limitation
- [x] Right to access
- [x] Right to erasure
- [x] Data portability
- [x] Consent management
- [x] Data protection by design

### HIPAA (for US)
- [x] Access controls
- [x] Audit controls
- [x] Integrity controls
- [x] Transmission security
- [ ] BAA with cloud providers (required for production)

## Security Contacts

- Security Team: security@nornos.io
- Bug Bounty: https://hackerone.com/nornos (planned)
- Emergency: +49-XXX-XXXXXXX
