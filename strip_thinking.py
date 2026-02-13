# Custom LiteLLM callback to strip thinking params for Ollama models
# These params are Anthropic-specific and cause errors with local models

from litellm.integrations.custom_logger import CustomLogger
from typing import Optional, Union
import litellm


class StripThinkingCallback(CustomLogger):
    """
    Strips Anthropic-specific 'thinking' parameters before sending to Ollama.
    """

    def log_pre_api_call(self, model, messages, kwargs):
        """Called before the API call - modify kwargs to remove thinking params."""
        # Only strip for ollama models
        if model and "ollama" in model.lower():
            # Remove thinking-related params
            thinking_params = [
                "thinking",
                "extended_thinking",
                "thinking_budget",
                "anthropic_beta",
            ]
            for param in thinking_params:
                if param in kwargs:
                    del kwargs[param]

            # Also check in extra_body if present
            if "extra_body" in kwargs and kwargs["extra_body"]:
                for param in thinking_params:
                    if param in kwargs["extra_body"]:
                        del kwargs["extra_body"][param]

            # Check metadata
            if "metadata" in kwargs and kwargs["metadata"]:
                for param in thinking_params:
                    if param in kwargs["metadata"]:
                        del kwargs["metadata"][param]


# Create instance for LiteLLM to use
strip_thinking_callback = StripThinkingCallback()
