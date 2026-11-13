#!/usr/bin/env python3
"""Local fake of the GitHub API slice the App's sync uses (simulator verification only).

Usage: python3 -I App/scripts/fake-github.py --port 8765 --out DIR [--token T] [--login L]
Run the App (DEBUG) with LE_GITHUB_API=http://127.0.0.1:8765 and LE_GITHUB_TOKEN=T.
Files committed by the App are mirrored under DIR (e.g. DIR/observations/iphone/2026-11.jsonl).
Touch DIR/.reject-token to make every request answer 401, DIR/.fail-503 for 503.
Files under --seed SEED (e.g. SEED/plan/2026-11-13.json) are served as if committed by another
writer (the Mac's Word Planning); they are read live, so dropping a new plan file there works.
The stale-head error format is the same assumption as SyncCore's GitHubErrors.isStaleHead.
"""
import argparse
import base64
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

p = argparse.ArgumentParser()
p.add_argument("--port", type=int, default=8765)
p.add_argument("--out", required=True)
p.add_argument("--token", default="fake-token")
p.add_argument("--login", default="learner")
p.add_argument("--repo", default="english-data")
p.add_argument("--seed", help="directory of extra repo files served read-only (e.g. plan/*.json)")
args = p.parse_args()

state = {"head": "oid0", "n": 0, "snapshots": {"oid0": {"README.md": b"# english-data\n"}}}


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, obj=None, raw=None):
        body = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("github-authentication-token-expiration", "2027-02-01 00:00:00 UTC")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def refused(self):
        """Answers 503 / 401 when the flag files or a wrong token say so; True if answered."""
        if os.path.exists(os.path.join(args.out, ".fail-503")):
            self.reply(503, {"message": "Service Unavailable"})
            return True
        if os.path.exists(os.path.join(args.out, ".reject-token")) or \
                self.headers.get("Authorization") != f"Bearer {args.token}":
            self.reply(401, {"message": "Bad credentials"})
            return True
        return False

    def do_GET(self):
        if self.refused():
            return
        u = urlparse(self.path)
        prefix = f"/repos/{args.login}/{args.repo}/contents/"
        if not u.path.startswith(prefix):
            return self.reply(404, {"message": "Not Found"})
        path = unquote(u.path[len(prefix):])
        ref = parse_qs(u.query).get("ref", [state["head"]])[0]
        files = dict(state["snapshots"].get(state["head"] if ref == "main" else ref, {}))
        if args.seed:
            for root, _, names in os.walk(args.seed):
                for n in names:
                    full = os.path.join(root, n)
                    with open(full, "rb") as f:
                        files.setdefault(os.path.relpath(full, args.seed), f.read())
        data = files.get(path)
        # Files placed in DIR by hand stand in for ones committed by other writers.
        if data is None and os.path.isfile(os.path.join(args.out, path)):
            with open(os.path.join(args.out, path), "rb") as f:
                data = f.read()
        if data is None:
            children = sorted({k[len(path) + 1:].split("/")[0] for k in files if k.startswith(path + "/")})
            if children:  # directory listing, as the Contents API returns it
                return self.reply(200, [{"name": c, "path": f"{path}/{c}", "type": "file"} for c in children])
            return self.reply(404, {"message": "Not Found"})
        self.reply(200, raw=data)

    def do_POST(self):
        if self.refused():
            return
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        q, v = req["query"], req.get("variables", {})
        if "createCommitOnBranch" in q:
            inp = v["input"]
            if inp["expectedHeadOid"] != state["head"]:
                return self.reply(200, {"data": {"createCommitOnBranch": None}, "errors": [{
                    "type": "STALE_DATA",
                    "message": f'Expected branch to point to "{inp["expectedHeadOid"]}" but it did not. Pull and try again.'}]})
            files = dict(state["snapshots"][state["head"]])
            for add in inp["fileChanges"].get("additions", []):
                files[add["path"]] = base64.b64decode(add["contents"])
                target = os.path.join(args.out, add["path"])
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(target, "wb") as f:
                    f.write(files[add["path"]])
            state["n"] += 1
            state["head"] = f"oid{state['n']}"
            state["snapshots"][state["head"]] = files
            print("commit", state["head"], inp["message"]["headline"], flush=True)
            return self.reply(200, {"data": {"createCommitOnBranch": {"commit": {"oid": state["head"]}}}})
        if "viewer" in q:
            return self.reply(200, {"data": {"viewer": {"login": args.login}}})
        if "ref(" in q:
            if v.get("owner") != args.login or v.get("name") != args.repo:
                return self.reply(200, {"data": {"repository": None}, "errors": [{"type": "NOT_FOUND", "message": "no repo"}]})
            return self.reply(200, {"data": {"repository": {"ref": {"target": {"oid": state["head"]}}}}})
        self.reply(400, {"message": "unsupported"})


os.makedirs(args.out, exist_ok=True)
ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
