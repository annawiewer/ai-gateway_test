"""Run inside the private test VM; emit only non-secret DNS/inference results."""

import argparse
import ipaddress
import json
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET


def request_json(opener, url, headers=None, body=None):
    payload = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=payload, headers=headers or {})
    with opener.open(request, timeout=90) as response:
        return response.status, json.load(response)


def endpoint_subnets(configuration):
    services = ["gateway", "models"]
    if "storage_endpoint" in configuration:
        services.append("storage")
    if "private_endpoint_subnets" in configuration:
        metadata = configuration["private_endpoint_subnets"]
        if not isinstance(metadata, dict):
            raise RuntimeError("private_endpoint_subnets must be a map of service CIDR lists.")
    else:
        metadata = {service: [configuration.get("private_endpoint_subnet")] for service in services}
    result = {}
    for service in services:
        prefixes = metadata.get(service)
        if not isinstance(prefixes, list) or not prefixes:
            raise RuntimeError(f"Missing or invalid private endpoint CIDR list for {service}.")
        try:
            if any(not isinstance(prefix, str) or "/" not in prefix for prefix in prefixes):
                raise ValueError
            result[service] = tuple(ipaddress.ip_network(prefix) for prefix in prefixes)
        except ValueError:
            raise RuntimeError(f"Invalid private endpoint CIDR for {service}.") from None
    return result


def private_dns(host, subnets):
    if isinstance(subnets, (ipaddress.IPv4Network, ipaddress.IPv6Network)):
        subnets = (subnets,)
    addresses = sorted({entry[4][0] for entry in socket.getaddrinfo(host, 443, socket.AF_UNSPEC)})
    if not addresses or not all(
        any(ipaddress.ip_address(address) in subnet for subnet in subnets) for address in addresses
    ):
        raise RuntimeError(
            f"{host} did not resolve exclusively inside {[str(subnet) for subnet in subnets]}: {addresses}"
        )
    return {
        "host": host, "addresses": addresses,
        "expected_subnets": [str(subnet) for subnet in subnets],
        "expected_subnet": str(subnets[0]) if len(subnets) == 1 else None,
    }


def validate_model_apis(configuration):
    models = configuration.get("model_names")
    apis = configuration.get("model_apis")
    if not models or not isinstance(apis, dict):
        raise RuntimeError("Model API metadata is required; use the current Terraform outputs and wrapper.")
    for model in models:
        api = apis.get(model)
        if (
            not isinstance(api, dict)
            or api.get("api_format") != "OpenAIChatCompletions"
            or "/openai/v1/chat/completions" not in (api.get("endpoints") or [])
        ):
            raise RuntimeError(
                f"Unsupported probe API for {model}: requires OpenAIChatCompletions and "
                "/openai/v1/chat/completions. Use a model-specific test; this is not a network failure."
            )


def check_key_rejection(opener, url, body, headers):
    try:
        request_json(opener, url, headers, body)
    except urllib.error.HTTPError as error:
        if error.code == 401:
            return error.code
        if error.code == 403:
            try:
                response = json.load(error)
            except (ValueError, UnicodeError):
                raise RuntimeError("Unclassified HTTP 403; authentication rejection not proven") from None
            if not isinstance(response, dict):
                raise RuntimeError("Unclassified HTTP 403; authentication rejection not proven") from None
            detail = response.get("error")
            nested_message = detail.get("message", "") if isinstance(detail, dict) else ""
            message = str(response.get("message", nested_message)).lower()
            if any(term in message for term in ("api key", "api-key", "authentication", "subscription key")):
                return error.code
        raise RuntimeError(f"Authentication rejection not proven: HTTP {error.code}") from None
    raise RuntimeError("Gateway accepted a missing or invalid runtime key")


