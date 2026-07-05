import json
import os
from datetime import datetime, timezone
from urllib.parse import unquote_plus

import boto3  # pre-installed in the Lambda Python runtime — nothing to package

s3 = boto3.client("s3")
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def lambda_handler(event, context):
    """Triggered by SQS. Each SQS record wraps an S3 event notification.
    For every uploaded object we read its metadata and store a record in DynamoDB.
    """
    for record in event["Records"]:
        # The SQS message body is the S3 event notification (as JSON text).
        body = json.loads(record["body"])

        # When the S3 notification is first created, S3 sends a one-off
        # "s3:TestEvent" that has no "Records" key. Skip anything like that.
        if "Records" not in body:
            print("Skipping non-object message:", body.get("Event", "unknown"))
            continue

        for s3_record in body["Records"]:
            bucket = s3_record["s3"]["bucket"]["name"]
            # S3 URL-encodes keys (spaces -> +, etc.), so decode it back.
            key = unquote_plus(s3_record["s3"]["object"]["key"])

            # Read the object's metadata WITHOUT downloading the whole file.
            head = s3.head_object(Bucket=bucket, Key=key)

            item = {
                "image_id": key,
                "bucket": bucket,
                "size_bytes": head["ContentLength"],
                "content_type": head.get("ContentType", "unknown"),
                "uploaded_at": datetime.now(timezone.utc).isoformat(),
                "status": "processed",
            }

            table.put_item(Item=item)
            print(f"Stored metadata for '{key}' ({head['ContentLength']} bytes)")

    return {"statusCode": 200}
