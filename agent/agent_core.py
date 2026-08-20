"""Shared engine for the cluster agent: bridges OpenAI's tool-calling to
AWS's own `awslabs.eks-mcp-server` (live k8s state AND CloudWatch history in
one official, read-only-by-default MCP server) - no hand-rolled tools, no
LangChain. UI-agnostic on purpose - `app.py` (Streamlit) is the only thing
that imports this and knows it's being shown on a screen.
"""

import json
import logging
import os

from mcp import Client, StdioServerParameters, stdio_client
from openai import AsyncOpenAI

CLUSTER = "clusterpilot"
REGION = "ap-south-1"
DEFAULT_MODEL = "gpt-4.1"

_AGENT_DIR = os.path.dirname(os.path.abspath(__file__))
AGENT_LOG_PATH = os.path.join(_AGENT_DIR, "agent.log")

# One clean, append-only audit trail answering "which tools did it call, in
# what order, with what args, to reach this answer" - not the subprocess's
# own internal chatter (that's suppressed at the source below via
# FASTMCP_LOG_LEVEL, and whatever still leaks through goes to this same
# file's ERROR lines, since a real subprocess error IS something worth
# keeping, not noise). A dedicated logger + explicit level, not
# logging.basicConfig, so importing this module never reconfigures whatever
# logging Streamlit itself has already set up.
_logger = logging.getLogger("cluster_agent")
_logger.setLevel(logging.INFO)
_logger.propagate = False
if not _logger.handlers:
    _handler = logging.FileHandler(AGENT_LOG_PATH)
    _handler.setFormatter(logging.Formatter("%(asctime)s | %(message)s", datefmt="%Y-%m-%d %H:%M:%S"))
    _logger.addHandler(_handler)

# Quiets the mcp client library's own chatter (e.g. validation-error spam
# from a protocol-version mismatch between this SDK and eks-mcp-server's -
# harmless, not worth logging every run) without touching the root logger,
# so it stays scoped to this package instead of silencing Streamlit's own.
logging.getLogger("mcp").setLevel(logging.ERROR)

# --allow-sensitive-data-access is required for get_pod_logs/get_k8s_events/
# get_cloudwatch_logs - deliberately NOT passing --allow-write, so
# manage_k8s_resource/apply_yaml/etc. stay read-only, same posture as every
# other agent in this project.
#
# env merges the full parent environment rather than replacing it - passing
# just {"AWS_REGION": REGION} would drop AWS_PROFILE (and everything else)
# from the uvx-launched subprocess, the exact class of bug Headlamp Desktop
# hit not inheriting shell env vars when launched from Finder/Dock.
#
# FASTMCP_LOG_LEVEL=ERROR is AWS's own quickstart config for this server -
# its documented "WARNING" default doesn't actually hold in practice.
EKS_MCP_SERVER = StdioServerParameters(
    command="uvx",
    args=["awslabs.eks-mcp-server@latest", "--allow-sensitive-data-access"],
    env={**os.environ, "AWS_REGION": REGION, "FASTMCP_LOG_LEVEL": "ERROR"},
)

