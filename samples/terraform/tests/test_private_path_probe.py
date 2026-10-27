import contextlib
import importlib.util
import io
import ipaddress
import json
import urllib.error
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch


spec = importlib.util.spec_from_file_location(
    "probe", Path(__file__).parents[1] / "scripts" / "private-path-probe.py"
)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class PrivatePathProbeTests(unittest.TestCase):
    def test_private_storage_read_uses_identity_without_disclosing_data(self):
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.status = 200
        response.read.return_value = b"<EnumerationResults><Containers><Container><Name>private-name</Name></Container></Containers></EnumerationResults>"
        with patch.object(probe.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("10.247.1.7", 443))]), \
                patch.object(probe, "request_json", return_value=(200, {"access_token": "secret-token"})) as identity:
            result = probe.check_storage(opener, "https://storage.blob.core.windows.net/", ipaddress.ip_network("10.247.1.0/24"))
        self.assertEqual(200, result["status"])
        self.assertEqual("ManagedIdentity", result["authentication"])
        self.assertIn("storage.azure.com", identity.call_args.args[1])
        request = opener.open.call_args.args[0]
        self.assertEqual("GET", request.get_method())
        self.assertEqual("https://storage.blob.core.windows.net/?comp=list&maxresults=1", request.full_url)
        self.assertEqual("Bearer secret-token", request.get_header("Authorization"))
        self.assertNotIn("secret-token", json.dumps(result))
        self.assertNotIn("private-name", json.dumps(result))

    def test_storage_rejects_unsafe_endpoints_and_public_dns_before_credentials(self):
        subnet = ipaddress.ip_network("10.247.1.0/24")
        for endpoint in ("http://storage.blob.core.windows.net/", "https://other.example/", "https://user@storage.blob.core.windows.net/",
                         "https://storage.blob.core.windows.net/?key=value", "https://storage.blob.core.windows.net/container"):
            with self.subTest(endpoint=endpoint), patch.object(probe, "request_json") as identity:
                with self.assertRaisesRegex(RuntimeError, "Invalid storage endpoint"):
                    probe.check_storage(None, endpoint, subnet)
                identity.assert_not_called()
        with patch.object(probe.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("20.10.0.1", 443))]), \
                patch.object(probe, "request_json") as identity:
            with self.assertRaisesRegex(RuntimeError, "resolve exclusively"):
                probe.check_storage(None, "https://storage.blob.core.windows.net/", subnet)
            identity.assert_not_called()

    def test_storage_requires_valid_success_and_bounds_role_propagation(self):
        endpoint = "https://storage.blob.core.windows.net/"
        for body in (b"not-xml", b"<Error><Code>Denied</Code></Error>"):
            opener = MagicMock()
            response = opener.open.return_value.__enter__.return_value
            response.status = 200
            response.read.return_value = body
            with patch.object(probe, "private_dns", return_value={}), \
                    patch.object(probe, "request_json", return_value=(200, {"access_token": "secret"})):
                with self.assertRaisesRegex(RuntimeError, "list-containers response"):
                    probe.check_storage(opener, endpoint, None)
        opener = MagicMock()
        opener.open.side_effect = urllib.error.HTTPError(endpoint, 403, "Forbidden", {}, None)
        with patch.object(probe, "private_dns", return_value={}), \
                patch.object(probe, "request_json", return_value=(200, {"access_token": "secret"})), \
                patch.object(probe.time, "sleep") as sleep:
            with self.assertRaisesRegex(RuntimeError, "Private storage read failed: HTTP 403"):
                probe.check_storage(opener, endpoint, None)
        self.assertEqual(12, opener.open.call_count)
        self.assertEqual(11, sleep.call_count)

    def test_rejects_public_or_wrong_private_dns(self):
        for addresses in (["10.247.1.4", "20.10.0.1"], ["10.20.1.4"], []):
            records = [(2, 1, 6, "", (address, 443)) for address in addresses]
            with self.subTest(addresses=addresses), patch.object(probe.socket, "getaddrinfo", return_value=records):
                with self.assertRaises(RuntimeError):
                    probe.private_dns("gateway.example", ipaddress.ip_network("10.247.1.0/24"))

    def configuration(self, **overrides):
        return {
            "gateway_id": "/subscriptions/test/resourceGroups/test/providers/Microsoft.ApiManagement/service/test",
            "gateway_endpoint": "https://gateway.example",
            "model_endpoint": "https://model.example",
            "private_endpoint_subnet": "10.247.1.0/24",
            "model_names": ["mini", "full"],
            "model_apis": {
                model: {
                    "api_format": "OpenAIChatCompletions",
                    "endpoints": ["/openai/v1/chat/completions", "/openai/v1/responses"],
                }
                for model in ("mini", "full")
            },
            **overrides,
        }

    def run_probe(self, replies, configuration=None, addresses=None):
        configuration = configuration or self.configuration()
        responses = [
            (200, {"access_token": "test-token-must-not-appear"}),
            (200, {"primaryKey": "test-key-must-not-appear"}),
        ] + [(200, {"choices": [{"message": {"content": reply}}]}) for reply in replies] + [
            urllib.error.HTTPError("https://gateway.example", 401, "Unauthorized", {}, None),
            urllib.error.HTTPError("https://gateway.example", 401, "Unauthorized", {}, None),
        ]
        if "storage_endpoint" in configuration:
            responses.insert(0, (200, {"access_token": "storage-token-must-not-appear"}))
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.status = 200
        response.read.return_value = b"<EnumerationResults><Containers/></EnumerationResults>"

        def resolve(host, *_):
            return [(2, 1, 6, "", (address, 443)) for address in
                    (addresses[host] if addresses is not None else ["10.247.1.4"])]

        output = io.StringIO()
        with patch.object(probe.sys, "argv", ["probe", "--configuration", json.dumps(configuration)]), \
                patch.object(probe.socket, "getaddrinfo", side_effect=resolve), \
                patch.object(probe.urllib.request, "build_opener", return_value=opener), \
                patch.object(probe, "request_json", side_effect=responses), contextlib.redirect_stdout(output):
            probe.main()
        return output.getvalue()

    def test_checks_all_aliases_without_emitting_credentials(self):
        output = self.run_probe(["OK", "OK"])
        result = json.loads(output)
        self.assertTrue(result["passed"])
        self.assertEqual(["mini", "full"], [entry["model"] for entry in result["inference"]])
        self.assertEqual([401, 401], [entry["status"] for entry in result["authentication"]])
        for entry in result["inference"]:
            self.assertRegex(entry["trace_id"], r"^[a-f0-9]{32}$")
        for entry in result["dns"]:
            self.assertEqual("10.247.1.0/24", entry["expected_subnet"])
            self.assertEqual(["10.247.1.0/24"], entry["expected_subnets"])
        self.assertNotIn("test-token-must-not-appear", output)
        self.assertNotIn("test-key-must-not-appear", output)

    def test_service_specific_subnets_are_authoritative_including_storage(self):
        configuration = self.configuration(
            private_endpoint_subnets={
                "gateway": ["10.10.1.0/24", "10.10.2.0/24"],
                "models": ["10.20.1.0/24"],
                "storage": ["10.30.1.0/24"],
                "unused-service": None,
            },
            storage_endpoint="https://storage.blob.core.windows.net/",
        )
        addresses = {
            "gateway.example": ["10.10.1.4", "10.10.2.4"],
            "model.example": ["10.20.1.4"],
            "storage.blob.core.windows.net": ["10.30.1.7"],
        }
        output = self.run_probe(["OK", "OK"], configuration, addresses)
        result = json.loads(output)
        self.assertTrue(result["passed"])
        self.assertEqual(["10.10.1.0/24", "10.10.2.0/24"], result["dns"][0]["expected_subnets"])
        self.assertIsNone(result["dns"][0]["expected_subnet"])
        self.assertEqual(["10.20.1.0/24"], result["dns"][1]["expected_subnets"])
        self.assertEqual(["10.30.1.0/24"], result["storage"]["dns"]["expected_subnets"])
        self.assertNotIn("storage-token-must-not-appear", output)
        for host, wrong in (
            ("gateway.example", ["10.20.1.4"]),
            ("model.example", ["10.10.1.4"]),
            ("storage.blob.core.windows.net", ["10.10.1.7"]),
            ("gateway.example", ["10.10.1.4", "20.10.1.4"]),
        ):
            with self.subTest(host=host, wrong=wrong), self.assertRaisesRegex(RuntimeError, "resolve exclusively"):
                self.run_probe(["OK", "OK"], configuration, {**addresses, host: wrong})

    def test_malformed_new_metadata_never_falls_back_to_legacy_subnet(self):
        for metadata, storage in (
            (None, False),
            ({}, False),
            ({"gateway": ["10.247.1.0/24"]}, False),
            ({"gateway": "10.247.1.0/24", "models": ["10.247.1.0/24"]}, False),
            ({"gateway": ["10.247.1.0/24"], "models": []}, False),
            ({"gateway": ["10.247.1.0/24"], "models": ["not-a-cidr"]}, False),
            ({"gateway": ["10.247.1.0/24"], "models": [42]}, False),
            ({"gateway": ["10.247.1.0/24"], "models": ["10.247.1.4/24"]}, False),
            ({"gateway": ["10.247.1.0/24"], "models": ["10.247.1.0/24"]}, True),
        ):
            configuration = self.configuration(private_endpoint_subnets=metadata)
            if storage:
                configuration["storage_endpoint"] = "https://storage.blob.core.windows.net/"
            with self.subTest(metadata=metadata, storage=storage), \
                    patch.object(probe.sys, "argv", ["probe", "--configuration", json.dumps(configuration)]), \
                    patch.object(probe.socket, "getaddrinfo") as dns, \
                    patch.object(probe, "request_json") as request:
                with self.assertRaisesRegex(RuntimeError, "CIDR|private_endpoint_subnets"):
                    probe.main()
                dns.assert_not_called()
                request.assert_not_called()

    def test_dns_checks_all_address_families_against_explicit_ranges(self):
        subnets = (ipaddress.ip_network("10.247.1.0/24"), ipaddress.ip_network("fd00:1::/64"))
        records = [(2, 1, 6, "", ("10.247.1.4", 443)), (10, 1, 6, "", ("fd00:1::4", 443, 0, 0))]
        with patch.object(probe.socket, "getaddrinfo", return_value=records):
            self.assertEqual(["10.247.1.4", "fd00:1::4"], probe.private_dns("gateway.example", subnets)["addresses"])
        records.append((10, 1, 6, "", ("2001:4860::1", 443, 0, 0)))
        with patch.object(probe.socket, "getaddrinfo", return_value=records):
            with self.assertRaisesRegex(RuntimeError, "resolve exclusively"):
                probe.private_dns("gateway.example", subnets)

    def test_rejects_success_status_with_wrong_model_reply(self):
        with self.assertRaisesRegex(RuntimeError, "Inference failed for full"):
            self.run_probe(["OK", "unexpected"])

    def test_negative_auth_requires_a_real_rejection(self):
        for code, message, accepted in (
            (401, "Unauthorized", True),
            (403, "Invalid API key", True),
            (403, "Blocked by firewall", False),
            (500, "Internal error", False),
            (429, "Rate limited", False),
        ):
            error = urllib.error.HTTPError(
                "https://gateway.example", code, message, {},
                io.BytesIO(json.dumps({"message": message}).encode()),
            )
            with self.subTest(code=code, message=message), \
                    patch.object(probe, "request_json", side_effect=error):
                if accepted:
                    self.assertEqual(code, probe.check_key_rejection(None, "https://gateway.example", {}, {}))
                else:
                    with self.assertRaisesRegex(RuntimeError, "not proven"):
                        probe.check_key_rejection(None, "https://gateway.example", {}, {})
        with patch.object(probe, "request_json", return_value=(200, {})):
            with self.assertRaisesRegex(RuntimeError, "accepted"):
                probe.check_key_rejection(None, "https://gateway.example", {}, {})

    def test_rejects_unsupported_apis_before_dns_or_credentials(self):
        for metadata in (
            None,
            {},
            {"mini": {"api_format": "OpenAIChatCompletions", "endpoints": ["/openai/v1/responses"]}},
            {"mini": {"api_format": "Other", "endpoints": ["/openai/v1/chat/completions"]}},
            {"mini": {"api_format": "OpenAIChatCompletions", "endpoints": []}},
        ):
            configuration = {"model_names": ["mini"], "model_apis": metadata}
            with self.subTest(metadata=metadata), \
                    patch.object(probe.sys, "argv", ["probe", "--configuration", json.dumps(configuration)]), \
                    patch.object(probe.socket, "getaddrinfo") as dns, \
                    patch.object(probe, "request_json") as request:
                with self.assertRaisesRegex(RuntimeError, "metadata|Unsupported probe API"):
                    probe.main()
                dns.assert_not_called()
                request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
