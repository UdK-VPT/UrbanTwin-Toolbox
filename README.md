# UrbanTwin-Toolbox

Currently a PostgreSQL/PostGIS foundation for urban digital twins to build upon.

This project is very much work in progress.

With Docker Compose installed, copy `.env.example` to `.env` and review its settings.
From the repository root:

```sh
docker compose up -d --build
```

Open pgAdmin at [localhost:5050](http://localhost:5050) (default port).
Stop with `docker compose down`; stored data is preserved in the untracked
`uttdb/data/` and `pgadmin/data/` folders.

[example/berlin.sql](example/berlin.sql) shows how to register, store and curate data
from public Berlin sources. It downloads large datasets and can take substantial time. Run
the SQL as a whole or step by step in pgAdmin.

Start with the [documentation overview](docs/welcome.md) for database usage,
temporal curation, pgAdmin and the current architecture.
