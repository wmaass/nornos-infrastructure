# Nornos Platform Architecture

## Overview

The Nornos Health Platform is designed with the following core principles:

1. **Data Sovereignty** - Patients own and control their health data
2. **Privacy by Design** - Minimal data exposure, consent-based access
3. **Scalability** - Horizontal scaling for growing user base
4. **Resilience** - High availability with disaster recovery

## System Components

### Frontend Applications

#### Patient App (Next.js PWA)
- **Purpose**: Patient-facing application for health data management
- **Features**:
  - Health data visualization
  - Wearable device sync (Apple Health, Garmin, etc.)
  - Consent management (grant/revoke doctor access)
  - AI agent recommendations
- **Data Storage**: 
  - IndexedDB for offline capability
  - Encrypted sync to Patient Vault
- **Deployment**: Edge CDN (Vercel/Cloudflare)

#### Doctor App (Next.js SPA)
- **Purpose**: Healthcare provider interface
- **Features**:
  - Patient overview (with active consent)
  - AI-powered health analysis
  - Meta-agent recommendations
  - Treatment planning
- **Data Storage**: Session-only (no persistent patient data)
- **Deployment**: Edge CDN

### Backend Services

#### Auth Service
- **Technology**: Node.js / FastAPI
- **Responsibilities**:
  - User authentication (OAuth 2.0 / OIDC)
  - JWT token issuance
  - Session management
  - Multi-factor authentication
- **Database**: PostgreSQL (users, sessions)

#### Relay Server
- **Technology**: Python FastAPI
- **Responsibilities**:
  - Consent management
  - Data sharing between patients and doctors
  - Access control enforcement
  - Audit logging
- **Key Features**:
  - Time-limited data access tokens
  - Field-level consent (e.g., only HRV, not genomics)
  - Complete audit trail

#### Shared Data Server
- **Technology**: Node.js
- **Responsibilities**:
  - Patient health data storage
  - Data normalization
  - Query optimization
- **Database**: PostgreSQL with row-level security

#### Agent Service
- **Technology**: Python FastAPI
- **Responsibilities**:
  - AI agent orchestration
  - Meta-agent coordination
  - LLM integration
  - Recommendation generation
- **Agents**:
  - Phenotype Agent (personality/health profile)
  - Daily Status Agent (daily health summary)
  - Action Plan Agent (personalized recommendations)
  - Specialist Agents (sleep, nutrition, stress, etc.)

#### Vault Server
- **Technology**: Node.js
- **Responsibilities**:
  - Encrypted data storage
  - Key management
  - Backup/restore

### Data Stores

#### PostgreSQL
- **Purpose**: Primary relational database
- **Data**: Users, consents, health records, audit logs
- **Configuration**: 
  - Multi-AZ deployment
  - Point-in-time recovery
  - Row-level security

#### Redis
- **Purpose**: Caching and session storage
- **Data**: 
  - Session tokens
  - Agent result cache
  - Rate limiting counters
- **Configuration**: Redis Cluster mode

#### MinIO / S3
- **Purpose**: Object storage
- **Data**:
  - Genomic files
  - Medical documents
  - Wearable data exports
- **Configuration**: Encrypted at rest, versioning enabled

## Data Flow

### Patient Data Entry

```
Patient Device → Patient App → Vault Server → Encrypted Storage
                     ↓
              IndexedDB (offline cache)
```

### Doctor Data Access

```
Doctor App → Relay Server → Check Consent → Shared Data Server → Data
                ↓
         Audit Log Entry
```

### Agent Processing

```
Request → Agent Service → Relay Server → Get Consented Data
              ↓
         Process with AI/ML
              ↓
         Cache Results (Redis)
              ↓
         Return Recommendations
```

## Security Model

### Authentication

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client    │────▶│ Auth Service│────▶│  Database   │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       │              JWT Token
       ▼                   │
┌─────────────┐            │
│ API Gateway │◀───────────┘
└─────────────┘
       │
       │ Validated Request
       ▼
┌─────────────┐
│  Services   │
└─────────────┘
```

### Consent Model

```yaml
Consent:
  patient_id: "patient_123"
  granted_to: "doctor_456"
  data_fields:
    - hrv
    - sleep
    - activity
  excluded_fields:
    - genomics
    - mental_health
  valid_from: "2025-01-01T00:00:00Z"
  valid_until: "2025-03-01T00:00:00Z"
  purpose: "routine_checkup"
  revocable: true
```

### Encryption

| Layer | Method | Key Management |
|-------|--------|----------------|
| Transport | TLS 1.3 | AWS ACM |
| Database | AES-256 | AWS KMS |
| Object Storage | AES-256-GCM | AWS KMS |
| Patient Vault | AES-256-GCM | Patient-derived key |

## Scaling Strategy

### Horizontal Scaling

| Service | Scaling Trigger | Min | Max |
|---------|-----------------|-----|-----|
| Patient App | CDN (automatic) | - | - |
| Doctor App | CDN (automatic) | - | - |
| Auth Service | CPU > 70% | 2 | 10 |
| Relay Server | CPU > 70% | 3 | 20 |
| Agent Service | Queue depth > 100 | 2 | 50 |
| Shared Data | CPU > 70% | 2 | 10 |

### Database Scaling

- **Read Replicas**: 2 replicas per region
- **Connection Pooling**: PgBouncer
- **Sharding**: By patient_id (future)

## Disaster Recovery

### RPO / RTO

| Tier | RPO | RTO | Examples |
|------|-----|-----|----------|
| Critical | 0 | 15 min | Auth, Consent |
| High | 1 hour | 1 hour | Health Data |
| Medium | 24 hours | 4 hours | Analytics |

### Backup Strategy

- PostgreSQL: Continuous WAL archiving + daily snapshots
- Redis: RDB snapshots every 15 minutes
- S3/MinIO: Cross-region replication

## Monitoring & Observability

### Metrics (Prometheus)

- Request latency (p50, p95, p99)
- Error rates
- Database connections
- Cache hit rates
- Agent processing times

### Logging (ELK Stack)

- Structured JSON logs
- Correlation IDs for tracing
- PII redaction

### Alerting

- PagerDuty integration
- Slack notifications
- Escalation policies
