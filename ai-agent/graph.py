"""The agent's logic: the model picks tools, the tools run, and that repeats until it finishes."""
from typing import Annotated, TypedDict

from langchain_core.messages import AnyMessage, ToolMessage
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages
from pydantic import ValidationError


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

    tools_by_name = {tool.name: tool for tool in toolbox.tools}

    def tools(state):
        # One at a time, in the reply's order, so a write lands before the Verify after it
        # and two Verify runs never overlap. Refusals and bad arguments go back to the model;
        # a bug in a tool fails the run.
        results = []
        for call in state["messages"][-1].tool_calls:
            tool = tools_by_name.get(call["name"])
            if toolbox.finished:
                content = "Refused: write_pr_section already ended this session."
            elif not tool:
                content = f"Refused: there is no tool named {call['name']}."
            else:
                try:
                    content = tool.invoke(call["args"])
                except ValidationError as error:
                    content = f"Refused: the arguments don't fit {call['name']}: {error}"
            results.append(ToolMessage(content=str(content), tool_call_id=call["id"], name=call["name"]))
        return {"messages": results}

    def after_tools(_state):
        return END if toolbox.finished else "agent"

    graph = StateGraph(State)
    graph.add_node("agent", agent)
    graph.add_node("tools", tools)
    graph.add_edge(START, "agent")
    graph.add_edge("agent", "tools")
    graph.add_conditional_edges("tools", after_tools, ["agent", END])
    return graph.compile()
