"""The agent's logic: the model picks tools, the tools run, and that repeats until it finishes."""
from typing import Annotated, TypedDict

from langchain_core.messages import AnyMessage
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode


class AgentError(Exception):
    pass


class State(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
    tokens: int


def build_graph(model, toolbox, max_tokens):
    bound_model = model.bind_tools(toolbox.tools)

    def agent(state):
        reply = bound_model.invoke(state["messages"])
        if not reply.usage_metadata:
            raise AgentError("The model reported no token usage, so the token limit can't be enforced.")
        tokens = state["tokens"] + reply.usage_metadata["total_tokens"]
        if tokens > max_tokens:
            raise AgentError(f"Token limit reached: {tokens} of {max_tokens}.")
        if not reply.tool_calls:
            raise AgentError("The model stopped without calling write_pr_section.")
        return {"messages": [reply], "tokens": tokens}

    def after_tools(_state):
        return END if toolbox.finished else "agent"

    graph = StateGraph(State)
    graph.add_node("agent", agent)
    # handle_tool_errors=False: a refusal is a normal result, but a bug in a tool should fail the run.
    graph.add_node("tools", ToolNode(toolbox.tools, handle_tool_errors=False))
    graph.add_edge(START, "agent")
    graph.add_edge("agent", "tools")
    graph.add_conditional_edges("tools", after_tools, ["agent", END])
    return graph.compile()
