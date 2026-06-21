---
name: mcp-development
description: >-
  Model Context Protocol (MCP) development. Building MCP servers in Python and TypeScript,
  defining tools/resources/prompts, transport layers (stdio, SSE), configuration in Claude Code,
  security, testing, and common patterns. Activate when building custom MCP servers, integrating
  external data sources with Claude, or debugging MCP connectivity issues.
effort: high
---

# MCP Development — Model Context Protocol

## What is MCP

Model Context Protocol (MCP) is an open standard that defines how LLM applications (hosts) connect to external tools and data sources (servers). Think of it as USB-C for AI -- a universal connector between LLMs and the outside world.

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Host** | The LLM application (Claude Code, Claude Desktop, custom app) |
| **Client** | Protocol handler inside the host — manages connection to one server |
| **Server** | External process that exposes tools, resources, and prompts |
| **Transport** | Communication layer: stdio (local process) or SSE (HTTP remote) |

### Architecture

```
Host (Claude Code)
  |
  |--- Client 1 ---[stdio]--- Server A (Python process)
  |--- Client 2 ---[stdio]--- Server B (Node.js process)
  |--- Client 3 ---[SSE]---- Server C (remote HTTP)
```

Each client maintains a 1:1 connection with exactly one server. The host aggregates capabilities from all connected servers.

### Three Primitives

| Primitive | Direction | Description |
|-----------|-----------|-------------|
| **Tools** | Server -> LLM decides when to call | Functions the model can invoke (e.g., search, query DB) |
| **Resources** | Server -> Client reads | Read-only data endpoints (e.g., file contents, DB schemas) |
| **Prompts** | Server -> User selects | Reusable prompt templates with parameters |

---

## Building MCP Servers in Python

### Installation

```bash
pip install mcp
# Or with CLI tools for testing
pip install "mcp[cli]"
```

### Minimal Server — One Tool

```python
# server.py
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent
import json

server = Server("my-tool-server")


@server.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="greet",
            description="Greet a user by name.",
            inputSchema={
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "The name to greet.",
                    }
                },
                "required": ["name"],
            },
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    if name == "greet":
        user_name = arguments.get("name", "World")
        return [TextContent(type="text", text=f"Hello, {user_name}!")]
    raise ValueError(f"Unknown tool: {name}")


async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

### Server with Multiple Tools

```python
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent
import json
import subprocess

server = Server("devops-tools")


