import json


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    try:
        a = float(params.get("a", 0))
        b = float(params.get("b", 0))
    except (TypeError, ValueError):
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "a and b must be numbers"}),
        }
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"result": a + b}),
    }
