"""Check a deployed Pages build, its local resources, and CLI-generated demos."""
import argparse
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import http.client
import json
import math
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlencode, urljoin, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


STATIC_FILES = {
    "index.html", "style.css", "app.js", "favicon.svg", "viewer/index.html",
    "viewer/style.css", "viewer/app.js", "viewer/model.js", "viewer/demos.js",
    "viewer/batch.js",
}
DEMO_EXPECTATIONS = {
    "bbox": ("bbox", "ap50", 1.0, 0.25, 3),
    "mask": ("segm", "ap", 0.0, 1.0, 0),
    "polygon": ("segm", "ap", 1.0, 1.0, 0),
}
METRICS = {
    "ap", "ap50", "ap75", "ap_small", "ap_medium", "ap_large",
    "ar1", "ar10", "ar100", "ar_small", "ar_medium", "ar_large",
}
SITE_FILES = STATIC_FILES | {"demos/manifest.json"} | {
    "demos/" + name + ".json" for name in DEMO_EXPECTATIONS
}
MAX_RESPONSE_BYTES = 8 * 1024 * 1024


class VerificationError(ValueError):
    """A deployed file does not match the expected build."""


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def object_value(value, label):
    require(isinstance(value, dict), label + " must be a JSON object")
    return value


def number_equal(value, expected):
    try:
        return (type(value) in (int, float) and math.isfinite(value)
                and abs(value - expected) <= 1e-9)
    except OverflowError:
        return False


def decoded_path(value):
    decoded = value
    for _ in range(4):
        updated = unquote(decoded)
        if updated == decoded:
            break
        decoded = updated
    require("%" not in decoded, "Ambiguous encoded path: " + value)
    require(not any(ord(char) < 32 or ord(char) == 127 for char in decoded),
            "Control character in path")
    require("\\" not in decoded, "Backslash in path: " + value)
    return decoded


def base_url(value):
    parts = urlsplit(value)
    require(parts.scheme in ("http", "https") and parts.hostname is not None,
            "URL must use http or https")
    require(parts.username is None and parts.password is None,
            "URL must not contain credentials")
    require(not parts.query and not parts.fragment, "URL must not contain a query or fragment")
    path = decoded_path(parts.path or "/")
    require(not any(part in (".", "..") for part in path.split("/")),
            "URL must not contain dot path segments")
    try:
        parts.port
    except ValueError as error:
        raise VerificationError("Invalid URL port") from error
    return urlunsplit((parts.scheme, parts.netloc, path.rstrip("/") + "/", "", ""))


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        raise VerificationError("Unexpected HTTP redirect for " + request.full_url)


class Deployment:
    def __init__(self, url, commit, attempt):
        self.url = base_url(url)
        require(re.fullmatch(r"[0-9a-fA-F]{40}", commit) is not None,
                "Commit must be a full 40-character Git SHA")
        self.commit = commit.lower()
        self.attempt = attempt
        handlers = [NoRedirect()]
        if urlsplit(self.url).hostname in ("127.0.0.1", "::1", "localhost"):
            handlers.append(ProxyHandler({}))
        self.opener = build_opener(*handlers)
        self.files = {}

    def fetch(self, relative):
        require(relative in SITE_FILES, "File outside site allowlist: " + relative)
        query = urlencode({"verify_commit": self.commit, "verify_attempt": self.attempt})
        request = Request(urljoin(self.url, relative) + "?" + query,
                          headers={"Cache-Control": "no-cache", "Accept-Encoding": "identity"})
        try:
            with self.opener.open(request, timeout=10) as response:
                require(response.status == 200, "Expected HTTP 200: " + relative)
                data = response.read(MAX_RESPONSE_BYTES + 1)
                require(len(data) <= MAX_RESPONSE_BYTES, "Response exceeds 8 MiB: " + relative)
                content_type = response.headers.get_content_type()
        except (HTTPError, URLError, OSError, UnicodeError, http.client.HTTPException) as error:
            raise VerificationError("Unable to load " + relative + ": " + str(error)) from error
        suffix = Path(relative).suffix
        accepted = {
            ".html": {"text/html"}, ".css": {"text/css"},
            ".js": {"text/javascript", "application/javascript"},
            ".json": {"application/json"}, ".svg": {"image/svg+xml"},
        }
        if suffix in accepted:
            require(content_type in accepted[suffix], "Unexpected content type for " + relative + ": " + content_type)
            require(bool(data.strip()), "Empty resource: " + relative)
        self.files[relative] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        return data

    def local_reference(self, document, reference, navigation=False):
        require(isinstance(reference, str) and reference.strip() == reference,
                "Invalid resource reference in " + document)
        parts = urlsplit(reference)
        if navigation and (parts.scheme or parts.netloc):
            # External navigation is not part of the deployment and is never fetched.
            require(parts.scheme in ("http", "https", "mailto") and not reference.startswith("//"),
                    "Unexpected external navigation in " + document)
            return None
        require(not parts.scheme and not parts.netloc, "Cross-origin resource in " + document)
        path = decoded_path(parts.path)
        home_link = navigation and document == "viewer/index.html" and reference == "../"
        require(home_link or ".." not in path.split("/"), "Parent path reference in " + document)
        require(not path.startswith("/"), "Absolute resource path in " + document)
        resolved = urlsplit(urljoin(urljoin(self.url, document), reference))
        base = urlsplit(self.url)
        require((resolved.scheme, resolved.netloc) == (base.scheme, base.netloc)
                and resolved.path.startswith(base.path), "Resource escapes project subpath: " + reference)
        relative = resolved.path[len(base.path):]
        if not relative or relative.endswith("/"):
            relative += "index.html"
        require(relative in SITE_FILES, "Linked file outside site allowlist: " + reference)
        return relative


