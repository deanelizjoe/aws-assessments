#!/usr/bin/env python3
"""
tests/integration_test.py

Automated integration test for the multi-region AWS compute stack.

Steps:
  1. Authenticates with Cognito (us-east-1) to obtain a JWT.
  2. Concurrently calls /greet on both regions and asserts region correctness.
  3. Concurrently calls /dispatch on both regions to trigger Fargate tasks.
  4. Prints a latency comparison table.

Usage:
  export COGNITO_USER_POOL_ID=us-east-1_xxxxxxxx
  export COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
  export COGNITO_USERNAME=your@email.com
  export COGNITO_PASSWORD=YourPassword123!
  export API_URL_USE1=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com
  export API_URL_EUW1=https://xxxxxxxxxx.execute-api.eu-west-1.amazonaws.com

  python tests/integration_test.py

  # Or via pytest:
  pytest tests/integration_test.py -v
"""

import concurrent.futures
import json
import os
import sys
import time
from dataclasses import dataclass, field
from typing import Optional

import boto3
import requests
from botocore.exceptions import ClientError

# ── ANSI colours ─────────────────────────────────────────────────────────────
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"


# ══════════════════════════════════════════════════════════════════════════════
# Configuration
# ══════════════════════════════════════════════════════════════════════════════

def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        print(f"{RED}✗ Missing required environment variable: {name}{RESET}")
        sys.exit(1)
    return value


@dataclass
class Config:
    cognito_user_pool_id: str = field(default_factory=lambda: _require_env("COGNITO_USER_POOL_ID"))
    cognito_client_id: str = field(default_factory=lambda: _require_env("COGNITO_CLIENT_ID"))
    username: str = field(default_factory=lambda: _require_env("COGNITO_USERNAME"))
    password: str = field(default_factory=lambda: _require_env("COGNITO_PASSWORD"))
    api_url_use1: str = field(default_factory=lambda: _require_env("API_URL_USE1"))
    api_url_euw1: str = field(default_factory=lambda: _require_env("API_URL_EUW1"))

    # Expected region identifiers returned by each endpoint
    expected_region_use1: str = "us-east-1"
    expected_region_euw1: str = "eu-west-1"


# ══════════════════════════════════════════════════════════════════════════════
# Step 1 — Cognito Authentication
# ══════════════════════════════════════════════════════════════════════════════

def authenticate(cfg: Config) -> str:
    """
    Exchange username + password for a Cognito JWT (IdToken).
    Uses USER_PASSWORD_AUTH flow — no SRP challenge.
    """
    print(f"\n{BOLD}{CYAN}═══ Step 1: Cognito Authentication ═══{RESET}")
    print(f"  Pool  : {cfg.cognito_user_pool_id}")
    print(f"  Client: {cfg.cognito_client_id}")
    print(f"  User  : {cfg.username}")

    client = boto3.client("cognito-idp", region_name="us-east-1")

    try:
        t0 = time.monotonic()
        response = client.initiate_auth(
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": cfg.username,
                "PASSWORD": cfg.password,
            },
            ClientId=cfg.cognito_client_id,
        )
        latency = (time.monotonic() - t0) * 1000

        # Handle NEW_PASSWORD_REQUIRED challenge (first-time login)
        if response.get("ChallengeName") == "NEW_PASSWORD_REQUIRED":
            print(f"  {YELLOW}⚠  NEW_PASSWORD_REQUIRED challenge detected.{RESET}")
            print(f"  {YELLOW}   Set a permanent password and re-run the test.{RESET}")
            sys.exit(1)

        token = response["AuthenticationResult"]["IdToken"]
        print(f"  {GREEN}✓ Authenticated in {latency:.0f} ms — JWT obtained{RESET}")
        return token

    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        print(f"  {RED}✗ Cognito auth failed [{code}]: {exc}{RESET}")
        sys.exit(1)


# ══════════════════════════════════════════════════════════════════════════════
# HTTP helpers
# ══════════════════════════════════════════════════════════════════════════════