def check_storage(opener, endpoint, subnets):
    parsed = urllib.parse.urlsplit(endpoint)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or not parsed.hostname.endswith(".blob.core.windows.net")
        or parsed.username or parsed.password or parsed.port not in (None, 443)
        or parsed.path not in ("", "/") or parsed.query or parsed.fragment
    ):
        raise RuntimeError("Invalid storage endpoint for the private Blob probe")
    dns = private_dns(parsed.hostname, subnets)
    _, identity = request_json(
        opener,
        "http://169.254.169.254/metadata/identity/oauth2/token"
        "?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F",
        {"Metadata": "true"},
    )
    request = urllib.request.Request(
        endpoint.rstrip("/") + "/?comp=list&maxresults=1",
        headers={"Authorization": "Bearer " + identity["access_token"], "x-ms-version": "2023-11-03"},
    )
    for attempt in range(12):
        try:
            with opener.open(request, timeout=90) as response:
                if response.status != 200:
                    raise RuntimeError(f"Private storage read failed: HTTP {response.status}")
                try:
                    root = ET.fromstring(response.read(1024 * 1024))
                except ET.ParseError:
                    raise RuntimeError("Private storage returned an invalid list-containers response") from None
                if root.tag != "EnumerationResults" or root.find("Containers") is None:
                    raise RuntimeError("Private storage returned an unexpected list-containers response")
                return {"dns": dns, "status": 200, "operation": "list-containers", "authentication": "ManagedIdentity"}
        except urllib.error.HTTPError as error:
            if error.code != 403 or attempt == 11:
                raise RuntimeError(f"Private storage read failed: HTTP {error.code}") from None
            time.sleep(15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", required=True, help="JSON from private_probe_configuration output.")
    args = parser.parse_args()
    configuration = json.loads(args.configuration)
    validate_model_apis(configuration)
    subnets = endpoint_subnets(configuration)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    gateway = configuration["gateway_endpoint"].rstrip("/")
    dns = [
        private_dns(urllib.parse.urlsplit(endpoint).hostname, subnets[service])
        for service, endpoint in (("gateway", gateway), ("models", configuration["model_endpoint"]))
    ]
    storage = (
        check_storage(opener, configuration["storage_endpoint"], subnets["storage"])
        if "storage_endpoint" in configuration else None
    )
    _, identity = request_json(
        opener,
        "http://169.254.169.254/metadata/identity/oauth2/token"
        "?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F",
        {"Metadata": "true"},
    )
    key_url = (
        "https://management.azure.com" + configuration["gateway_id"]
        + "/apiKeys/default/listSecrets?api-version=2025-09-01-preview"
    )
    # A new role assignment can take time to reach ARM's authorization cache.
    for attempt in range(12):
        try:
            _, secrets = request_json(
                opener, key_url, {"Authorization": "Bearer " + identity["access_token"]}, {}
            )
            break
        except urllib.error.HTTPError as error:
            if error.code != 403 or attempt == 11:
                raise RuntimeError(f"Managed identity key retrieval failed: HTTP {error.code}") from None
            time.sleep(15)
    key = secrets["primaryKey"]
    results = []
    url = gateway + "/default/models/openai/v1/chat/completions"
    for model in configuration["model_names"]:
        trace_id = uuid.uuid4().hex
        status, response = request_json(
            opener,
            url,
            {
                "Content-Type": "application/json",
                "Api-Key": key,
                "traceparent": f"00-{trace_id}-{uuid.uuid4().hex[:16]}-01",
            },
            {
                "model": model,
                "messages": [{"role": "user", "content": "Reply with exactly OK."}],
                "max_tokens": 8,
                "temperature": 0,
            },
        )
        text = response["choices"][0]["message"]["content"].strip()
        if status != 200 or text != "OK":
            raise RuntimeError(f"Inference failed for {model}: HTTP {status}, unexpected reply")
        usage = response.get("usage")
        safe_usage = None if not isinstance(usage, dict) else {
            name: usage[name] for name in ("prompt_tokens", "completion_tokens", "total_tokens")
            if type(usage.get(name)) is int and usage[name] >= 0
        }
        results.append({
            "model": model, "status": status, "reply": text,
            "trace_id": trace_id, "usage": safe_usage,
        })
    body = {
        "model": configuration["model_names"][0],
        "messages": [{"role": "user", "content": "Reply with exactly OK."}],
        "max_tokens": 8,
        "temperature": 0,
    }
    authentication = [
        {"case": name, "status": check_key_rejection(opener, url, body, headers)}
        for name, headers in (
            ("missing-key", {"Content-Type": "application/json"}),
            ("invalid-key", {"Content-Type": "application/json", "Api-Key": "invalid-acceptance-key"}),
        )
    ]
    print(json.dumps({
        "run_id": configuration.get("run_id"),
        "dns": dns, "inference": results, "authentication": authentication, "passed": True,
        **({"storage": storage} if storage is not None else {}),
    }))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, IndexError, RuntimeError) as error:
        # Do not emit request headers, tokens, keys, or unfiltered service bodies.
        message = f"HTTP {error.code}" if isinstance(error, urllib.error.HTTPError) else str(error)
        print(json.dumps({"passed": False, "error": message}), file=sys.stderr)
        sys.exit(1)
