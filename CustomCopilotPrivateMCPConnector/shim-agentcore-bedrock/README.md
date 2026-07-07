# AgentCore MCP Shim (Variant A2)

A thin MCP adapter that fronts a single Amazon Bedrock AgentCore Runtime
hosting an MCP server, so a Power Platform custom connector can reach it
through an on-premises data gateway over private network paths.

This is the reference implementation for Variant A2 described in
[`docs/variant-a2-thin-mcp-adapter-spec.md`](../docs/variant-a2-thin-mcp-adapter-spec.md),
applied specifically to an AWS Bedrock AgentCore backend. Follow
[`docs/a2-howto-agentcore-bedrock.md`](../docs/a2-howto-agentcore-bedrock.md)
for the full step-by-step deployment guide this code accompanies.

## Layout

```
shim-agentcore-bedrock/
  app/
    main.py            FastAPI routes (health, servers, tools, resources, prompts)
    config.py           Config loading (SHIM_CONFIG_YAML / SHIM_CONFIG_PATH)
    mcp_protocol.py      MCP JSON-RPC envelope building + SSE flattening
    agentcore_client.py  boto3 bedrock-agentcore wrapper (InvokeAgentRuntime)
    session_manager.py   Per-caller runtimeSessionId/mcpSessionId cache
    auth.py              Caller authentication (Basic, Entra ID OAuth)
    authz.py             Allow-list checks + JSON schema argument validation
    audit.py             Structured JSON audit logging
    errors.py            Shared error model / HTTP status mapping
    models.py             Request/response Pydantic models
  config/
    server.example.yaml  Single-server registry template (copy, do not commit filled-in copy)
  infra/cloudformation/
    shim-agentcore-vpc-privatelink.yaml  PrivateLink endpoint + IAM + ECS Fargate + internal NLB
  tests/                 pytest suite (mcp_protocol, agentcore_client via botocore Stubber, API via TestClient)
  Dockerfile
  requirements.txt / requirements-dev.txt
```

## Local development

```powershell
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt -r requirements-dev.txt
Copy-Item config\server.example.yaml config\server.yaml   # then edit with your own ARN/tenant
$env:SHIM_CONFIG_PATH = "config\server.yaml"
$env:SHIM_BASIC_USERNAME = "dev"
$env:SHIM_BASIC_PASSWORD = "dev"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8080
```

## Running tests

```powershell
.\.venv\Scripts\python.exe -m pytest tests\ -v
```

Tests never call AWS: `test_agentcore_client.py` uses `botocore.stub.Stubber`
against a real (offline) `bedrock-agentcore` client so exception types stay
accurate to the live SDK, and `test_api.py` monkeypatches
`AgentCoreMcpClient.invoke`/`initialize_session` to exercise routing,
auth, and allow-list logic through FastAPI's `TestClient`.

## Validating the CloudFormation template

```powershell
.\.venv\Scripts\cfn-lint.exe infra\cloudformation\shim-agentcore-vpc-privatelink.yaml
```

This is static validation only (no AWS credentials required). It does not
replace a real `aws cloudformation deploy` / `--no-execute-changeset`
change-set review before applying to an account.

## Known scope limitations

See the module docstring in `app/main.py` for the two documented
simplifications in this reference implementation (per-tool timeout
enforcement is a ceiling check, not a literal socket-level override; no
built-in rate limiting/backpressure -- front with an ALB/WAF rate rule or
extend `SessionManager` if you need `429 QuotaExceeded` enforcement at this
layer).