@dataclass
class ApiResult:
    region_label: str      # e.g. "us-east-1"
    endpoint: str          # e.g. "/greet"
    status_code: int
    body: dict
    latency_ms: float
    error: Optional[str] = None

    @property
    def ok(self) -> bool:
        return self.status_code == 200 and self.error is None


def call_endpoint(
    region_label: str,
    base_url: str,
    path: str,
    token: str,
    method: str = "GET",
    timeout: int = 30,
) -> ApiResult:
    url = base_url.rstrip("/") + path
    headers = {"Authorization": token, "Content-Type": "application/json"}

    try:
        t0 = time.monotonic()
        if method.upper() == "POST":
            resp = requests.post(url, headers=headers, timeout=timeout)
        else:
            resp = requests.get(url, headers=headers, timeout=timeout)
        latency_ms = (time.monotonic() - t0) * 1000

        try:
            body = resp.json()
        except ValueError:
            body = {"raw": resp.text}

        return ApiResult(
            region_label=region_label,
            endpoint=path,
            status_code=resp.status_code,
            body=body,
            latency_ms=latency_ms,
        )

    except requests.RequestException as exc:
        return ApiResult(
            region_label=region_label,
            endpoint=path,
            status_code=0,
            body={},
            latency_ms=0,
            error=str(exc),
        )


# ══════════════════════════════════════════════════════════════════════════════
# Step 2 — Concurrent /greet calls
# ══════════════════════════════════════════════════════════════════════════════

def test_greet(cfg: Config, token: str) -> list[ApiResult]:
    print(f"\n{BOLD}{CYAN}═══ Step 2: Concurrent /greet calls ═══{RESET}")

    tasks = [
        (cfg.expected_region_use1, cfg.api_url_use1, "/greet", token, "GET"),
        (cfg.expected_region_euw1, cfg.api_url_euw1, "/greet", token, "GET"),
    ]

    results = _run_concurrent(tasks)
    _print_results(results)

    # ── Assertions ───────────────────────────────────────────────────────────
    failures = []
    for r in results:
        if not r.ok:
            failures.append(f"  {r.region_label} returned HTTP {r.status_code}: {r.error or r.body}")
            continue

        returned_region = r.body.get("region", "")
        if returned_region != r.region_label:
            failures.append(
                f"  {r.region_label}: payload region mismatch — "
                f"expected '{r.region_label}', got '{returned_region}'"
            )
        else:
            print(f"  {GREEN}✓ [{r.region_label}] region assertion PASSED "
                  f"(payload.region == '{returned_region}'){RESET}")

    if failures:
        for f in failures:
            print(f"{RED}{f}{RESET}")
        raise AssertionError("/greet assertions failed")

    return results


# ══════════════════════════════════════════════════════════════════════════════
# Step 3 — Concurrent /dispatch calls
# ══════════════════════════════════════════════════════════════════════════════

def test_dispatch(cfg: Config, token: str) -> list[ApiResult]:
    print(f"\n{BOLD}{CYAN}═══ Step 3: Concurrent /dispatch calls ═══{RESET}")

    tasks = [
        (cfg.expected_region_use1, cfg.api_url_use1, "/dispatch", token, "POST"),
        (cfg.expected_region_euw1, cfg.api_url_euw1, "/dispatch", token, "POST"),
    ]

    results = _run_concurrent(tasks)
    _print_results(results)

    failures = []
    for r in results:
        if not r.ok:
            failures.append(f"  {r.region_label} /dispatch returned HTTP {r.status_code}: {r.error or r.body}")
            continue

        returned_region = r.body.get("region", "")
        if returned_region != r.region_label:
            failures.append(
                f"  {r.region_label}: region mismatch — "
                f"expected '{r.region_label}', got '{returned_region}'"
            )
        else:
            task_arn = r.body.get("taskArn", "N/A")
            print(f"  {GREEN}✓ [{r.region_label}] ECS task dispatched — ARN: {task_arn}{RESET}")

    if failures:
        for f in failures:
            print(f"{RED}{f}{RESET}")
        raise AssertionError("/dispatch assertions failed")

    return results


