# pgAdmin

pgAdmin provides browser-based database administration and SQL access.
It starts alongside UTTDB with `docker compose up -d --build`.

1. Open [localhost:5050](http://localhost:5050), or the `PGADMIN_PORT` from `.env`.
2. Sign in with `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD`.
3. Open the preconfigured UTTDB server and enter `UTTDB_POSTGRES_PASSWORD`.

[servers.json](../pgadmin/servers.json) connects to `uttdb:5432` inside the Compose
network. If you customize the database name or username, adjust that registration.
Use the Query Tool for the [UTTDB SQL examples](uttdb.md).

Settings and accounts persist in ignored `pgadmin/data/`.
The initial login and server registration seed fresh state; changing configuration
may require updating an existing pgAdmin setup manually. Stop the stack before
deleting its data folder; deletion resets accounts, preferences and saved connections.
Database storage is separate.
