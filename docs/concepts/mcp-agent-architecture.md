# MCP and the cluster agent

## What the Model Context Protocol is

MCP (Model Context Protocol) is a standard interface between an LLM
application and a "tool server" - a process that exposes a set of callable
tools (with typed input schemas) over a simple transport, most commonly
stdio (the server runs as a local subprocess) or streamable HTTP. The
protocol itself just standardizes tool discovery
(`list_tools`) and invocation (`call_tool`); the actual capability comes
entirely from whatever server implements it.

The alternative to MCP here would be hand-rolling tool functions directly
in application code and wiring them into an LLM's function-calling API -
that's more code to write and maintain per capability, and ties the tool
implementation to this one application. MCP separates those concerns: any
MCP-speaking client can use any MCP server.

## Why `agent/` uses AWS's own server instead of hand-rolled tools

`agent/agent_core.py` doesn't implement any cluster-reading logic itself.
It launches [`awslabs.eks-mcp-server`](https://github.com/awslabs/mcp/tree/main/src/eks-mcp-server)
- an official, AWS-maintained MCP server - as a `uvx` subprocess, and acts
purely as an MCP *client* plus an OpenAI tool-calling loop that forwards
whatever tools that server advertises. This means live-cluster-state
tools (`list_k8s_resources`, `get_pod_logs`, `get_k8s_events`) and
CloudWatch-history tools (`get_cloudwatch_logs`, `get_cloudwatch_metrics`)
come from one upstream server that AWS maintains, rather than this
project reimplementing AWS API calls it would then be responsible for
keeping correct.

## The tool-calling loop

`agent_core.ask()` is a standard agentic loop: send the conversation +
available tools to the model, and if it responds with tool calls, execute
each one against the MCP server, append the results as tool messages, and
send again - repeating until the model responds with plain content
instead of a tool call. Nothing here is MCP-specific; the loop would look
identical wired to any other tool source. What MCP contributes is that
`tools` is populated dynamically from `mcp_client.list_tools()` rather
than a hardcoded schema, so the agent automatically picks up whatever
tools a given version of `eks-mcp-server` exposes.

## Read-only by construction, not by convention

The server is launched **without** `--allow-write`
(`agent/agent_core.py`'s `EKS_MCP_SERVER` definition), which makes
`manage_k8s_resource`'s write path, `apply_yaml`, and
`generate_app_manifest` unavailable at the transport level - not just
something the system prompt asks the model to avoid. The system prompt
still states the constraint explicitly ("every tool here is read-only...
if asked to change anything, say you can't"), but the actual enforcement
is the missing CLI flag, not the instruction.

## Why live state and history are two distinct tool categories

A live Kubernetes API calls only knows the *current* state - `kubectl get
events` (and this server's `get_k8s_events`) reflects etcd, which only
retains Events for about an hour. `k8s/event-exporter.yaml` forwards every
Event to CloudWatch Logs (via the Fluent Bit daemonset the
`amazon-cloudwatch-observability` addon already runs), specifically so
questions like "was there a node drain a few hours ago" remain answerable
after etcd would have already dropped that Event. `app.py`'s live/history
badges reflect this same split in the UI - `list_k8s_resources`/
`get_pod_logs`/`get_k8s_events` are live, `get_cloudwatch_logs`/
`get_cloudwatch_metrics` are history - so it's visible at a glance which
kind of data any given answer actually came from.