# ══════════════════════════════════════════════════════════════════════════════
# Step 4 — Latency summary
# ══════════════════════════════════════════════════════════════════════════════

def print_latency_summary(greet_results: list[ApiResult], dispatch_results: list[ApiResult]) -> None:
    print(f"\n{BOLD}{CYAN}═══ Step 4: Latency Summary ═══{RESET}")
    print(f"\n  {'Endpoint':<12}  {'Region':<12}  {'Latency (ms)':>14}  Status")
    print(f"  {'─' * 12}  {'─' * 12}  {'─' * 14}  {'─' * 10}")

    all_results = greet_results + dispatch_results
    for r in sorted(all_results, key=lambda x: (x.endpoint, x.region_label)):
        status = f"{GREEN}200 OK{RESET}" if r.ok else f"{RED}{r.status_code} ERR{RESET}"
        latency_str = f"{r.latency_ms:.1f}" if r.latency_ms else "N/A"
        print(f"  {r.endpoint:<12}  {r.region_label:<12}  {latency_str:>14}  {status}")

    # Geographic performance insight
    greet_by_region = {r.region_label: r.latency_ms for r in greet_results if r.ok}
    if len(greet_by_region) == 2:
        use1 = greet_by_region.get("us-east-1", 0)
        euw1 = greet_by_region.get("eu-west-1", 0)
        diff = abs(use1 - euw1)
        faster = "us-east-1" if use1 < euw1 else "eu-west-1"
        print(
            f"\n  {YELLOW}ℹ  Geographic latency delta: {diff:.1f} ms "
            f"({faster} responded faster from this client){RESET}"
        )


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

def _run_concurrent(tasks) -> list[ApiResult]:
    """Execute API calls concurrently using a thread pool."""
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(tasks)) as executor:
        futures = {
            executor.submit(call_endpoint, *task): task[0]
            for task in tasks
        }
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())
    return results


def _print_results(results: list[ApiResult]) -> None:
    for r in sorted(results, key=lambda x: x.region_label):
        icon = GREEN + "✓" + RESET if r.ok else RED + "✗" + RESET
        print(f"\n  {icon} [{r.region_label}] HTTP {r.status_code} — {r.latency_ms:.1f} ms")
        print(f"    Body: {json.dumps(r.body, indent=2)[:300]}")


# ══════════════════════════════════════════════════════════════════════════════
# pytest-compatible test functions
# ══════════════════════════════════════════════════════════════════════════════

_cfg: Optional[Config] = None
_token: Optional[str] = None
_greet_results: list[ApiResult] = []
_dispatch_results: list[ApiResult] = []


def setup_module(_module):
    """Called once before all tests in this module."""
    global _cfg, _token
    _cfg = Config()
    _token = authenticate(_cfg)


def test_greet_both_regions():
    global _greet_results
    _greet_results = test_greet(_cfg, _token)


def test_dispatch_both_regions():
    global _dispatch_results
    _dispatch_results = test_dispatch(_cfg, _token)


def test_latency_summary():
    print_latency_summary(_greet_results, _dispatch_results)


# ══════════════════════════════════════════════════════════════════════════════
# Script entry point
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print(f"\n{BOLD}AWS Multi-Region Integration Test Suite{RESET}")
    print("=" * 50)

    cfg = Config()
    token = authenticate(cfg)

    greet_results = test_greet(cfg, token)
    dispatch_results = test_dispatch(cfg, token)
    print_latency_summary(greet_results, dispatch_results)

    # Final verdict
    all_passed = all(r.ok for r in greet_results + dispatch_results)
    if all_passed:
        print(f"\n{BOLD}{GREEN}✓ All tests PASSED{RESET}\n")
        sys.exit(0)
    else:
        print(f"\n{BOLD}{RED}✗ Some tests FAILED — see above{RESET}\n")
        sys.exit(1)
