# Custom MCP Private Connector

Design and reference implementation for exposing Model Context Protocol
(MCP) servers to Power Platform (Power Apps, Power Automate, Copilot
Studio) through a governed custom connector, over private network paths
only — never a public endpoint.

Start here: **[docs/exec.md](./docs/exec.md)** — a one-page executive
summary and architecture overview of the recommended approach (Variant A2).

## Documentation

| Document | What it covers |
| --- | --- |
| [docs/exec.md](./docs/exec.md) | Executive summary and high-level architecture of Variant A2 — start here. |
| [docs/power-platform-mcp-private-proxy-connector-spec.md](./docs/power-platform-mcp-private-proxy-connector-spec.md) | Parent spec: goals, reference architecture, connectivity patterns (Variant A1 vs. A2), connector action model, error model, and why a direct gateway-to-MCP connection isn't viable. |
| [docs/variant-a2-thin-mcp-adapter-spec.md](./docs/variant-a2-thin-mcp-adapter-spec.md) | Detailed design of Variant A2: scope, request lifecycle, MCP session management, streaming (SSE) flattening, authentication model, configuration shape, security summary and hardening checklist, and the migration path to Variant A1. |
| [docs/a2-howto-agentcore-bedrock.md](./docs/a2-howto-agentcore-bedrock.md) | Step-by-step deployment guide for Variant A2 on AWS using Amazon Bedrock AgentCore Runtime: architecture, prerequisites, a feasibility pre-flight checklist, deployment steps 1-8, observability, design trade-offs/caveats (including latency and AI-assistant grounding on curated data), AWS-specific security hardening, and troubleshooting. |
| [shim-agentcore-bedrock/README.md](./shim-agentcore-bedrock/README.md) | Reference implementation: a FastAPI-based thin MCP adapter fronting Amazon Bedrock AgentCore. Layout, local development setup, running tests, and validating the CloudFormation template. |

## Reference implementation

[`shim-agentcore-bedrock/`](./shim-agentcore-bedrock/) is a working,
tested implementation of Variant A2 for an MCP server hosted in Amazon
Bedrock AgentCore Runtime, including:

- A FastAPI adapter (`app/`) implementing the connector action model,
  MCP JSON-RPC translation, session management, SSE flattening, auth,
  allow-list enforcement, and audit logging.
- A pytest suite (`tests/`) covering the MCP protocol layer, the AgentCore
  client (via `botocore.stub.Stubber`, no live AWS calls), and the API
  routing/auth/allow-list behavior end to end.
- CloudFormation (`infra/cloudformation/`) provisioning the PrivateLink
  endpoint, IAM roles, ECS Fargate service, and internal load balancer.

See its [README](./shim-agentcore-bedrock/README.md) for local setup and
test instructions.

## Status

Draft. See individual documents for status and open questions.
