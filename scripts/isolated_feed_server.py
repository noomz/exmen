#!/usr/bin/env python3
"""Serve an isolated Sparkle feed over HTTPS. TLS material stays out of the repo."""

from __future__ import annotations

import argparse
import http.server
import ssl
import sys
from pathlib import Path


class LoggingHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        line = '%s %s\n' % (self.log_date_time_string(), format % args)
        sys.stderr.write(line)
        log = getattr(self.server, 'access_log', None)
        if log:
            log.write(line)
            log.flush()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--bind', default='192.168.64.1')
    parser.add_argument('--port', type=int, default=8443)
    parser.add_argument('--cert', required=True, type=Path)
    parser.add_argument('--key', required=True, type=Path)
    parser.add_argument('--access-log', type=Path)
    args = parser.parse_args()
    args.root.mkdir(parents=True, exist_ok=True)
    handler = lambda *a, **k: LoggingHandler(*a, directory=str(args.root), **k)
    server = http.server.ThreadingHTTPServer((args.bind, args.port), handler)
    log = open(args.access_log, 'a') if args.access_log else None
    server.access_log = log
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(args.cert, args.key)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    print(f'https://{args.bind}:{args.port}/', flush=True)
    try:
        server.serve_forever()
    finally:
        if log:
            log.close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