SYSTEM_PROMPT = f"""You are a cluster assistant for the EKS cluster '{CLUSTER}' in region {REGION}.

Tools come from the AWS EKS MCP server - it covers both live cluster state
(list_k8s_resources, manage_k8s_resource for reads, get_pod_logs, get_k8s_events)
and CloudWatch history (get_cloudwatch_logs, get_cloudwatch_metrics). Always
pass cluster_name="{CLUSTER}" where a tool takes it.

Rules:
- "What's currently configured/running" -> the live k8s tools. Kubernetes
  Events from get_k8s_events are gone after ~1h.
- "What happened" / "did X change" / anything more than ~1h old -> get_cloudwatch_logs
  (log_type="application" is where kubernetes-event-exporter's forwarded
  Kubernetes Events live - node drains, evictions, scheduling failures,
  autoscaler scale up/down) or get_cloudwatch_metrics (ContainerInsights
  namespace - cluster_node_count, node_cpu_utilization, pod_memory_utilization,
  etc; use get_eks_metrics_guidance first if unsure of exact dimensions).
- If a question needs both ("what is it now vs before") -> use both kinds of tools.
- get_cloudwatch_logs's own tool description is wrong about filter_pattern - it
  says a bare word like "ERROR" works, but the server literally appends it as
  "| {{filter_pattern}}" to the query, so it MUST be a complete CloudWatch Logs
  Insights pipe stage, e.g. filter_pattern="filter @message like /drain/" (or
  "filter @message like /drain/ or @message like /evict/" to combine terms in
  one call) - not a bare word, that produces a MalformedQueryException.
- Always state what time range you actually *searched* - not the same thing
  as how far back real data exists. This cluster and its log group are only
  as old as this session; searching "the last 4 years" is not evidence
  anything happened further back than the log group's actual creation time.
- Never paste raw tool output (JSON blobs, field dumps) into your answer -
  always summarize the relevant parts in plain English.
- If you found nothing, say so plainly - never guess or fabricate an answer.
- Every tool here is read-only in this deployment (no --allow-write) - if
  asked to change anything, say you can't.
"""


def mcp_tool_to_openai(tool) -> dict:
    # tool.input_schema is documented as a pydantic model, but eks-mcp-server
    # (built against an older SDK) hands back a plain dict at runtime instead -
    # handle both rather than assume one shape.
    schema = tool.input_schema or {"type": "object", "properties": {}}
    if hasattr(schema, "model_dump"):
        schema = schema.model_dump(by_alias=True, exclude_none=True)
    return {
        "type": "function",
        "function": {
            "name": tool.name,
            "description": tool.description or "",
            "parameters": schema,
        },
    }


def _field(obj, name, default=None):
    """Some responses come back as pydantic models, others as plain dicts
    (same version-mismatch story as tool.input_schema) - try both."""
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


def extract_text(result) -> str:
    structured = _field(result, "structured_content")
    if structured is not None:
        return json.dumps(structured, default=str)
    parts = []
    for block in _field(result, "content", []) or []:
        text = _field(block, "text")
        if text is not None:
            parts.append(text)
    return "\n".join(parts) if parts else str(result)


async def ask(openai_client, mcp_client, model, question, history=None):
    """Runs one question to completion against an already-connected
    mcp_client. Returns (answer, updated_history, tool_calls) - tool_calls is
    a list of {"name", "args", "result"} dicts in call order, for the UI to
    render (and for the audit log) without re-deriving it from raw messages.
    """
    tools_result = await mcp_client.list_tools()
    tools = [mcp_tool_to_openai(t) for t in tools_result.tools]

    messages = history if history is not None else [{"role": "system", "content": SYSTEM_PROMPT}]
    messages.append({"role": "user", "content": question})
    _logger.info("QUESTION: %s", question)

    tool_calls = []
    while True:
        resp = await openai_client.chat.completions.create(model=model, messages=messages, tools=tools)
        msg = resp.choices[0].message
        messages.append(msg)
        if not msg.tool_calls:
            _logger.info("ANSWER: %s", msg.content)
            return msg.content, messages, tool_calls
        for call in msg.tool_calls:
            args = json.loads(call.function.arguments or "{}")
            try:
                result = await mcp_client.call_tool(call.function.name, args)
                content = extract_text(result)
            except Exception as e:
                content = f"Tool error: {e}"
            tool_calls.append({"name": call.function.name, "args": args, "result": content})
            _logger.info("TOOL %s(%s) -> %s", call.function.name, args, content[:300])
            messages.append({"role": "tool", "tool_call_id": call.id, "content": content[:8000]})


async def run_turn(question, model=DEFAULT_MODEL, history=None):
    """Opens a fresh MCP connection for this one turn (simpler than keeping
    a connection alive across Streamlit's rerun-on-every-interaction model;
    costs ~1-2s of `uvx` subprocess startup per question) and asks it."""
    openai_client = AsyncOpenAI()
    async with Client(stdio_client(EKS_MCP_SERVER)) as mcp_client:
        return await ask(openai_client, mcp_client, model, question, history)
