import json
import functions_framework


@functions_framework.http
def add(request):
    try:
        a = float(request.args.get("a", 0))
        b = float(request.args.get("b", 0))
    except (TypeError, ValueError):
        return (
            json.dumps({"error": "a and b must be numbers"}),
            400,
            {"Content-Type": "application/json"},
        )
    return (
        json.dumps({"result": a + b}),
        200,
        {"Content-Type": "application/json"},
    )