def parse_json(data, label):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "Duplicate JSON key in " + label + ": " + key)
            result[key] = value
        return result

    def invalid_constant(value):
        raise VerificationError("Non-finite JSON number in " + label + ": " + value)

    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=pairs, parse_constant=invalid_constant)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise VerificationError("Invalid JSON in " + label + ": " + str(error)) from error
    return object_value(value, label)


class ResourceLinks(HTMLParser):
    def __init__(self, deployment, document):
        super().__init__(convert_charrefs=True)
        self.deployment = deployment
        self.document = document
        self.references = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        require(tag != "base", "HTML base tags are not supported: " + self.document)
        if tag == "a" and "href" in attrs:
            value = self.deployment.local_reference(self.document, attrs["href"], navigation=True)
            if value is not None:
                self.references.add(value)
        for attribute in (("src", "href") if tag == "link" else ("src",)):
            if attribute in attrs:
                value = self.deployment.local_reference(self.document, attrs[attribute])
                self.references.add(value)


def verify_report(name, report, expected):
    geometry, metric, left, right, _ = expected
    require(report.get("schema_version") == "0.1.0", name + ": wrong report schema")
    summaries = {}
    for side, value in (("baseline", left), ("candidate", right)):
        evaluation = object_value(report.get(side), name + "." + side)
        require(evaluation.get("schema_version") == "0.1.0", name + ": wrong evaluation schema")
        require(evaluation.get("evaluator_version") == "0.2.1", name + ": wrong evaluator version")
        config = object_value(evaluation.get("config"), name + "." + side + ".config")
        require(config.get("ignore_policy") == "coco_" + geometry, name + ": wrong geometry")
        summary = object_value(evaluation.get("summary"), name + "." + side + ".summary")
        require(number_equal(summary.get(metric), value), name + ": unexpected " + side + " " + metric)
        for key in METRICS:
            number = summary.get(key)
            require(type(number) in (int, float) and (number == -1 or 0 <= number <= 1),
                    name + ": invalid summary metric " + key)
        summaries[side] = summary
    metrics = report.get("metrics")
    require(isinstance(metrics, list) and len(metrics) == len(METRICS), name + ": expected all 12 metrics")
    rows = [object_value(row, name + ".metrics[]") for row in metrics]
    require(all(isinstance(row.get("name"), str) for row in rows), name + ": invalid metric name")
    require({row.get("name") for row in rows} == METRICS, name + ": unknown or missing metric")
    for row in rows:
        key = row["name"]
        values = []
        for side in ("baseline", "candidate"):
            value = summaries[side][key]
            value = None if value == -1 else value
            values.append(value)
            require(side in row and (row[side] is None if value is None else number_equal(row[side], value)),
                    name + ": comparison " + side + " does not match summary for " + key)
        difference = None if None in values else values[1] - values[0]
        require("delta" in row and (row["delta"] is None if difference is None else number_equal(row["delta"], difference)),
                name + ": comparison delta does not match summary for " + key)
    if name == "polygon":
        require(all(row.get("delta") is None or number_equal(row["delta"], 0) for row in rows),
                "polygon: defined metric differences must be zero")
    if name == "bbox":
        gates = object_value(report.get("metric_gates"), "bbox.metric_gates")
        require(gates.get("format_version") == "1" and gates.get("status") == "failed"
                and gates.get("reason") == "rules_failed", "bbox: expected failed metric gates")
        checks = gates.get("checks")
        require(isinstance(checks, list) and checks, "bbox: missing gate checks")
        checks = [object_value(check, "bbox.metric_gates.checks[]") for check in checks]
        require(any(check.get("kind") == "max_drop" and check.get("metric") == "ap50"
                    and check.get("category_id") is None and check.get("status") == "failed"
                    and check.get("reason") == "drop_exceeded"
                    and all(number_equal(check.get(key), value) for key, value in
                            (("baseline", 1), ("candidate", 0.25), ("drop", 0.75), ("threshold", 0.1)))
                    for check in checks), "bbox: missing expected AP50 regression failure")


