"""Exercise deployment checks against a temporary HTTP server."""
import contextlib
import copy
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import io
import json
from pathlib import Path
from socketserver import TCPServer
import tempfile
import threading
import unittest
from urllib.parse import urlsplit


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("deployment_verifier", HERE / "verify_deployment.py")
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)
COMMIT = "a" * 40
OLD_COMMIT = "b" * 40
PREFIX = "/moondeteval/"


def json_bytes(value):
    return json.dumps(value, separators=(",", ":")).encode("utf-8")


def fixtures():
    files = {}
    source = HERE.parent
    for relative in verifier.STATIC_FILES:
        if relative.startswith("viewer/"):
            files[PREFIX + relative] = (source / relative).read_bytes()
        else:
            files[PREFIX + relative] = (HERE / relative).read_bytes()
    demos = {}
    for name, (geometry, metric, left, right, exit_code) in verifier.DEMO_EXPECTATIONS.items():
        report = {"schema_version": "0.1.0", "metrics": []}
        for side, value in (("baseline", left), ("candidate", right)):
            report[side] = {"schema_version": "0.1.0", "evaluator_version": "0.2.2",
                            "config": {"ignore_policy": "coco_" + geometry},
                            "summary": {key: value for key in verifier.METRICS}}
        for key in sorted(verifier.METRICS):
            report["metrics"].append({"name": key, "baseline": left, "candidate": right, "delta": right - left})
        if name == "bbox":
            report["metric_gates"] = {"format_version": "1", "status": "failed", "reason": "rules_failed",
                "checks": [{"kind": "max_drop", "metric": "ap50", "category_id": None,
                            "threshold": 0.1, "baseline": 1, "candidate": 0.25, "drop": 0.75,
                            "status": "failed", "reason": "drop_exceeded"}]}
        data = json_bytes(report)
        files[PREFIX + "demos/" + name + ".json"] = data
        demos[name] = {"report": name + ".json", "report_sha256": hashlib.sha256(data).hexdigest(),
                       "iou_type": geometry, "metric": metric, "baseline": left, "candidate": right,
                       "expected_exit_code": exit_code}
    files[PREFIX + "demos/manifest.json"] = json_bytes({"schema_version": "1", "synthetic": True,
        "source_commit": COMMIT, "source_modified": False, "demos": demos})
    return files


