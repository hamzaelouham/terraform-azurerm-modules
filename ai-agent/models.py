"""The chat model. Any endpoint that speaks the OpenAI API and supports tool calling works."""
import os

from langchain_openai import ChatOpenAI


class SettingsError(Exception):
    pass


def required(name):
    value = os.environ.get(name, "")
    if not value:
        raise SettingsError(f"{name} is not set; see the propose job in check-registry.yml.")
    return value


def get_model():
    # An unset GitHub repo variable arrives as an empty string, and the client would use it.
    if not os.environ.get("OPENAI_BASE_URL"):
        os.environ.pop("OPENAI_BASE_URL", None)
    # No temperature: some OpenAI-compatible models reject anything but their default.
    return ChatOpenAI(
        model=required("AI_AGENT_MODEL"),
        api_key=required("OPENAI_API_KEY"),
        timeout=300,
    )
