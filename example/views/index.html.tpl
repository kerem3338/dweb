<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dweb</title>
    {{ include(cwd() + "\views\style.html.tpl") }}
</head>
<body>
    <h1>Example Dweb Application</h1>
    <hr>
    <p>This is a example application using <a href="https://github.com/kerem3338/dweb">Dweb</a></p>

    <h3>Routes</h3>
    <a href="{{ url_for("error_500") }}">Get Interal Server Error</a><br>
    <a href="{{ url_for("user_profile", id=1) }}">Visit User Profile 1</a><br>
    <a href="{{ url_for("user_profile", id=99) }}">Visit User Profile 99</a><br>
    <a href="{{ url_for("json", id=99) }}">JSON Response Route</a><br>

    <br>
    This application is running on a <b>{{ os() }}</b> machine.
   	<br>
   	Z-Template Engine Version: {{ __version__ }}
</body>
</html>