@server.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="disk_usage",
            description="Check disk usage for a given path.",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Filesystem path to check.",
                        "default": "/",
                    }
                },
            },
        ),
        Tool(
            name="process_count",
            description="Count running processes, optionally filtered by name.",
            inputSchema={
                "type": "object",
                "properties": {
                    "filter": {
                        "type": "string",
                        "description": "Process name filter (grep pattern).",
                    }
                },
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    if name == "disk_usage":
        path = arguments.get("path", "/")
        # Input validation
        if ".." in path or not path.startswith("/"):
            return [TextContent(type="text", text="Error: path must be absolute, no '..'")]
        result = subprocess.run(
            ["df", "-h", path], capture_output=True, text=True, timeout=10
        )
        return [TextContent(type="text", text=result.stdout)]

    elif name == "process_count":
        filter_pattern = arguments.get("filter", "")
        if filter_pattern:
            result = subprocess.run(
                ["pgrep", "-c", filter_pattern],
                capture_output=True, text=True, timeout=10,
            )
            count = result.stdout.strip() or "0"
        else:
            result = subprocess.run(
                ["ps", "aux"], capture_output=True, text=True, timeout=10
            )
            count = str(len(result.stdout.strip().split("\n")) - 1)
        return [TextContent(type="text", text=f"Process count: {count}")]

    raise ValueError(f"Unknown tool: {name}")


async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

### Resources — Read-Only Data

```python
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Resource, TextContent
import json

server = Server("db-schema-server")


@server.list_resources()
async def list_resources() -> list[Resource]:
    return [
        Resource(
            uri="schema://main/tables",
            name="Database Tables",
            description="List of all tables in the main database.",
            mimeType="application/json",
        ),
        Resource(
            uri="schema://main/tables/users",
            name="Users Table Schema",
            description="Column definitions for the users table.",
            mimeType="application/json",
        ),
    ]


@server.read_resource()
async def read_resource(uri: str) -> str:
    if uri == "schema://main/tables":
        return json.dumps({"tables": ["users", "orders", "products"]})
    elif uri == "schema://main/tables/users":
        return json.dumps({
            "table": "users",
            "columns": [
                {"name": "id", "type": "INTEGER", "primary_key": True},
                {"name": "email", "type": "VARCHAR(255)", "unique": True},
                {"name": "created_at", "type": "TIMESTAMP"},
            ],
        })
    raise ValueError(f"Unknown resource: {uri}")
```

### Prompts — Reusable Templates

```python
from mcp.types import Prompt, PromptArgument, PromptMessage, TextContent

@server.list_prompts()
async def list_prompts() -> list[Prompt]:
    return [
        Prompt(
            name="code_review",
            description="Generate a code review for a given file.",
            arguments=[
                PromptArgument(
                    name="language",
                    description="Programming language.",
                    required=True,
                ),
                PromptArgument(
                    name="code",
                    description="The code to review.",
                    required=True,
                ),
                PromptArgument(
                    name="focus",
                    description="Review focus: security, performance, readability.",
                    required=False,
                ),
            ],
        )
    ]


@server.get_prompt()
async def get_prompt(name: str, arguments: dict) -> list[PromptMessage]:
    if name == "code_review":
        focus = arguments.get("focus", "general")
        return [
            PromptMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=(
                        f"Review this {arguments['language']} code with focus on {focus}.\n\n"
                        f"```{arguments['language']}\n{arguments['code']}\n```\n\n"
                        "Provide: issues found, severity, fix suggestions."
                    ),
                ),
            )
        ]
    raise ValueError(f"Unknown prompt: {name}")
```

### FastMCP — High-Level API

```python
# FastMCP provides a decorator-based API (higher level than raw Server)
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("my-server")


@mcp.tool()
async def search_docs(query: str, limit: int = 10) -> str:
    """Search documentation by query string.

    Args:
        query: Search query
        limit: Maximum number of results (default: 10)
    """
    # FastMCP auto-generates inputSchema from type hints + docstring
    results = await do_search(query, limit)
    return json.dumps(results)


@mcp.resource("config://app/settings")
async def get_settings() -> str:
    """Current application settings."""
    return json.dumps({"debug": False, "version": "1.2.3"})


@mcp.prompt()
async def debug_prompt(error_message: str) -> str:
    """Generate a debugging prompt for an error."""
    return f"Debug this error and suggest fixes:\n\n{error_message}"


# Run with stdio transport
mcp.run()
```

---

## Building MCP Servers in TypeScript

### Installation

```bash
npm init -y
npm install @modelcontextprotocol/sdk
npm install -D typescript @types/node
```

### Minimal TypeScript Server

```typescript
// src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "example-server",
  version: "1.0.0",
});

// Define a tool
server.tool(
  "calculate",
  "Perform basic arithmetic operations.",
  {
    operation: z.enum(["add", "subtract", "multiply", "divide"]),
    a: z.number().describe("First operand"),
    b: z.number().describe("Second operand"),
  },
  async ({ operation, a, b }) => {
    let result: number;
    switch (operation) {
      case "add": result = a + b; break;
      case "subtract": result = a - b; break;
      case "multiply": result = a * b; break;
      case "divide":
        if (b === 0) {
          return { content: [{ type: "text", text: "Error: Division by zero" }] };
        }
        result = a / b;
        break;
    }
    return {
      content: [{ type: "text", text: `Result: ${result}` }],
    };
  }
);

// Define a resource
server.resource(
  "status",
  "status://server",
  async (uri) => ({
    contents: [
      {
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify({ status: "running", uptime: process.uptime() }),
      },
    ],
  })
);

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("MCP server running on stdio");
}

main().catch(console.error);
```

### TypeScript Build and Run

```json
// package.json
{
  "name": "my-mcp-server",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "@types/node": "^20.0.0"
  }
}
```

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "strict": true,
    "esModuleInterop": true
  },
  "include": ["src/**/*"]
}
```

---

## Configuration in Claude Code

### settings.json — stdio Transport

```json
{
  "mcpServers": {
    "my-python-server": {
      "command": "python3",
      "args": ["/absolute/path/to/server.py"],
      "env": {
        "DATABASE_URL": "postgresql://localhost/mydb"
      }
    },
    "my-node-server": {
      "command": "node",
      "args": ["/absolute/path/to/dist/index.js"]
    },
    "uvx-server": {
      "command": "uvx",
      "args": ["my-mcp-package"]
    },
    "npx-server": {
      "command": "npx",
      "args": ["-y", "@org/mcp-server-name"]
    }
  }
}
```

### settings.json — SSE Transport (Remote)

```json
{
  "mcpServers": {
    "remote-server": {
      "url": "https://my-server.example.com/sse",
      "headers": {
        "Authorization": "Bearer my-token"
      }
    }
  }
}
```

### Configuration File Locations

| Scope | Path | Purpose |
|-------|------|---------|
| Project | `.claude/settings.json` | Shared with team via git |
| Project local | `.claude/settings.local.json` | Personal overrides (gitignored) |
| User | `~/.claude/settings.json` | Global, all projects |

Settings are merged: project < project local < user. MCP servers from all scopes are combined.

### Environment Variables in MCP Config

```json
{
  "mcpServers": {
    "db-server": {
      "command": "python3",
      "args": ["/path/to/db_server.py"],
      "env": {
        "DB_HOST": "localhost",
        "DB_PORT": "5432",
        "DB_NAME": "production",
        "DB_PASSWORD": "${DB_PASSWORD}"
      }
    }
  }
}
```

---

## Transport Layers

### stdio (Local Process)

```
Host <--stdin/stdout--> Server Process
```

- Default for local servers
- Host spawns server as child process
- Communication via stdin (requests) and stdout (responses)
- stderr is available for server logging (does not interfere with protocol)
- Best for: local tools, file system access, development

### SSE (Server-Sent Events / HTTP)

```
Host <--HTTP POST/SSE--> Remote Server
```

- For remote/shared servers
- Client sends requests via HTTP POST
- Server streams responses via SSE
- Supports authentication headers
- Best for: shared team servers, cloud-hosted tools, production

### Choosing Transport

| Factor | stdio | SSE |
|--------|-------|-----|
| Latency | Lowest (local) | Network dependent |
| Setup | Just a command | HTTP server needed |
| Security | Process isolation | Network auth required |
| Sharing | Per-machine | Multi-user |
| Debugging | stderr logging | HTTP logging |

---

## Security

### Input Validation

```python
import re
from pathlib import Path

