#!/usr/bin/env python3
"""Serve a long MP3 over delayed, byte-range HTTP for streaming seek regressions."""
# Copyright (c) 2026 Sandalbar Enterprises, Inc.
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import time


def serve(source: Path, port: int) -> None:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            size = source.stat().st_size
            start, end = 0, size - 1
            requested = self.headers.get("Range")
            if requested:
                try:
                    unit, bounds = requested.split("=", 1)
                    first, last = bounds.split("-", 1)
                    if unit != "bytes":
                        raise ValueError("Unsupported range unit")
                    if first:
                        start = int(first)
                        end = min(end, int(last)) if last else end
                    else:
                        start = max(0, size - int(last))
                    if not 0 <= start <= end < size:
                        raise ValueError("Unsatisfiable range")
                except ValueError:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.end_headers()
                    return
            self.send_response(206 if requested else 200)
            self.send_header("Content-Type", "audio/mpeg")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(end - start + 1))
            if requested:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()
            # Hold initial data so buffering and seek requests overlap reliably.
            if start == 0:
                time.sleep(3)
            try:
                with source.open("rb") as stream:
                    stream.seek(start)
                    remaining = end - start + 1
                    while remaining > 0:
                        block = stream.read(min(remaining, 32768))
                        if not block:
                            break
                        self.wfile.write(block)
                        remaining -= len(block)
                        time.sleep(0.02)
            except (BrokenPipeError, ConnectionResetError):
                pass  # Seeking cancels the old HTTP response.

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Streaming seek fixture: http://127.0.0.1:{port}/stream.mp3", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="A Sudden Clash of Thunder 01 MP3 (84m47s)")
    parser.add_argument("--port", type=int, default=18769)
    args = parser.parse_args()
    if not args.source.is_file():
        parser.error("source must be an existing MP3 file")
    serve(args.source, args.port)