class FixtureServer:
    def __init__(self, files):
        self.files = files
        self.requests = []
        self.manifest_responses = []
        self.redirects = {}
        self.content_types = {}

    def __enter__(self):
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                path = urlsplit(self.path).path
                fixture.requests.append(path)
                if path in fixture.redirects:
                    self.send_response(302)
                    self.send_header("Location", fixture.redirects[path])
                    self.end_headers()
                    return
                data = fixture.files.get(path)
                if path == PREFIX + "demos/manifest.json" and fixture.manifest_responses:
                    data = fixture.manifest_responses.pop(0)
                if data is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                content_type = fixture.content_types.get(path, {
                    ".html": "text/html", ".css": "text/css", ".js": "application/javascript",
                    ".json": "application/json", ".svg": "image/svg+xml",
                }.get(Path(path).suffix, "application/octet-stream"))
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, format, *args):
                pass

        class LocalHTTPServer(ThreadingHTTPServer):
            def server_bind(self):
                # No reverse DNS lookup is needed for a loopback fixture server.
                TCPServer.server_bind(self)
                self.server_name = "localhost"
                self.server_port = self.server_address[1]

        self.server = LocalHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        self.thread.start()
        self.url = "http://127.0.0.1:" + str(self.server.server_port) + PREFIX
        return self

    def __exit__(self, *args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.files = fixtures()

    def manifest(self):
        return json.loads(self.files[PREFIX + "demos/manifest.json"])

    def save_manifest(self, value):
        self.files[PREFIX + "demos/manifest.json"] = json_bytes(value)

    def change_report(self, name, change):
        key = PREFIX + "demos/" + name + ".json"
        report = json.loads(self.files[key])
        change(report)
        self.files[key] = json_bytes(report)
        manifest = self.manifest()
        manifest["demos"][name]["report_sha256"] = hashlib.sha256(self.files[key]).hexdigest()
        self.save_manifest(manifest)

    def failure(self, pattern, **kwargs):
        with FixtureServer(self.files) as server:
            result = verifier.verify(server.url, COMMIT, attempts=1, retry_delay=0, **kwargs)
        self.assertEqual(result["status"], "failed")
        self.assertRegex(result["failures"][-1]["error"], pattern)
        return result

    def test_full_project_subpath_and_existing_home_navigation(self):
        with FixtureServer(self.files) as server:
            result = verifier.verify(server.url.rstrip("/"), COMMIT, attempts=1, retry_delay=0)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(set(result["files"]), verifier.SITE_FILES)
        self.assertEqual(len(server.requests), len(verifier.SITE_FILES))
        self.assertTrue(all(path.startswith(PREFIX) for path in server.requests))
        self.assertEqual(result["demos"]["bbox"]["candidate"], 0.25)

    def test_allowlist_matches_builder(self):
        spec = importlib.util.spec_from_file_location("product_site_builder", HERE / "build.py")
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        # Pages consumes this build control file without serving it publicly.
        self.assertEqual(verifier.STATIC_FILES, set(builder.ASSETS))
        self.assertEqual(set(verifier.DEMO_EXPECTATIONS), set(builder.DEMOS))

    def test_stale_commit_fails_after_bounded_retries(self):
        manifest = self.manifest()
        manifest["source_commit"] = OLD_COMMIT
        self.save_manifest(manifest)
        with FixtureServer(self.files) as server:
            result = verifier.verify(server.url, COMMIT, attempts=2, retry_delay=0)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["attempts_used"], 2)
        self.assertEqual(len(server.requests), 2)

    def test_stale_manifest_can_refresh_on_next_attempt(self):
        manifest = self.manifest()
        manifest["source_commit"] = OLD_COMMIT
        with FixtureServer(self.files) as server:
            server.manifest_responses = [json_bytes(manifest)]
            result = verifier.verify(server.url, COMMIT, attempts=2, retry_delay=0)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["attempts_used"], 2)
        self.assertEqual(len(result["previous_failures"]), 1)

    def test_source_modified_requires_boolean_false(self):
        for value in (True, 0, None, "false"):
            with self.subTest(value=value):
                manifest = self.manifest()
                manifest["source_modified"] = value
                self.save_manifest(manifest)
                self.failure("source_modified")

    def test_tampered_report_bytes_fail_sha(self):
        self.files[PREFIX + "demos/bbox.json"] += b" "
        self.failure("SHA-256 mismatch")

    def test_matching_sha_cannot_hide_changed_metric(self):
        self.change_report("mask", lambda report: report["candidate"]["summary"].update(ap=0.5))
        self.failure("unexpected candidate ap")

    def test_bbox_gate_reason_and_drop_are_checked(self):
        original = copy.deepcopy(self.files)
        for field, value in (("reason", "ok"), ("drop", 0.5), ("threshold", 0.2), ("status", "passed")):
            with self.subTest(field=field):
                self.files = copy.deepcopy(original)
                self.change_report("bbox", lambda report: report["metric_gates"]["checks"][0].update({field: value}))
                self.failure("expected AP50 regression failure")

    def test_polygon_defined_delta_must_be_zero(self):
        self.change_report("polygon", lambda report: report["metrics"][0].update(delta=0.1))
        self.failure("delta does not match summary")

    def test_comparison_metrics_match_summaries_and_defined_deltas(self):
        original = copy.deepcopy(self.files)
        for field, value in (("baseline", 0.123), ("candidate", None), ("delta", None)):
            with self.subTest(field=field):
                self.files = copy.deepcopy(original)
                self.change_report("polygon", lambda report: report["metrics"][0].update({field: value}))
                self.failure("does not match summary")

    def test_undefined_summaries_require_null_comparison_values(self):
        def undefined(report):
            report["baseline"]["summary"]["ap_large"] = -1
            report["candidate"]["summary"]["ap_large"] = -1
            for row in report["metrics"]:
                if row["name"] == "ap_large":
                    row.update(baseline=None, candidate=None, delta=None)

        self.change_report("polygon", undefined)
        with FixtureServer(self.files) as server:
            result = verifier.verify(server.url, COMMIT, attempts=1, retry_delay=0)
        self.assertEqual(result["status"], "passed")
        self.change_report("polygon", lambda report: next(row for row in report["metrics"] if row["name"] == "ap_large").update(delta=0))
        self.failure("delta does not match summary")

    def test_duplicate_or_non_string_metric_names_fail(self):
        original = copy.deepcopy(self.files)
        for value in ("ap", [], None):
            with self.subTest(value=value):
                self.files = copy.deepcopy(original)
                self.change_report("polygon", lambda report: report["metrics"][1].update(name=value))
                self.failure("metric name|unknown or missing metric")

    def test_all_report_versions_and_geometry_are_checked(self):
        original = copy.deepcopy(self.files)
        for field, value in (("evaluator_version", "0.1.0"), ("schema_version", "2")):
            with self.subTest(field=field):
                self.files = copy.deepcopy(original)
                self.change_report("mask", lambda report: report["candidate"].update({field: value}))
                self.failure("wrong .*version|wrong evaluation schema")
        self.files = original
        self.change_report("mask", lambda report: report["baseline"]["config"].update(ignore_policy="coco_bbox"))
        self.failure("wrong geometry")

    def test_manifest_metadata_is_not_trusted(self):
        original = self.manifest()
        for field, value in (("iou_type", "segm"), ("metric", "ap"), ("expected_exit_code", 0),
                             ("expected_exit_code", True), ("baseline", 0), ("candidate", 1)):
            with self.subTest(field=field, value=value):
                manifest = copy.deepcopy(original)
                manifest["demos"]["bbox"][field] = value
                self.save_manifest(manifest)
                self.failure("wrong manifest")

    def test_missing_static_resources_fail(self):
        for resource in ("style.css", "app.js", "viewer/model.js", "viewer/index.html"):
            with self.subTest(resource=resource):
                files = self.files.copy()
                del self.files[PREFIX + resource]
                self.failure("Unable to load " + resource)
                self.files = files

    def test_html_in_place_of_javascript_fails(self):
        with FixtureServer(self.files) as server:
            server.content_types[PREFIX + "app.js"] = "text/html"
            result = verifier.verify(server.url, COMMIT, attempts=1, retry_delay=0)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Unexpected content type", result["failures"][0]["error"])

    def test_manifest_path_cannot_escape_or_fetch_external_url(self):
        original = self.manifest()
        for value in ("../bbox.json", "https://example.invalid/x", "//example.invalid/x", "%2e%2e/bbox.json"):
            with self.subTest(path=value):
                manifest = copy.deepcopy(original)
                manifest["demos"]["bbox"]["report"] = value
                self.save_manifest(manifest)
                with FixtureServer(self.files) as server:
                    result = verifier.verify(server.url, COMMIT, attempts=1, retry_delay=0)
                self.assertEqual(result["status"], "failed")
                self.assertEqual(server.requests, [PREFIX + "demos/manifest.json"])

    def test_html_resource_paths_reject_external_and_parent_paths(self):
        original = self.files[PREFIX + "index.html"]
        for value in ("../secret.js", "%2e%2e/secret.js", "%252e%252e/secret.js", "//example.invalid/x.js",
                      "https://example.invalid/x.js", "/app.js", "missing.js", "..\\secret.js"):
            with self.subTest(path=value):
                self.files[PREFIX + "index.html"] = original + ('<script src="' + value + '"></script>').encode()
                with FixtureServer(self.files) as server:
                    result = verifier.verify(server.url, COMMIT, attempts=1, retry_delay=0)
                self.assertEqual(result["status"], "failed")
                self.assertTrue(all(path.startswith(PREFIX) for path in server.requests))

    def test_css_paths_are_confined(self):
        self.files[PREFIX + "style.css"] += b" body { background: url('../secret.svg'); }"
        self.failure("Parent path reference")

    def test_redirects_are_rejected_before_following(self):
        with FixtureServer(self.files) as server:
            server.redirects[PREFIX + "app.js"] = server.url + "not-in-allowlist"
            result = verifier.verify(server.url, COMMIT, attempts=1, retry_delay=0)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Unexpected HTTP redirect", result["failures"][0]["error"])
        self.assertNotIn(PREFIX + "not-in-allowlist", server.requests)

    def test_non_object_and_invalid_json_are_readable_failures(self):
        for value in (b"[]", b"null", b"1", b"{", b'\xff', b'{"x":NaN}', b'{"x":1,"x":2}'):
            with self.subTest(value=value):
                self.files[PREFIX + "demos/manifest.json"] = value
                self.failure("JSON|Duplicate")
        self.files = fixtures()
        self.files[PREFIX + "demos/bbox.json"] = b"[]"
        manifest = self.manifest()
        manifest["demos"]["bbox"]["report_sha256"] = hashlib.sha256(b"[]").hexdigest()
        self.save_manifest(manifest)
        self.failure("must be a JSON object")

    def test_malformed_nested_values_fail(self):
        original = self.manifest()
        for field, value in (("demos", []), ("source_commit", None)):
            with self.subTest(field=field):
                manifest = copy.deepcopy(original)
                manifest[field] = value
                self.save_manifest(manifest)
                self.failure("object|source_commit")
        self.files = fixtures()
        self.change_report("bbox", lambda report: report.update(metric_gates=[]))
        self.failure("must be a JSON object")

    def test_cli_writes_success_and_failure_json_with_correct_exit(self):
        with tempfile.TemporaryDirectory(prefix="deployment-test-") as directory:
            output = Path(directory) / "result.json"
            with FixtureServer(self.files) as server, contextlib.redirect_stdout(io.StringIO()):
                code = verifier.main(["--url", server.url, "--commit", COMMIT, "--attempts", "1", "--output", str(output)])
                self.assertEqual(code, 0)
                self.assertEqual(json.loads(output.read_text(encoding="utf-8"))["status"], "passed")
                code = verifier.main(["--url", server.url, "--commit", OLD_COMMIT, "--attempts", "1", "--output", str(output)])
            self.assertEqual(code, 1)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8"))["status"], "failed")

    def test_cli_rejects_bad_configuration(self):
        cases = (("--attempts", "0"), ("--attempts", "11"), ("--retry-delay", "nan"),
                 ("--retry-delay", "-1"), ("--retry-delay", "61"), ("--commit", "main"),
                 ("--url", "file:///tmp/site/"), ("--url", "https://example.test/../site/"),
                 ("--url", "https://user:password@example.test/site/"),
                 ("--url", "https://example.test/site/?key=value"))
        for option, value in cases:
            with self.subTest(option=option, value=value), contextlib.redirect_stdout(io.StringIO()) as output:
                code = verifier.main(["--url", "http://127.0.0.1:1/moondeteval/", "--commit", COMMIT, option, value])
                self.assertEqual(code, 1)
                self.assertEqual(json.loads(output.getvalue())["status"], "failed")


if __name__ == "__main__":
    unittest.main()
