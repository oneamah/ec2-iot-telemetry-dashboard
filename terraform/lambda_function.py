import json
import os
from decimal import Decimal

import boto3


TABLE_NAME = os.environ["TABLE_NAME"]
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def to_decimal(value):
    if isinstance(value, float):
        return Decimal(str(value))
    if isinstance(value, list):
        return [to_decimal(item) for item in value]
    if isinstance(value, dict):
        return {key: to_decimal(item) for key, item in value.items()}
    return value


def lambda_handler(event, _context):
    payload = dict(event)
    thing_name = payload.get("thing_name", "unknown")
    timestamp = payload.get("ts")

    if timestamp is None:
        raise ValueError("Incoming IoT payload must contain a ts field")

    item = {
        "thing_name": thing_name,
        "ts": int(timestamp),
        "instance_id": payload.get("instance_id", "unknown"),
        "cpu_percent": payload.get("cpu_percent", 0),
        "timestamp": payload.get("timestamp"),
        "memory": payload.get("memory"),
        "disk": payload.get("disk"),
        "network": payload.get("network"),
        "load_average": payload.get("load_average"),
        "battery": payload.get("battery"),
        "process_count": payload.get("process_count"),
        "uptime_seconds": payload.get("uptime_seconds"),
        "payload": payload,
    }

    table.put_item(Item=to_decimal(item))

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "stored": True,
                "thing_name": thing_name,
                "ts": int(timestamp),
            }
        ),
    }