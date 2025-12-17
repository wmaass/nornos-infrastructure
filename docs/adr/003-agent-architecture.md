# ADR-003: AI Agent Architecture

## Status

Accepted

## Date

2025-01-15

## Context

Nornos uses AI agents to provide personalized health recommendations. We need to decide:

- How agents are organized and orchestrated
- How they access patient data
- How results are cached and served
- How to scale agent processing

## Decision

We will implement a **Hierarchical Agent Architecture** with Meta-Agents coordinating Specialist Agents.

### Agent Hierarchy

```
                    ┌─────────────────────────────────────┐
                    │           META AGENTS               │
                    │   (Orchestration & Synthesis)       │
                    └─────────────────────────────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        │                             │                             │
        ▼                             ▼                             ▼
┌───────────────┐         ┌───────────────────┐         ┌───────────────────┐
│ Phenotype     │         │ Daily Status      │         │ Action Plan       │
│ Agent         │         │ Agent             │         │ Agent             │
│               │         │                   │         │                   │
│ Coordinates:  │         │ Coordinates:      │         │ Coordinates:      │
│ - Sleep       │         │ - Sleep           │         │ - All specialist  │
│ - Nutrition   │         │ - Nutrition       │         │   agents          │
│ - Stress      │         │ - Stress          │         │ - Phenotype       │
│ - Cardio      │         │                   │         │                   │
│ - PRS         │         │                   │         │                   │
└───────────────┘         └───────────────────┘         └───────────────────┘
        │                             │                             │
        └─────────────────────────────┼─────────────────────────────┘
                                      │
                    ┌─────────────────────────────────────┐
                    │         SPECIALIST AGENTS           │
                    │     (Domain-Specific Analysis)      │
                    └─────────────────────────────────────┘
                                      │
    ┌──────────┬──────────┬──────────┼──────────┬──────────┬──────────┐
    │          │          │          │          │          │          │
    ▼          ▼          ▼          ▼          ▼          ▼          ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│Sleep  │ │Nutri- │ │Stress │ │Cardio │ │PRS    │ │Social │ │ECG    │
│Agent  │ │tion   │ │Agent  │ │Risk   │ │Agent  │ │Agent  │ │Agent  │
└───────┘ └───────┘ └───────┘ └───────┘ └───────┘ └───────┘ └───────┘
```

### Agent Manifest Schema

Each agent declares its capabilities via a manifest:

```typescript
interface AgentManifest {
  id: string;                      // e.g., "phenotype_agent_v1"
  name: string;                    // Display name
  version: string;                 // Semantic version
  category: 'meta' | 'specialist' | 'screening' | 'utility';
  
  config: {
    timeout_ms: number;            // Max processing time
    requires_consent: boolean;     // Needs patient consent
    data_types: string[];          // Required data fields
    data_scope_days: number;       // How far back to look
  };
  
  capabilities: {
    streaming: boolean;            // Can stream results
    uses_llm: boolean;             // Uses language model
    visualization: boolean;        // Has visual output
  };
  
  depends_on: string[];            // Other agents required
}
```

### Agent Communication (MCP)

Agents communicate via the Model Context Protocol:

```
┌─────────────┐     MCP Request      ┌─────────────┐
│ Meta Agent  │─────────────────────▶│  Specialist │
│             │                      │  Agent      │
│             │◀─────────────────────│             │
└─────────────┘     MCP Response     └─────────────┘
```

### Caching Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                     CACHING LAYERS                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Layer 1: Client-side (sessionStorage)                     │
│  ├── TTL: 5 minutes                                        │
│  ├── Scope: Per browser session                            │
│  └── Pattern: Stale-while-revalidate                       │
│                                                             │
│  Layer 2: Redis (server-side)                              │
│  ├── TTL: 1 hour                                           │
│  ├── Scope: Per patient + agent                            │
│  └── Invalidation: On new data ingestion                   │
│                                                             │
│  Layer 3: Database (explanation_store)                     │
│  ├── TTL: 7 days                                           │
│  ├── Scope: LLM-generated explanations                     │
│  └── Purpose: Avoid redundant LLM calls                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Processing Flow

```
1. Request arrives
   └── Check client cache → HIT → Return immediately
   
2. Check server cache (Redis)
   └── HIT → Return + refresh in background
   
3. Check explanation cache (DB)
   └── HIT (for LLM parts) → Use cached explanations
   
4. Process agent
   ├── Fetch patient data via Relay
   ├── Run analysis algorithms
   ├── Generate LLM explanations (if needed)
   └── Cache results at all layers
   
5. Return results
```

## Consequences

### Positive

- **Modularity**: Agents can be updated independently
- **Reusability**: Specialist agents shared across meta-agents
- **Scalability**: Agents can scale independently
- **Caching**: Multiple cache layers for performance

### Negative

- **Complexity**: More moving parts
- **Latency**: Meta-agents wait for specialist agents
- **Debugging**: Harder to trace issues across agents

### Mitigations

- Comprehensive logging with correlation IDs
- Agent health checks and circuit breakers
- Background prefetching for common scenarios
- Timeout enforcement at each layer

## Scaling Configuration

| Agent Type | Min Replicas | Max Replicas | Scaling Trigger |
|------------|--------------|--------------|-----------------|
| Meta Agent | 2 | 10 | CPU > 70% |
| Specialist Agent | 2 | 20 | Queue depth |
| LLM Agent | 1 | 5 | GPU utilization |

## References

- Model Context Protocol (MCP) specification
- LangChain agent patterns
- Netflix microservices caching strategies
