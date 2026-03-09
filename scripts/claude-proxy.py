#!/usr/bin/env python3
"""
claude-proxy: Local proxy that accepts OpenAI-compatible API requests
and forwards them through the Claude CLI using your Max subscription.

Usage:
    python3 scripts/claude-proxy.py [port]

Then configure your nvim-ai plugin to use:
    endpoint = "http://127.0.0.1:5757/v1/chat/completions"
"""

import json
import subprocess
import sys
import time
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 5757

# Map common model names to claude CLI model aliases
MODEL_MAP = {
    "anthropic/claude-sonnet-4.5": "sonnet",
    "anthropic/claude-opus-4.6": "opus",
    "anthropic/claude-haiku-4.5": "haiku",
    "claude-sonnet-4.5": "sonnet",
    "claude-opus-4.6": "opus",
    "claude-haiku-4.5": "haiku",
}


def format_messages(messages):
    """Extract system prompt and format conversation for claude -p."""
    system_prompt = None
    conversation = []

    for msg in messages:
        if msg["role"] == "system":
            system_prompt = msg["content"]
        else:
            conversation.append(msg)

    if not conversation:
        return system_prompt, ""

    # Single message: just pass it directly
    if len(conversation) == 1:
        return system_prompt, conversation[-1]["content"]

    # Multi-turn: format full history as the prompt
    parts = []
    for msg in conversation[:-1]:
        role = "Human" if msg["role"] == "user" else "Assistant"
        parts.append(f"{role}: {msg['content']}")

    # Last message is the current prompt
    parts.append(f"Human: {conversation[-1]['content']}")
    parts.append("Assistant:")

    return system_prompt, "\n\n".join(parts)


def resolve_model(model):
    """Map model names from OpenRouter/OpenAI format to claude CLI aliases."""
    if model in MODEL_MAP:
        return MODEL_MAP[model]
    # Pass through if already a claude alias or full model ID
    return model


class ClaudeProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(content_length))

        messages = body.get("messages", [])
        model = resolve_model(body.get("model", "sonnet"))

        system_prompt, prompt = format_messages(messages)

        cmd = ["claude", "-p", "--output-format", "json", "--tools", ""]
        cmd.extend(["--model", model])
        if system_prompt:
            cmd.extend(["--system-prompt", system_prompt])

        log(f"→ model={model}, {len(messages)} messages, prompt={len(prompt)} chars")

        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=300,
            )

            if result.returncode != 0:
                log(f"✗ claude exited with code {result.returncode}")
                self.send_error(502, f"Claude CLI error: {result.stderr[:200]}")
                return

            response_data = json.loads(result.stdout)

            if response_data.get("is_error"):
                log(f"✗ claude returned error: {response_data.get('result', '')[:100]}")
                self.send_error(502, response_data.get("result", "Unknown error"))
                return

            content = response_data.get("result", "")
            usage = response_data.get("usage", {})

            openai_response = {
                "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model,
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": content},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": usage.get("input_tokens", 0),
                    "completion_tokens": usage.get("output_tokens", 0),
                    "total_tokens": usage.get("input_tokens", 0)
                    + usage.get("output_tokens", 0),
                },
            }

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(openai_response).encode())

            log(
                f"← {usage.get('output_tokens', '?')} tokens, "
                f"{response_data.get('duration_ms', '?')}ms"
            )

        except subprocess.TimeoutExpired:
            log("✗ timed out after 300s")
            self.send_error(504, "Claude CLI timed out")
        except json.JSONDecodeError as e:
            log(f"✗ failed to parse response: {e}")
            self.send_error(502, "Failed to parse Claude CLI response")
        except Exception as e:
            log(f"✗ unexpected error: {e}")
            self.send_error(500, str(e))

    def do_GET(self):
        """Health check endpoint."""
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
            return
        self.send_error(404)

    def log_message(self, format, *args):
        # Suppress default request logging; we do our own
        pass


def log(msg):
    print(f"[claude-proxy] {msg}", flush=True)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    server = HTTPServer(("127.0.0.1", port), ClaudeProxyHandler)
    log(f"Listening on http://127.0.0.1:{port}")
    log(f"Endpoint: http://127.0.0.1:{port}/v1/chat/completions")
    log("Press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down")
        server.shutdown()
