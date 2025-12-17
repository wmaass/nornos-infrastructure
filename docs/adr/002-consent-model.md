# ADR-002: Consent-Based Data Access Model

## Status

Accepted

## Date

2025-01-15

## Context

When doctors need to access patient data, we need a secure, auditable, and user-friendly consent mechanism. The system must balance:

- Patient control and transparency
- Doctor workflow efficiency
- Regulatory compliance
- Technical feasibility

## Decision

We will implement a **Granular, Time-Limited Consent Model** with the following characteristics:

### Consent Structure

```typescript
interface Consent {
  // Identity
  id: string;                    // Unique consent ID
  patient_id: string;            // Patient granting consent
  granted_to: string;            // Doctor/organization receiving access
  
  // Scope
  data_fields: string[];         // Specific fields allowed
  excluded_fields: string[];     // Explicitly denied fields
  purpose: ConsentPurpose;       // Why access is needed
  
  // Time bounds
  valid_from: DateTime;          // Start of access window
  valid_until: DateTime;         // End of access window
  
  // Control
  revocable: boolean;            // Can be revoked anytime
  revoked_at?: DateTime;         // When revoked (if applicable)
  
  // Audit
  created_at: DateTime;
  created_via: 'app' | 'qr' | 'api';
  audit_trail: AuditEntry[];
}

type ConsentPurpose = 
  | 'routine_checkup'
  | 'specialist_consultation'
  | 'emergency'
  | 'research'
  | 'second_opinion';
```

### Consent Workflow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Patient App   │     │  Relay Server   │     │   Doctor App    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │  1. Create Consent    │                       │
         │──────────────────────▶│                       │
         │                       │                       │
         │  2. Consent ID/QR     │                       │
         │◀──────────────────────│                       │
         │                       │                       │
         │                       │  3. Request Access    │
         │                       │◀──────────────────────│
         │                       │                       │
         │                       │  4. Validate Consent  │
         │                       │─────────┐             │
         │                       │         │             │
         │                       │◀────────┘             │
         │                       │                       │
         │                       │  5. Return Data       │
         │                       │──────────────────────▶│
         │                       │                       │
         │  6. Access Notification                       │
         │◀──────────────────────│                       │
         │                       │                       │
```

### Data Field Categories

| Category | Fields | Default Access |
|----------|--------|----------------|
| **Basic** | name, age, gender | Included |
| **Vitals** | hrv, heart_rate, blood_pressure | Included |
| **Activity** | steps, sleep, exercise | Included |
| **Metabolic** | glucose, hba1c, cholesterol | Requires consent |
| **Genomic** | prs_scores, variants | Requires explicit consent |
| **Mental** | mood, stress, anxiety | Requires explicit consent |
| **Sensitive** | hiv_status, psychiatric | Never shared |

### Emergency Access

For emergency situations:

```typescript
interface EmergencyAccess {
  type: 'emergency';
  reason: string;
  duration_hours: 4;  // Fixed short duration
  requires_justification: true;
  auto_audit: true;
  patient_notification: 'immediate';
}
```

## Consequences

### Positive

- **Patient Control**: Granular, understandable consent
- **Compliance**: Clear audit trail for regulators
- **Trust**: Patients see exactly what's shared
- **Flexibility**: Different consent levels for different purposes

### Negative

- **Friction**: Doctors must request consent each time
- **Complexity**: Many consent states to manage
- **UX Challenge**: Make consent easy without being "click-through"

### Mitigations

- Quick consent via QR code in doctor's office
- Template consents for common scenarios
- Clear, jargon-free consent descriptions
- Easy bulk revocation

## API Design

### Grant Consent

```http
POST /api/v1/consent/grant
Authorization: Bearer <patient_token>

{
  "granted_to": "doctor_456",
  "data_fields": ["hrv", "sleep", "activity", "glucose"],
  "valid_days": 30,
  "purpose": "routine_checkup"
}
```

### Check Consent

```http
GET /api/v1/consent/check?patient_id=123&doctor_id=456&field=glucose
Authorization: Bearer <doctor_token>

Response:
{
  "has_consent": true,
  "valid_until": "2025-02-15T00:00:00Z",
  "fields_allowed": ["hrv", "sleep", "activity", "glucose"]
}
```

### Revoke Consent

```http
POST /api/v1/consent/revoke
Authorization: Bearer <patient_token>

{
  "consent_id": "consent_789",
  "reason": "No longer needed"
}
```

## References

- GDPR Article 7 (Conditions for consent)
- eHealth consent frameworks (IHE, HL7 FHIR Consent)
- Apple Health sharing model