ALLOWED_PATHS = [Path("/home/user/projects"), Path("/tmp")]

def validate_path(path_str: str) -> Path:
    """Validate and sanitize file paths."""
    path = Path(path_str).resolve()

    # Prevent path traversal
    if ".." in path.parts:
        raise ValueError("Path traversal detected")

    # Check against allowlist
    if not any(path.is_relative_to(allowed) for allowed in ALLOWED_PATHS):
        raise ValueError(f"Path {path} is outside allowed directories")

    return path


def validate_query(query: str) -> str:
    """Sanitize database queries."""
    # Block dangerous patterns
    dangerous = re.compile(
        r"(DROP|DELETE|TRUNCATE|ALTER|GRANT|REVOKE)\s",
        re.IGNORECASE,
    )
    if dangerous.search(query):
        raise ValueError("Destructive SQL operations are not allowed")
    return query
```

### Permission Scoping

```python
@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    if name == "read_file":
        path = validate_path(arguments["path"])

        # Read-only: never write, delete, or execute
        if not path.is_file():
            return [TextContent(type="text", text=f"Error: {path} is not a file")]

        content = path.read_text(encoding="utf-8")

        # Truncate large files to prevent context overflow
        if len(content) > 50_000:
            content = content[:50_000] + "\n... [truncated at 50,000 chars]"

        return [TextContent(type="text", text=content)]
```

### Secrets Management

```python
# NEVER expose secrets in tool responses
import os

# Good: use environment variables
DB_PASSWORD = os.environ.get("DB_PASSWORD")

# Good: mask secrets in responses
def mask_connection_string(conn_str: str) -> str:
    return re.sub(r"password=[^&\s]+", "password=***", conn_str)

# Bad: returning raw credentials
# return [TextContent(type="text", text=f"Password is {DB_PASSWORD}")]
```

### Rate Limiting

```python
import time
from collections import defaultdict

class RateLimiter:
    def __init__(self, max_calls: int = 10, window_seconds: int = 60):
        self.max_calls = max_calls
        self.window = window_seconds
        self.calls: dict[str, list[float]] = defaultdict(list)

    def check(self, tool_name: str) -> bool:
        now = time.time()
        self.calls[tool_name] = [
            t for t in self.calls[tool_name] if now - t < self.window
        ]
        if len(self.calls[tool_name]) >= self.max_calls:
            return False
        self.calls[tool_name].append(now)
        return True

rate_limiter = RateLimiter(max_calls=20, window_seconds=60)

@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    if not rate_limiter.check(name):
        return [TextContent(type="text", text=f"Rate limit exceeded for {name}. Try again later.")]
    # ... handle tool call
```

---

## Testing MCP Servers

### MCP Inspector

```bash
# Install and run the inspector (interactive testing UI)
npx @modelcontextprotocol/inspector python3 /path/to/server.py

