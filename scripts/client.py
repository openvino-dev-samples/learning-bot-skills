# -*- coding: utf-8 -*-
"""CLI/HTTP client for the OpenVINO pipeline server (stdlib-only).

  client.py --health
  client.py --run --input "hello"
  client.py --chat "hello"
  client.py --shutdown
Talks to 127.0.0.1:18790 (override with --port). Usable before the venv exists.
"""
import argparse, json, sys, urllib.request

HOST = "127.0.0.1"


def _call(port, path, method="GET", body=None):
    url = "http://%s:%d%s" % (HOST, port, path)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=18790)
    ap.add_argument("--health", action="store_true")
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--input", default="")
    ap.add_argument("--chat")
    ap.add_argument("--shutdown", action="store_true")
    args = ap.parse_args()

    try:
        if args.health:
            print(json.dumps(_call(args.port, "/api/health"), ensure_ascii=False, indent=2))
        elif args.run:
            print(json.dumps(_call(args.port, "/api/run", "POST",
                  {"input": args.input, "params": {}}), ensure_ascii=False, indent=2))
        elif args.chat is not None:
            resp = _call(args.port, "/v1/chat/completions", "POST",
                         {"messages": [{"role": "user", "content": args.chat}]})
            print(resp["choices"][0]["message"]["content"])
        elif args.shutdown:
            print(json.dumps(_call(args.port, "/api/shutdown", "POST", {}), ensure_ascii=False))
        else:
            ap.print_help(); return 2
    except urllib.error.HTTPError as e:
        print("HTTP %d: %s" % (e.code, e.read().decode(errors="ignore")), file=sys.stderr)
        return 1
    except Exception as e:
        print("client error: %s (is the server up? run.ps1 --serve)" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
