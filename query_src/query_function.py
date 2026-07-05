import json
import os

import boto3  # built into the Lambda runtime

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def lambda_handler(event, context):
    """Triggered by API Gateway (HTTP API). Reads one record from DynamoDB
    by its image_id and returns it as JSON.
    """
    # The greedy path variable {id+} captures the full key, including slashes
    # (our IDs look like "uploads/test.jpg").
    image_id = (event.get("pathParameters") or {}).get("id")

    if not image_id:
        return _response(400, {"error": "missing image id in path"})

    result = table.get_item(Key={"image_id": image_id})
    item = result.get("Item")

    if not item:
        return _response(404, {"error": f"no record found for '{image_id}'"})

    return _response(200, item)


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        # default=str converts DynamoDB's Decimal numbers into JSON-safe text.
        "body": json.dumps(body, default=str),
    }
