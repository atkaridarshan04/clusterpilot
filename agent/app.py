"""Streamlit chat UI for the cluster agent - live k8s state + CloudWatch
history in one conversation. Run with:

    streamlit run app.py

All the actual logic (MCP connection, tool-calling loop, system prompt)
lives in agent_core.py - this file only renders it.
"""

import asyncio
import json
import time

import streamlit as st

from agent_core import CLUSTER, DEFAULT_MODEL, REGION, run_turn

# Display name for the UI - distinct from CLUSTER, which is the literal EKS
# cluster/resource name (lowercase, matches Terraform) and always shown
# verbatim wherever that matters (system prompt, captions below).
APP_NAME = "ClusterPilot"

MAX_SESSIONS = 5

# Which category a tool belongs to, purely for the badge next to it below -
# agent_core/eks-mcp-server don't need this, it's UI sugar so you can see
# the live-vs-history split this whole project is built around at a glance.
# Colors below (LIVE_COLOR/HISTORY_COLOR) are the same split carried into
# the theme - not arbitrary accent colors, the taxonomy itself is the palette.
LIVE_TOOLS = {"list_k8s_resources", "manage_k8s_resource", "get_pod_logs", "get_k8s_events"}
HISTORY_TOOLS = {"get_cloudwatch_logs", "get_cloudwatch_metrics", "get_eks_metrics_guidance"}
LIVE_COLOR = "#4FA8FF"
HISTORY_COLOR = "#B98BFF"
MUTED_COLOR = "#7D8BA8"

SUGGESTED_QUESTIONS = [
    "What's the memory request and limit configured on the wordpress deployment?",
    "Were there any node drains, evictions, or scheduling failures recently?",
    "Has the ContainerInsights cluster_node_count metric changed in the last few hours?",
]

# page_icon accepts Streamlit's built-in Material Symbols shorthand
# (":material/<name>:") - a real icon set, not an emoji standing in for one.
st.set_page_config(page_title=f"{APP_NAME} Agent", page_icon=":material/hub:")

# A deliberate type scale, not scattered overrides - each rule below is one
# rung: display (h1) > section (sidebar h3) > body (chat prose) > caption
# (muted metadata) > code (tool args/results) > badge (smallest, a label not
# prose). Space Grotesk for display/section only, kept to headings so it
# never fights body readability; Inter for everything else. Both loaded
# once here since .streamlit/config.toml's `font` only accepts the three
# generic families, not arbitrary web fonts. Selectors use stable
# data-testid attributes rather than Streamlit's internal hashed classes,
# except `h1`/`.stApp`/`.stButton`/`.stChatMessage`, which have been stable
# across recent versions.
st.markdown(
    f"""
    <style>
    @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@600;700&family=Inter:wght@400;500;600&display=swap');

    .stApp {{ font-family: 'Inter', sans-serif; }}

    /* Display - the page title, the one place the display face earns its keep */
    h1 {{
        font-family: 'Space Grotesk', sans-serif !important;
        font-weight: 700 !important;
        font-size: 2rem !important;
        letter-spacing: 0.01em;
        margin-bottom: 0.1rem !important;
    }}

    /* Section - sidebar heading, one step down from the display size */
    section[data-testid="stSidebar"] h3 {{
        font-family: 'Space Grotesk', sans-serif;
        font-weight: 600;
        font-size: 1.05rem;
        letter-spacing: 0.01em;
    }}

    section[data-testid="stSidebar"] {{
        border-right: 1px solid #22304D;
    }}

    /* Sidebar nav (new chat / session list) - compact and nav-like, not
       sized like a primary action button */
    section[data-testid="stSidebar"] .stButton > button {{
        font-size: 0.85rem;
        padding: 0.35rem 0.75rem;
    }}

    /* Body - the actual conversation prose, sized for comfortable reading,
       no letter-spacing (that's a display-only device) */
    [data-testid="stChatMessageContent"] p,
    [data-testid="stChatMessageContent"] li {{
        font-size: 0.95rem;
        line-height: 1.55;
    }}

    .stChatMessage {{ margin-bottom: 0.4rem; }}

    /* Caption - deliberately smaller and muted, metadata never competes
       with body text */
    [data-testid="stCaptionContainer"] {{
        font-size: 0.8rem !important;
        color: {MUTED_COLOR} !important;
    }}

    /* Code - tool args/results are data, monospace stays default; sized
       down one notch from body for density since these can run long */
    div[data-testid="stCodeBlock"] pre {{
        font-size: 0.8rem !important;
    }}

    /* Badge - the smallest rung, a label rather than prose */
    .tool-badge {{
        display: inline-block;
        padding: 1px 9px;
        border-radius: 999px;
        font-size: 0.7rem;
        font-weight: 600;
        letter-spacing: 0.03em;
        vertical-align: middle;
    }}
    </style>
    """,
    unsafe_allow_html=True,
)


