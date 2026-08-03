# Project documentation

The documents in this directory define the chart's approved behavior and maintenance boundary.

## Core documents

- [Specification](spec.md) — goals, user stories, implementation decisions, and acceptance strategy.
- [Architecture](architecture.md) — project resources, shared rules, values structure, and dependencies.
- [Warehouse](warehouse.md) — standalone Freight discovery and artifact assembly.
- [Chart completeness audit](chart-completeness-audit.md) — implemented contracts, evidence, and external prerequisites.

## Stage designs

1. [Prepare release](stages/prepare-release.md)
2. [Dev](stages/dev.md)
3. [Integration](stages/integration.md)
4. [Pre-production](stages/pre-production.md)
5. [Production](stages/production.md)

Each Stage document is the design authority for its corresponding Helm template. `AGENTS.md` contains the condensed non-negotiable implementation rules.
