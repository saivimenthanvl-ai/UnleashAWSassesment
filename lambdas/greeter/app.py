import json
import os
import time
import uuid
from decimal import Decimal

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
CANDIDATE_EMAIL = os.environ["CANDIDATE_EMAIL"]
REPO_URL = os.environ["REPO_URL"]
EXECUTING_REGION = os.environ["EXECUTING_REGION"]


dynamodb = boto3.resource("dynamodb", region_name=EXECUTING_REGION)
table = dynamodb.Table(TABLE_NAME)
sns = boto3.client("sns", region_name=EXECUTING_REGION)


def lambda_handler(event, context):
    request_id = event.get("requestContext", {}).get("requestId", str(uuid.uuid4()))
    now = int(time.time())

    table.put_item(
        Item={
            "request_id": request_id,
            "created_at": Decimal(now),
            "region": EXECUTING_REGION,
            "path": event.get("rawPath", "/greet"),
            "method": event.get("requestContext", {}).get("http", {}).get("method", "GET"),
        }
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=json.dumps(
            {
                "email": CANDIDATE_EMAIL,
                "source": "Lambda",
                "region": EXECUTING_REGION,
                "repo": REPO_URL,
            }
        ),
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "message": "hello from greeter",
                "region": EXECUTING_REGION,
                "request_id": request_id,
            }
        ),
    }


if __name__ == "__main__":
    test_event = {
        "requestContext": {
            "requestId": "test-123",
            "http": {"method": "GET"}
        },
        "rawPath": "/greet"
    }
    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))
