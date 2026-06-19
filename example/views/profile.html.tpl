<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Profile: {{ name }}</title>
    {{ include(cwd() + "\views\style.html.tpl") }}
</head>
<body>
    <h1>Profile</h1>

    {# Greet the user by name #}
    <p>Hello, <strong>{{ name }}</strong>!</p>

    {% if (is_admin == "true") %}
    <p class="badge">🛡 Admin</p>
    {% else %}
    <p class="badge">👤 Regular user</p>
    {% endif %}

    <ul>
        <li>User ID: {{ id }}</li>
        <li>Username: {{ name }}</li>
    </ul>

    <nav>
        <a href="{{ url_for("index") }}">← Back to Home</a>
    </nav>
</body>
</html>