# For Node.js servers
npx @modelcontextprotocol/inspector node /path/to/dist/index.js

# Inspector opens a web UI where you can:
# - List available tools, resources, prompts
# - Call tools with custom arguments
# - View raw protocol messages
```

### Manual Testing with Python Client

```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def test_server():
    server_params = StdioServerParameters(
        command="python3",
        args=["/path/to/server.py"],
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # List tools
            tools = await session.list_tools()
            print(f"Available tools: {[t.name for t in tools.tools]}")

            # Call a tool
            result = await session.call_tool("greet", {"name": "⟦ user_name ⟧"})
            print(f"Result: {result.content[0].text}")

            # List resources
            resources = await session.list_resources()
            print(f"Available resources: {[r.uri for r in resources.resources]}")

            # Read a resource
            content = await session.read_resource("schema://main/tables")
            print(f"Resource content: {content.contents[0].text}")

import asyncio
asyncio.run(test_server())
```

### Unit Testing Tool Handlers

```python
import pytest
from unittest.mock import AsyncMock

# Test tool logic directly without MCP transport
@pytest.mark.asyncio
async def test_greet_tool():
    result = await call_tool("greet", {"name": "⟦ user_name ⟧"})
    assert len(result) == 1
    assert result[0].text == "Hello, ⟦ user_name ⟧!"

@pytest.mark.asyncio
async def test_greet_tool_default():
    result = await call_tool("greet", {})
    assert "World" in result[0].text

@pytest.mark.asyncio
async def test_unknown_tool():
    with pytest.raises(ValueError, match="Unknown tool"):
        await call_tool("nonexistent", {})
```

---

## Common Patterns

### Pattern 1: Database Query Server

```python
from mcp.server.fastmcp import FastMCP
import asyncpg
import json
import os

mcp = FastMCP("postgres-query")

pool = None

async def get_pool():
    global pool
    if pool is None:
        pool = await asyncpg.create_pool(os.environ["DATABASE_URL"])
    return pool


@mcp.tool()
async def query(sql: str, params: list | None = None) -> str:
    """Execute a read-only SQL query against the database.

    Args:
        sql: SQL SELECT query (write operations are blocked)
        params: Optional query parameters for parameterized queries
    """
    # Security: block write operations
    sql_upper = sql.strip().upper()
    if not sql_upper.startswith("SELECT") and not sql_upper.startswith("WITH"):
        return "Error: Only SELECT queries are allowed"

    pool = await get_pool()
    try:
        rows = await pool.fetch(sql, *(params or []))
        results = [dict(row) for row in rows[:100]]  # Cap at 100 rows
        return json.dumps(results, default=str)
    except Exception as e:
        return f"Query error: {e}"


@mcp.resource("schema://tables")
async def list_tables() -> str:
    """List all tables in the database."""
    pool = await get_pool()
    rows = await pool.fetch(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
    )
    return json.dumps([row["table_name"] for row in rows])


mcp.run()
```

### Pattern 2: API Wrapper Server

```python
from mcp.server.fastmcp import FastMCP
import httpx
import os
import json

mcp = FastMCP("github-api")

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
BASE_URL = "https://api.github.com"


async def github_request(path: str, params: dict | None = None) -> dict:
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"{BASE_URL}{path}",
            headers={
                "Authorization": f"Bearer {GITHUB_TOKEN}",
                "Accept": "application/vnd.github+json",
            },
            params=params,
            timeout=30.0,
        )
        response.raise_for_status()
        return response.json()


@mcp.tool()
async def list_issues(repo: str, state: str = "open", limit: int = 10) -> str:
    """List issues for a GitHub repository.

    Args:
        repo: Repository in owner/name format (e.g., 'langchain-ai/langchain')
        state: Filter by state: open, closed, all
        limit: Maximum number of issues to return
    """
    issues = await github_request(
        f"/repos/{repo}/issues",
        params={"state": state, "per_page": min(limit, 100)},
    )
    return json.dumps([
        {"number": i["number"], "title": i["title"], "state": i["state"]}
        for i in issues
    ])


@mcp.tool()
async def get_file(repo: str, path: str, ref: str = "main") -> str:
    """Get file contents from a GitHub repository.

    Args:
        repo: Repository in owner/name format
        path: File path within the repository
        ref: Branch or commit SHA (default: main)
    """
    import base64
    data = await github_request(
        f"/repos/{repo}/contents/{path}",
        params={"ref": ref},
    )
    if data.get("encoding") == "base64":
        content = base64.b64decode(data["content"]).decode("utf-8")
        # Truncate large files
        if len(content) > 30_000:
            content = content[:30_000] + "\n... [truncated]"
        return content
    return json.dumps(data)


