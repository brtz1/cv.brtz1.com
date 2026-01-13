import os
import json
import boto3

ddb = boto3.client("dynamodb")

TABLE_NAME = os.environ.get("TABLE_NAME", "cv-visitor-counter")
COUNTER_ID = os.environ.get("COUNTER_ID", "cv.brtz1.com")

def _method(event):
    rc = (event or {}).get("requestContext", {})
    http = rc.get("http", {})
    if "method" in http:
        return http["method"]
    if "httpMethod" in (event or {}):
        return event["httpMethod"]
    return "GET"

def lambda_handler(event, context):
    method = _method(event)

    # Preflight (Function URL can handle this too; harmless)
    if method == "OPTIONS":
        return {"statusCode": 204, "headers": {}, "body": ""}

    if method == "GET":
        resp = ddb.get_item(
            TableName=TABLE_NAME,
            Key={"id": {"S": COUNTER_ID}}
        )
        count = 0
        if "Item" in resp and "count" in resp["Item"]:
            count = int(resp["Item"]["count"]["N"])
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"id": COUNTER_ID, "count": count})
        }

    if method == "POST":
        resp = ddb.update_item(
            TableName=TABLE_NAME,
            Key={"id": {"S": COUNTER_ID}},
            UpdateExpression="SET #c = if_not_exists(#c, :zero) + :inc",
            ExpressionAttributeNames={"#c": "count"},
            ExpressionAttributeValues={
                ":inc": {"N": "1"},
                ":zero": {"N": "0"}
            },
            ReturnValues="UPDATED_NEW"
        )
        new_count = int(resp["Attributes"]["count"]["N"])
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"id": COUNTER_ID, "count": new_count})
        }

    return {
        "statusCode": 405,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "Method not allowed"})
    }
