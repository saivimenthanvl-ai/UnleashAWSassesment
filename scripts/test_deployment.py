#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import sys
import time
from typing import Dict, Tuple

import boto3
import requests


def get_token(region: str, user_pool_client_id: str, username: str, password: str) -> str:
    cognito = boto3.client("cognito-idp", region_name=region)
    response = cognito.initiate_auth(
        ClientId=user_pool_client_id,
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={
            "USERNAME": username,
            "PASSWORD": password,
        },
    )
    return response["AuthenticationResult"]["IdToken"]


def invoke(method: str, url: str, token: str, expected_region: str) -> Dict:
    headers = {"Authorization": token}
    started = time.perf_counter()
    response = requests.request(method=method, url=url, headers=headers, timeout=30)
    elapsed_ms = (time.perf_counter() - started) * 1000

    try:
        payload = response.json()
    except ValueError:
        payload = {"raw": response.text}

    actual_region = payload.get("region")
    assertion = actual_region == expected_region

    return {
        "url": url,
        "status_code": response.status_code,
        "latency_ms": round(elapsed_ms, 2),
        "expected_region": expected_region,
        "actual_region": actual_region,
        "region_match": assertion,
        "payload": payload,
    }


def pretty_print(title: str, results: Dict[str, Dict]) -> None:
    print(f"\n=== {title} ===")
    for label, result in results.items():
        print(f"[{label}] status={result['status_code']} latency_ms={result['latency_ms']} expected={result['expected_region']} actual={result['actual_region']} match={result['region_match']}")
        print(json.dumps(result["payload"], indent=2))


def main() -> int:
    parser = argparse.ArgumentParser(description="Authenticate with Cognito and exercise both regional APIs.")
    parser.add_argument("--auth-region", default="us-east-1", help="Cognito region")
    parser.add_argument("--user-pool-client-id", required=True)
    parser.add_argument("--username", required=True, help="Candidate email address")
    parser.add_argument("--password", required=True)
    parser.add_argument("--region1-name", required=True)
    parser.add_argument("--region1-base-url", required=True)
    parser.add_argument("--region2-name", required=True)
    parser.add_argument("--region2-base-url", required=True)
    args = parser.parse_args()

    token = get_token(
        region=args.auth_region,
        user_pool_client_id=args.user_pool_client_id,
        username=args.username,
        password=args.password,
    )

    greet_targets: Dict[str, Tuple[str, str, str]] = {
        args.region1_name: ("GET", f"{args.region1_base_url}/greet", args.region1_name),
        args.region2_name: ("GET", f"{args.region2_base_url}/greet", args.region2_name),
    }

    dispatch_targets: Dict[str, Tuple[str, str, str]] = {
        args.region1_name: ("POST", f"{args.region1_base_url}/dispatch", args.region1_name),
        args.region2_name: ("POST", f"{args.region2_base_url}/dispatch", args.region2_name),
    }

    greet_results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        future_map = {
            executor.submit(invoke, method, url, token, expected_region): name
            for name, (method, url, expected_region) in greet_targets.items()
        }
        for future in concurrent.futures.as_completed(future_map):
            greet_results[future_map[future]] = future.result()

    dispatch_results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        future_map = {
            executor.submit(invoke, method, url, token, expected_region): name
            for name, (method, url, expected_region) in dispatch_targets.items()
        }
        for future in concurrent.futures.as_completed(future_map):
            dispatch_results[future_map[future]] = future.result()

    pretty_print("GREET RESULTS", greet_results)
    pretty_print("DISPATCH RESULTS", dispatch_results)

    failures = [
        result
        for result in list(greet_results.values()) + list(dispatch_results.values())
        if result["status_code"] >= 300 or not result["region_match"]
    ]

    if failures:
        print("\nOne or more checks failed.", file=sys.stderr)
        return 1

    print("\nAll regional checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