def new_session():
    return {"title": None, "chat_history": None, "display_history": []}


if "sessions" not in st.session_state:
    first_id = str(time.time())
    st.session_state.sessions = {first_id: new_session()}
    st.session_state.current_id = first_id


def start_new_chat():
    sid = str(time.time())
    st.session_state.sessions[sid] = new_session()
    st.session_state.current_id = sid
    # keep only the most recent MAX_SESSIONS - oldest first in dict order
    ids = list(st.session_state.sessions.keys())
    for old_id in ids[:-MAX_SESSIONS]:
        del st.session_state.sessions[old_id]


with st.sidebar:
    st.markdown(f"### {APP_NAME}")
    st.caption(f"`{CLUSTER}`  ·  {REGION}")

    if st.button("New chat", icon=":material/add_comment:", use_container_width=True):
        start_new_chat()
        st.rerun()

    st.markdown("---")
    st.caption(f"Recent chats (last {MAX_SESSIONS})")
    for sid in reversed(list(st.session_state.sessions.keys())):
        title = st.session_state.sessions[sid]["title"] or "New chat"
        is_current = sid == st.session_state.current_id
        if st.button(
            title,
            key=f"session-{sid}",
            use_container_width=True,
            type="primary" if is_current else "secondary",
        ):
            st.session_state.current_id = sid
            st.rerun()

    st.markdown("---")
    with st.expander("How it works", icon=":material/help:"):
        st.markdown(
            f'<span class="tool-badge" style="background:{LIVE_COLOR}26; color:{LIVE_COLOR};">live</span> '
            "tools read current cluster state via the Kubernetes API<br>"
            f'<span class="tool-badge" style="background:{HISTORY_COLOR}26; color:{HISTORY_COLOR};">history</span> '
            "tools read CloudWatch Logs/Metrics for anything more than ~1h old "
            "(past etcd's Event TTL)<br><br>"
            "Every answer shows exactly which tools it called to reach it.",
            unsafe_allow_html=True,
        )

session = st.session_state.sessions[st.session_state.current_id]

st.title(APP_NAME)
st.caption(
    f"EKS cluster `{CLUSTER}` ({REGION}) - live Kubernetes state via "
    "`awslabs.eks-mcp-server`, plus CloudWatch history from "
    "`k8s/event-exporter.yaml` and Container Insights."
)


def tool_badge(name: str) -> str:
    if name in LIVE_TOOLS:
        color, label = LIVE_COLOR, "live"
    elif name in HISTORY_TOOLS:
        color, label = HISTORY_COLOR, "history"
    else:
        color, label = MUTED_COLOR, "other"
    style = f"background:{color}26; color:{color};"  # 26 = ~15% alpha hex suffix
    return f'<span class="tool-badge" style="{style}">{label}</span>'


def render_tool_calls(tool_calls, container):
    if not tool_calls:
        container.caption("Answered directly, no tools needed.")
        return
    for call in tool_calls:
        container.markdown(
            f"{tool_badge(call['name'])} &nbsp; :material/build: **`{call['name']}`**",
            unsafe_allow_html=True,
        )
        container.code(json.dumps(call["args"], indent=2), language="json")
        result = call["result"]
        preview = result if len(result) <= 500 else result[:500] + "..."
        container.text(preview)


# Replay everything so far in this session - Streamlit reruns this whole
# script on every interaction, so past turns only stay visible if redrawn.
# No custom `avatar=` - Streamlit's own default user/assistant icons render
# cleanly without needing an emoji stand-in.
for turn in session["display_history"]:
    with st.chat_message("user"):
        st.markdown(turn["question"])
    with st.chat_message("assistant"):
        label = f"Used {len(turn['tool_calls'])} tool call(s)" if turn["tool_calls"] else "Answered directly"
        with st.status(label, state="complete"):
            render_tool_calls(turn["tool_calls"], st)
        st.markdown(turn["answer"])

question = None
if not session["display_history"]:
    st.markdown("**Try asking:**")
    for suggestion in SUGGESTED_QUESTIONS:
        if st.button(suggestion, use_container_width=True):
            question = suggestion

question = st.chat_input("Ask about live cluster state or history...") or question

if question:
    if session["title"] is None:
        session["title"] = question[:40] + ("..." if len(question) > 40 else "")

    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("assistant"):
        with st.status("Thinking...", state="running") as status:
            answer, new_history, tool_calls = asyncio.run(
                run_turn(question, model=DEFAULT_MODEL, history=session["chat_history"])
            )
            label = f"Used {len(tool_calls)} tool call(s)" if tool_calls else "Answered directly"
            status.update(label=label, state="complete")
            render_tool_calls(tool_calls, status)
        st.markdown(answer)

    session["chat_history"] = new_history
    session["display_history"].append({"question": question, "tool_calls": tool_calls, "answer": answer})
    st.rerun()
