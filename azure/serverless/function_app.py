import azure.functions as func
import json

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.route(route="add")
def add(req: func.HttpRequest) -> func.HttpResponse:
    try:
        a = float(req.params.get("a", 0))
        b = float(req.params.get("b", 0))
    except (TypeError, ValueError):
        return func.HttpResponse(
            json.dumps({"error": "a and b must be numbers"}),
            status_code=400,
            mimetype="application/json",
        )
    return func.HttpResponse(
        json.dumps({"result": a + b}),
        status_code=200,
        mimetype="application/json",
    )
