# Architecture

The current stack runs in one Docker Compose project. Arrows show existing access
and data flow.

```mermaid
flowchart LR
  wfs[WFS sources] --> pkg
  files["uttdb/source-files"] --> pkg

  subgraph stack[Docker Compose]
    pgadmin[pgAdmin]
    subgraph db[UTTDB — PostgreSQL / PostGIS]
      pkg["utt_pkg — SQL workflows"]
      mirror[(mirror)]
      utt[(utt)]
      citydb[(citydb — 3DCityDB v5)]
      pkg --> mirror
      mirror --> pkg
      pkg --> utt
    end
    pgadmin --> db
  end
```

UTTDB persists in `uttdb/data/`; pgAdmin persists in `pgadmin/data/`.
Original source files remain separate from database storage. See
[UTTDB](uttdb.md) and [pgAdmin](pgadmin.md) for operational details.
