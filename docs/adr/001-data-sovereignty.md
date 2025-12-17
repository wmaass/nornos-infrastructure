# ADR-001: Patient Data Sovereignty Model

## Status

Accepted

## Date

2025-01-15

## Context

Nornos handles sensitive health data including genomics, wearable metrics, and medical records. We need to decide how patient data is stored, accessed, and controlled.

Key considerations:
- GDPR compliance (data subject rights)
- HIPAA requirements (for US expansion)
- Patient trust and adoption
- Technical complexity
- Operational costs

## Decision

We will implement a **Patient-Centric Data Sovereignty Model** where:

1. **Patients own their data** - All health data is stored in patient-controlled vaults
2. **Consent-based access** - Doctors can only access data with explicit, time-limited consent
3. **Field-level granularity** - Patients can grant access to specific data fields only
4. **Audit trail** - Every data access is logged and visible to patients
5. **Portability** - Patients can export all their data at any time

### Data Storage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PATIENT DOMAIN                          │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Patient Vault (per patient)            │   │
│  │  ┌───────────────┐  ┌───────────────┐              │   │
│  │  │ Health Data   │  │ Genomics      │              │   │
│  │  │ (encrypted)   │  │ (encrypted)   │              │   │
│  │  └───────────────┘  └───────────────┘              │   │
│  │  ┌───────────────┐  ┌───────────────┐              │   │
│  │  │ Wearables     │  │ Documents     │              │   │
│  │  │ (encrypted)   │  │ (encrypted)   │              │   │
│  │  └───────────────┘  └───────────────┘              │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                               │
│                            │ Patient-controlled key        │
│                            ▼                               │
└─────────────────────────────────────────────────────────────┘
                             │
                             │ Consent Token (time-limited)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    RELAY LAYER                             │
│  ┌─────────────────┐  ┌─────────────────┐                 │
│  │ Consent Manager │  │ Data Relay      │                 │
│  │ - Verify        │  │ - Decrypt       │                 │
│  │ - Time check    │  │ - Filter fields │                 │
│  │ - Audit log     │  │ - Serve         │                 │
│  └─────────────────┘  └─────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
                             │
                             │ Filtered, decrypted data
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    DOCTOR DOMAIN                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Doctor App (session only)              │   │
│  │  - No persistent patient data storage              │   │
│  │  - View during active session                      │   │
│  │  - Data cleared on logout                          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Consequences

### Positive

- **Trust**: Patients have full control, increasing adoption
- **Compliance**: Natural GDPR compliance (right to access, erasure, portability)
- **Security**: Breach impact limited to individual vaults
- **Differentiation**: Strong market positioning

### Negative

- **Complexity**: More complex than centralized storage
- **Performance**: Additional encryption/decryption overhead
- **Cost**: Per-patient storage infrastructure
- **Operations**: More complex backup/recovery

### Mitigations

- Use efficient encryption (AES-GCM with hardware acceleration)
- Implement aggressive caching in Relay layer
- Offer tiered storage (hot/warm/cold)
- Automate vault lifecycle management

## Alternatives Considered

### 1. Centralized Data Store
- **Pros**: Simpler, better performance
- **Cons**: Single point of failure, regulatory risk, trust issues
- **Rejected**: Doesn't align with privacy-first mission

### 2. Blockchain-based Storage
- **Pros**: Immutable audit trail, decentralized
- **Cons**: Scalability issues, cost, complexity
- **Rejected**: Over-engineered for our use case

### 3. Third-party Vault (e.g., Solid Pods)
- **Pros**: Established ecosystem, interoperability
- **Cons**: Dependency, limited customization
- **Rejected**: Need more control over implementation

## References

- GDPR Article 17 (Right to Erasure)
- GDPR Article 20 (Right to Data Portability)
- HIPAA Privacy Rule
- Apple Health Records approach
