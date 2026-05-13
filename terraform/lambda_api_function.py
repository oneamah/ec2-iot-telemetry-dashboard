import json
import os
from decimal import Decimal
from urllib.parse import parse_qs

import boto3
from boto3.dynamodb.conditions import Key


TABLE_NAME = os.environ["TABLE_NAME"]
THING_NAME = os.environ["THING_NAME"]
DEFAULT_QUERY_LIMIT = int(os.environ.get("DEFAULT_QUERY_LIMIT", "20"))

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def from_dynamodb(value):
    if isinstance(value, list):
        return [from_dynamodb(item) for item in value]
    if isinstance(value, dict):
        return {key: from_dynamodb(item) for key, item in value.items()}
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    return value


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
            "access-control-allow-methods": "GET,OPTIONS",
        },
        "body": json.dumps(body),
    }


def normalize_item(item):
    payload = item.get("payload") or {}

    normalized = dict(item)
    normalized["memory"] = normalized.get("memory") or payload.get("memory")
    normalized["disk"] = normalized.get("disk") or payload.get("disk")
    normalized["network"] = normalized.get("network") or payload.get("network")
    normalized["load_average"] = normalized.get("load_average") or payload.get("load_average")
    normalized["battery"] = normalized.get("battery") or payload.get("battery")
    normalized["process_count"] = normalized.get("process_count") or payload.get("process_count")
    normalized["uptime_seconds"] = normalized.get("uptime_seconds") or payload.get("uptime_seconds")

    return normalized


def lambda_handler(event, _context):
    request_context = event.get("requestContext", {})
    http_method = request_context.get("http", {}).get("method", "GET")

    if http_method == "OPTIONS":
        return response(200, {"ok": True})

    params = event.get("queryStringParameters") or {}
    limit = int(params.get("limit", DEFAULT_QUERY_LIMIT))
    limit = max(1, min(limit, 100))

    thing_name = params.get("thingName", THING_NAME)

    result = table.query(
        KeyConditionExpression=Key("thing_name").eq(thing_name),
        ScanIndexForward=False,
        Limit=limit,
    )

    items = [normalize_item(from_dynamodb(item)) for item in result.get("Items", [])]

    return response(
        200,
        {
            "thingName": thing_name,
            "count": len(items),
            "items": items,
        },
    )