def verify_once(url, commit, attempt=1):
    deployment = Deployment(url, commit, attempt)
    manifest = parse_json(deployment.fetch("demos/manifest.json"), "manifest")
    require(manifest.get("schema_version") == "1" and manifest.get("synthetic") is True,
            "Unexpected demo manifest format")
    require(manifest.get("source_commit") == deployment.commit, "Manifest source_commit does not match " + deployment.commit)
    require(manifest.get("source_modified") is False, "Manifest source_modified must be false")
    demos = object_value(manifest.get("demos"), "manifest.demos")
    require(set(demos) == set(DEMO_EXPECTATIONS), "Manifest must contain exactly bbox, mask and polygon demos")
    summary = {}
    for name, expected in DEMO_EXPECTATIONS.items():
        geometry, metric, left, right, exit_code = expected
        entry = object_value(demos[name], "manifest.demos." + name)
        require(entry.get("report") == name + ".json", name + ": invalid report path")
        require(entry.get("iou_type") == geometry and entry.get("metric") == metric
                and type(entry.get("expected_exit_code")) is int and entry["expected_exit_code"] == exit_code,
                name + ": wrong manifest geometry, metric or exit code")
        require(number_equal(entry.get("baseline"), left) and number_equal(entry.get("candidate"), right),
                name + ": wrong manifest metric values")
        digest = entry.get("report_sha256")
        require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
                name + ": invalid report SHA-256")
        relative = "demos/" + entry["report"]
        data = deployment.fetch(relative)
        require(hashlib.sha256(data).hexdigest() == digest, name + ": report SHA-256 mismatch")
        verify_report(name, parse_json(data, relative), expected)
        summary[name] = {"metric": metric, "baseline": left, "candidate": right,
                         "expected_exit_code": exit_code, "report_sha256": digest}
    for relative in sorted(STATIC_FILES):
        data = deployment.fetch(relative)
        if relative.endswith(".html"):
            parser = ResourceLinks(deployment, relative)
            try:
                parser.feed(data.decode("utf-8"))
                parser.close()
            except UnicodeError as error:
                raise VerificationError("Invalid UTF-8 in " + relative) from error
        if relative.endswith(".css"):
            for match in re.finditer(r"url\(\s*['\"]?([^'\")\s]+)['\"]?\s*\)", data.decode("utf-8")):
                deployment.local_reference(relative, match.group(1))
    require(set(deployment.files) == SITE_FILES, "Incomplete deployment resource checks")
    return {"status": "passed", "url": deployment.url, "source_commit": deployment.commit,
            "source_modified": False, "demos": summary, "files": deployment.files}


def verify(url, commit, attempts=3, retry_delay=2):
    require(type(attempts) is int and 1 <= attempts <= 10, "Attempts must be between 1 and 10")
    require(type(retry_delay) in (int, float) and math.isfinite(retry_delay) and 0 <= retry_delay <= 60,
            "Retry delay must be between 0 and 60 seconds")
    # Validate configuration before retrying a deployment that may still be cached.
    Deployment(url, commit, 1)
    failures = []
    for attempt in range(1, attempts + 1):
        try:
            result = verify_once(url, commit, attempt)
        except VerificationError as error:
            failures.append({"attempt": attempt, "error": str(error)})
            if attempt < attempts:
                time.sleep(retry_delay)
        else:
            result.update({"attempts_used": attempt, "previous_failures": failures})
            return result
    return {"status": "failed", "url": base_url(url), "source_commit": commit.lower(),
            "attempts_used": attempts, "failures": failures}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="Pages project URL, including its subpath")
    parser.add_argument("--commit", required=True, help="expected full source commit SHA")
    parser.add_argument("--attempts", type=int, default=3, help="maximum attempts, 1-10 (default: 3)")
    parser.add_argument("--retry-delay", type=float, default=2, help="seconds between attempts, 0-60 (default: 2)")
    parser.add_argument("--output", type=Path, help="also save the JSON verification result")
    args = parser.parse_args(argv)
    try:
        result = verify(args.url, args.commit, args.attempts, args.retry_delay)
    except (VerificationError, ValueError) as error:
        result = {"status": "failed", "error": str(error)}
    result["checked_at"] = datetime.now(timezone.utc).isoformat()
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output is not None:
        try:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(text, encoding="utf-8")
        except OSError as error:
            print(json.dumps({"status": "failed", "error": "Unable to write output: " + str(error)}))
            return 1
    print(text, end="")
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
