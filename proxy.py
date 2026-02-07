#!/usr/bin/env python3
"""
Simple proxy to strip Anthropic-specific 'thinking' params before forwarding to LiteLLM.
Listens on port 4001, forwards to LiteLLM on port 4000.
"""

import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.request
import urllib.error

LITELLM_URL = os.environ.get("LITELLM_URL", "http://localhost:4000")


class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Quieter logging
        pass

    def do_GET(self):
        """Forward GET requests (health checks, etc)."""
        self._proxy_request()

    def do_POST(self):
        """Forward POST requests, stripping thinking params from body."""
        self._proxy_request(strip_thinking=True)

    def _proxy_request(self, strip_thinking=False):
        # Read request body if present
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        # Strip thinking params from JSON body
        if strip_thinking and body:
            try:
                data = json.loads(body)
                modified = self._strip_thinking_params(data)
                if modified:
                    print(f"[proxy] Stripped thinking params from request to {self.path}")
                body = json.dumps(data).encode("utf-8")
            except json.JSONDecodeError:
                pass  # Not JSON, forward as-is

        # Build target URL
        target_url = f"{LITELLM_URL}{self.path}"

        # Build headers (forward most, skip hop-by-hop)
        headers = {}
        skip_headers = {"host", "connection", "keep-alive", "transfer-encoding"}
        for key, value in self.headers.items():
            if key.lower() not in skip_headers:
                headers[key] = value

        # Update content-length if body was modified
        if body:
            headers["Content-Length"] = str(len(body))

        # Make request to LiteLLM
        try:
            req = urllib.request.Request(
                target_url,
                data=body,
                headers=headers,
                method=self.command,
            )
            with urllib.request.urlopen(req) as response:
                self.send_response(response.status)
                for key, value in response.headers.items():
                    if key.lower() not in {"transfer-encoding", "connection"}:
                        self.send_header(key, value)
                self.end_headers()
                self.wfile.write(response.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for key, value in e.headers.items():
                if key.lower() not in {"transfer-encoding", "connection"}:
                    self.send_header(key, value)
            self.end_headers()
            self.wfile.write(e.read())
        except urllib.error.URLError as e:
            print(f"[proxy] Connection error to {target_url}: {e.reason}")
            self.send_response(503)
            self.end_headers()
            self.wfile.write(f"Service unavailable: {e.reason}".encode())
        except ConnectionRefusedError as e:
            print(f"[proxy] LiteLLM connection refused at {LITELLM_URL}")
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"LiteLLM service is not available")
        except (ConnectionResetError, BrokenPipeError) as e:
            print(f"[proxy] Connection reset while proxying: {e}")
            self.send_response(502)
            self.end_headers()
            self.wfile.write(b"Connection interrupted")
        except OSError as e:
            print(f"[proxy] OS/network error: {e}")
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"Network error: {e}".encode())
        except Exception as e:
            print(f"[proxy] Unexpected error: {type(e).__name__}: {e}")
            self.send_response(500)
            self.end_headers()
            self.wfile.write(f"Internal proxy error: {type(e).__name__}".encode())

    def _strip_thinking_params(self, data):
        """Recursively strip thinking-related params. Returns True if modified."""
        modified = False
        thinking_keys = {
            "thinking",
            "extended_thinking",
            "thinking_budget",
            "budget_tokens",
        }

        if isinstance(data, dict):
            for key in list(data.keys()):
                if key in thinking_keys:
                    del data[key]
                    modified = True
                elif isinstance(data[key], (dict, list)):
                    if self._strip_thinking_params(data[key]):
                        modified = True
        elif isinstance(data, list):
            for item in data:
                if isinstance(item, (dict, list)):
                    if self._strip_thinking_params(item):
                        modified = True

        return modified


def main():
    port = int(os.environ.get("PROXY_PORT", 4001))
    server = HTTPServer(("0.0.0.0", port), ProxyHandler)
    print(f"[proxy] Listening on port {port}, forwarding to {LITELLM_URL}")
    print("[proxy] Will strip thinking params from requests")
    server.serve_forever()


if __name__ == "__main__":
    main()
