#!/usr/bin/env python3
"""
claude-proxy: Local proxy that accepts OpenAI-compatible API requests
and forwards them through the Claude CLI using your Pro or Max subscription.

Usage:
    python3 scripts/claude-proxy.py [port]

Then configure your nvim-ai plugin to use:
    endpoint = "http://127.0.0.1:5757/v1/chat/completions"
"""

import json
import os
import select
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

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
    def send_json_error(self, status, message):
        """Send an error response as JSON instead of HTML."""
        error_body = {
            "error": {
                "message": message,
                "type": "proxy_error",
                "code": status,
            }
        }
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(error_body).encode())

    TIMEOUT = 300

    def run_claude(self, cmd, prompt):
        """Run `claude` and kill it if the HTTP client disconnects.

        Returns (returncode, stdout, stderr), or None if the client went away
        (in which case the claude process group has been terminated).
        Raises subprocess.TimeoutExpired if claude exceeds TIMEOUT seconds.
        """
        # start_new_session=True puts claude in its own process group so we can
        # kill it *and* any children it spawns with one os.killpg().
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )

        # Drain stdin/stdout/stderr on a worker thread. communicate() handles
        # writing the prompt and reading both pipes to EOF, so a large response
        # can't fill a pipe buffer and deadlock claude.
        io_result = {}

        def _communicate():
            try:
                io_result["stdout"], io_result["stderr"] = proc.communicate(input=prompt)
            except Exception as e:  # pragma: no cover - defensive
                io_result["error"] = e

        worker = threading.Thread(target=_communicate, daemon=True)
        worker.start()

        deadline = time.monotonic() + self.TIMEOUT
        cancelled = False
        timed_out = False

        while worker.is_alive():
            # A readable client socket whose peek returns empty means curl sent
            # FIN (the user cancelled). Any real pipelined data (won't happen
            # for our one-shot requests) just falls through and we keep waiting.
            try:
                readable, _, _ = select.select([self.connection], [], [], 0.1)
                if readable and self.connection.recv(1, socket.MSG_PEEK) == b"":
                    cancelled = True
                    break
            except OSError:
                cancelled = True
                break

            if time.monotonic() > deadline:
                timed_out = True
                break

        if cancelled or timed_out:
            self._kill_group(proc, signal.SIGTERM)
            worker.join(timeout=2)
            if worker.is_alive():
                self._kill_group(proc, signal.SIGKILL)
                worker.join(timeout=2)

        if cancelled:
            return None
        if timed_out:
            raise subprocess.TimeoutExpired(cmd, self.TIMEOUT)

        return proc.returncode, io_result.get("stdout", ""), io_result.get("stderr", "")

    @staticmethod
    def _kill_group(proc, sig):
        try:
            os.killpg(os.getpgid(proc.pid), sig)
        except (ProcessLookupError, PermissionError):
            pass

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_json_error(404, "Not found")
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
            outcome = self.run_claude(cmd, prompt)

            if outcome is None:
                # Client cancelled; claude has been killed and the connection
                # is gone, so there's nothing to send back.
                log("✗ cancelled by client — killed claude")
                return

            returncode, stdout, stderr = outcome

            if returncode != 0:
                stderr = (stderr or "").strip()
                log(f"✗ claude exited with code {returncode}")
                if "login" in stderr.lower() or "auth" in stderr.lower():
                    self.send_json_error(401, f"Claude CLI auth error — try running: claude login\n{stderr[:200]}")
                else:
                    self.send_json_error(502, f"Claude CLI error: {stderr[:200]}")
                return

            response_data = json.loads(stdout)

            if response_data.get("is_error"):
                log(f"✗ claude returned error: {response_data.get('result', '')[:100]}")
                self.send_json_error(502, response_data.get("result", "Unknown error"))
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
            self.send_json_error(504, "Claude CLI timed out")
        except json.JSONDecodeError as e:
            log(f"✗ failed to parse response: {e}")
            self.send_json_error(502, "Failed to parse Claude CLI response")
        except Exception as e:
            log(f"✗ unexpected error: {e}")
            self.send_json_error(500, str(e))

    def do_GET(self):
        """Health check endpoint."""
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
            return
        self.send_json_error(404, "Not found")

    def log_message(self, format, *args):
        # Suppress default request logging; we do our own
        pass


def log(msg):
    print(f"[claude-proxy] {msg}", flush=True)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    # ThreadingHTTPServer so each request gets its own thread: cancel detection
    # (see ClaudeProxyHandler.run_claude) polls the client socket while claude
    # runs, and concurrent requests don't block each other.
    server = ThreadingHTTPServer(("127.0.0.1", port), ClaudeProxyHandler)
    log(f"Listening on http://127.0.0.1:{port}")
    log(f"Endpoint: http://127.0.0.1:{port}/v1/chat/completions")
    log("Press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down")
        server.shutdown()
