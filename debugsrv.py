# sudo pacman -S python-bottle
# python debugsrv.py
from bottle import request, response, route, run


@route("/", method="POST")
def index():
    msg = ""

    msg += "Headers:\n"
    for k, v in request.headers.items():
        msg += f"{k}: {v}\n"

    msg += f"content_length: {request.content_length}"

    request.body.seek(0)
    msg += f"\nBody:***{request.body.getvalue().decode()}***"

    response.set_header("Content-Type", "text/plain")

    print(">>", msg)

    return msg


run(host="localhost", port=8080, debug=True, reloader=True)