mcp.run()
```

### Pattern 3: File System Server (Scoped)

```python
from mcp.server.fastmcp import FastMCP
from pathlib import Path
import json

mcp = FastMCP("project-files")

# Scope to a specific directory
PROJECT_ROOT = Path("/home/user/projects/my-project").resolve()


def safe_path(relative: str) -> Path:
    """Resolve path within project root only."""
    full = (PROJECT_ROOT / relative).resolve()
    if not full.is_relative_to(PROJECT_ROOT):
        raise ValueError(f"Access denied: {relative} is outside project root")
    return full


@mcp.tool()
async def read_file(path: str) -> str:
    """Read a file from the project directory.

    Args:
        path: Relative path from project root
    """
    full_path = safe_path(path)
    if not full_path.is_file():
        return f"Error: {path} is not a file"
    content = full_path.read_text(encoding="utf-8")
    if len(content) > 50_000:
        content = content[:50_000] + "\n... [truncated at 50,000 chars]"
    return content


@mcp.tool()
async def list_files(path: str = ".", pattern: str = "*") -> str:
    """List files in a project directory.

    Args:
        path: Relative directory path (default: project root)
        pattern: Glob pattern to filter files (default: all)
    """
    dir_path = safe_path(path)
    if not dir_path.is_dir():
        return f"Error: {path} is not a directory"
    files = sorted(dir_path.glob(pattern))[:200]  # Cap results
    return json.dumps([
        str(f.relative_to(PROJECT_ROOT)) for f in files if f.is_file()
    ])


@mcp.tool()
async def search_files(query: str, glob: str = "**/*.py") -> str:
    """Search file contents in the project.

    Args:
        query: Text to search for (case-insensitive)
        glob: File pattern to search in (default: Python files)
    """
    matches = []
    for filepath in PROJECT_ROOT.glob(glob):
        if not filepath.is_file() or filepath.stat().st_size > 1_000_000:
            continue
        try:
            content = filepath.read_text(encoding="utf-8")
            for i, line in enumerate(content.splitlines(), 1):
                if query.lower() in line.lower():
                    matches.append({
                        "file": str(filepath.relative_to(PROJECT_ROOT)),
                        "line": i,
                        "text": line.strip()[:200],
                    })
                    if len(matches) >= 50:
                        return json.dumps(matches)
        except (UnicodeDecodeError, PermissionError):
            continue
    return json.dumps(matches)


mcp.run()
```

---

## Decision Guide

| Need | Approach |
|------|----------|
| Local tool for one user | Python/TS stdio server |
| Shared team tool | SSE server behind auth |
| Quick prototype | FastMCP decorators |
| Production database access | DB query server with read-only enforcement |
| External API integration | API wrapper server with rate limiting |
| File browsing | Scoped file server with path validation |
| Complex multi-step workflow | Combine multiple tools in one server |
| Testing during development | MCP Inspector + unit tests |

---

## Anti-Patterns

| Anti-Pattern | Why It Fails | Fix |
|--------------|-------------|-----|
| Unbounded tool responses | Floods LLM context, causes context rot | Truncate/paginate all responses (cap at ~30K chars) |
| No input validation | Path traversal, SQL injection, command injection | Validate/sanitize all inputs before use |
| Returning raw errors with stack traces | Leaks internal details, confuses LLM | Return clean error messages, log stack traces to stderr |
| Tool that does everything | LLM cannot reliably choose between 20+ sub-operations | One tool per atomic operation |
| No error handling in tool calls | Crashes kill server, no retry possible | Wrap every tool in try/except, return error as TextContent |
| Hardcoded secrets in server code | Security risk, hard to rotate | Use environment variables passed via MCP config |
| Missing resource caps | DB queries returning millions of rows | Always LIMIT queries and cap result arrays |
| Server with write access and no confirmation | Destructive operations without human review | Separate read and write tools, require confirmation param |
| Testing only via Claude | Slow, non-deterministic, expensive | Unit test tool handlers + MCP Inspector |
| SSE server without authentication | Anyone on network can call tools | Add token-based auth, validate on every request |

---

## References

- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)
- [MCP Inspector](https://github.com/modelcontextprotocol/inspector)
- [Building MCP Servers Guide](https://modelcontextprotocol.io/quickstart/server)
- [Claude Code MCP Configuration](https://docs.anthropic.com/en/docs/claude-code/mcp)
- [MCP Server Registry](https://github.com/modelcontextprotocol/servers)
