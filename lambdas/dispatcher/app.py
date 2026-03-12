import json
import os

import boto3

ECS_CLUSTER_ARN = os.environ["ECS_CLUSTER_ARN"]
ECS_TASK_DEFINITION_ARN = os.environ["ECS_TASK_DEFINITION_ARN"]
ECS_SUBNET_IDS = os.environ["ECS_SUBNET_IDS"].split(",")
ECS_SECURITY_GROUP_ID = os.environ["ECS_SECURITY_GROUP_ID"]
EXECUTING_REGION = os.environ["EXECUTING_REGION"]


ecs = boto3.client("ecs", region_name=EXECUTING_REGION)


def lambda_handler(event, context):
    response = ecs.run_task(
        cluster=ECS_CLUSTER_ARN,
        taskDefinition=ECS_TASK_DEFINITION_ARN,
        launchType="FARGATE",
        count=1,
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": ECS_SUBNET_IDS,
                "securityGroups": [ECS_SECURITY_GROUP_ID],
                "assignPublicIp": "ENABLED",
            }
        },
    )

    failures = response.get("failures", [])
    status_code = 200 if not failures else 500

    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "message": "dispatch requested",
                "region": EXECUTING_REGION,
                "tasks": [task["taskArn"] for task in response.get("tasks", [])],
                "failures": failures,
            }
        ),
    }
