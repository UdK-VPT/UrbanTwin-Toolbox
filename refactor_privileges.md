# UTT — Implement Privilege Model v1

## Objective

Refactor the existing UTT database privilege initialization to implement the agreed access model.

**All UTT privilege configuration must be maintained in one initialization file: `902-create-privilege-roles.sql`.**

Do not distribute privilege definitions, sandbox provisioning, default grants or service account configuration across additional initialization files.

The implementation must support an existing development database through migration and also work on a fresh database installation.

## 1. Generic roles

Implement exactly two generic privilege roles:

| Role | Purpose |
|---|---|
| `utt_admin` | Trusted UTT administration |
| `utt_developer` | Researchers and developers |

Both must be `NOLOGIN` roles.

Every human user receives an individual PostgreSQL login and membership in the appropriate role. Shared login accounts are not permitted.

Researchers and developers are identical from a privilege perspective.

The previous generic roles (`uttdb_dba`, `uttdb_developer`, `uttdb_reader`, `uttdb_pipeline`, `uttdb_app_reader`, `uttdb_app_writer`) are superseded. Migrate existing dependencies and grants carefully rather than blindly dropping roles.

## 2. Administrative permissions

Members of `utt_admin` must have full administrative control over UTT.

This includes:

- All UTT-managed schemas and their objects.
- Registration, staging, ingestion, acceptance, rejection and retirement of sources.
- Database migrations and maintenance.
- Provisioning researcher accounts and sandbox schemas.
- Managing privileges and ownership of UTT-managed objects.

Ensure that the role has the ownership capabilities necessary for administration. Ordinary `GRANT ALL` is insufficient for certain DDL operations.

Do not unnecessarily require PostgreSQL `SUPERUSER`.

Existing external components, especially 3DCityDB, may have their own ownership requirements. Preserve their functionality while providing the agreed administrative capabilities.

## 3. Developer permissions

Members of `utt_developer` receive read-only access to all five protected shared schemas:

- `mirror`
- `curation`
- `utt_pkg`
- `citydb`
- `citydb_pkg`

Read-only access includes appropriate `USAGE` and `SELECT` permissions.

Developers must not be able to directly create, modify, delete, truncate, alter or drop shared infrastructure objects.

Do not grant unrestricted `EXECUTE` on administrative or data-mutating functions.

Review function/procedure execution permissions, including PostgreSQL's default `PUBLIC EXECUTE` behavior. Developers should be able to execute explicitly authorized read-only routines without gaining mutation privileges indirectly.

## 4. Personal sandboxes

Every developer receives a personal sandbox schema.

Example:

- Login: `alice`
- Generic role: `utt_developer`
- Schema: `sandbox_alice`

Requirements:

1. A developer owns their sandbox and can freely create, modify and delete objects within it.
2. Every developer can read other developers' sandbox tables and views.
3. Developers cannot modify objects owned by other developers.
4. New sandbox objects automatically receive the appropriate read permissions.
5. Administrators retain full administrative control over all sandboxes.
6. Provisioning must be repeatable without resetting ownership or existing work.
7. Schema naming must avoid collisions, including normalization and PostgreSQL identifier-length truncation.
8. Provisioning must not accidentally grant access to an existing sandbox belonging to somebody else.

Revise the existing sandbox provisioning function rather than introducing unnecessary additional infrastructure.

Use PostgreSQL's native roles, ownership, schema privileges and default privileges.

## 5. Automatic permissions for future objects

**This is a mandatory architectural requirement.**

No manual privilege maintenance should be necessary during normal UTT operation.

The following must work automatically:

- A newly registered mirror dataset becomes readable to all existing developers.
- Newly generated mirror stored tables and views receive the appropriate access rights.
- Newly created shared tables and views in the other protected schemas receive the appropriate permissions.
- New developers receive read access to shared objects that existed before their accounts.
- New developers receive read access to future shared objects.
- New sandbox tables and views are automatically readable by other developers.
- New administrators receive administrative control over existing and future UTT objects.

Account for the fact that PostgreSQL default privileges apply to the **object-creating role**, not automatically to its memberships.

Ensure predictable ownership and default privileges for objects created by UTT routines, migrations and sandbox owners.

Privilege correctness must not depend on remembering to execute manual GRANT statements after ingestion.

## 6. Applications and functional modules

Do not introduce generic application, reader, writer, module or pipeline privilege roles.

Each application or functional module will receive individually defined permissions when needed.

If an application or module becomes an official UTT component, place its privilege configuration in the same `902-create-privilege-roles.sql` initialization file.

Otherwise, leave its permissions to its own deployment configuration.

In particular, an administrative web interface must **not** automatically inherit `utt_admin` privileges simply because it performs administrative workflows.

Do not create speculative service roles for modules that do not yet exist.

## 7. Auditing and resource usage

Individual human logins must remain identifiable through PostgreSQL's session identity and logging.

Do not introduce additional user-tracking columns into mirror history or registry tables merely for administrator auditing.

Do not implement elaborate researcher resource quotas or query restrictions. Resource-intensive research queries are accepted as an operational responsibility.

## 8. Migration requirements

- Preserve existing registrations, imports, mirror history, curation data and sandboxes.
- Avoid unnecessary changes to ingestion and versioning logic.
- Update references to deprecated roles where required.
- Ensure dynamically generated tables and views use the new ownership and privilege model.
- Preserve external 3DCityDB functionality.
- Ensure the initialization is idempotent where practicable.
- Keep all privilege-related initialization in the single designated SQL file.

If another UTT routine must change to respect the new model, update that routine as necessary, but keep the role definitions and privilege configuration centralized.

## 9. Regression tests

Implement or provide repeatable tests covering:

1. Two individual administrator accounts sharing `utt_admin` privileges.
2. Two developer accounts with separate sandboxes.
3. Each developer creating, modifying and dropping objects in their own sandbox.
4. Developers reading one another's sandbox data.
5. Developers being unable to modify another sandbox.
6. Developers reading existing and newly created mirror tables and views.
7. Developers being unable to modify any of the five protected schemas.
8. Newly provisioned developers reading objects created before their accounts.
9. Newly provisioned administrators administering existing objects.
10. Correct default privileges on newly created tables, views and relevant other objects.
11. Restricted execution of administrative and mutating routines.
12. Repeated sandbox provisioning without breaking ownership or existing objects.
13. Safe handling of sandbox-name collisions.
14. Continued operation of mirror registration, ingestion, acceptance, rejection and retirement with the new roles.

## 10. Deliverables

Update `902-create-privilege-roles.sql` and any strictly necessary references in the existing database routines.

Provide a concise summary of:

- Changes made.
- Existing roles migrated or deprecated.
- Ownership and default-privilege strategy.
- Any limitations that PostgreSQL cannot enforce automatically.
- Tests implemented and their results.

## 11. User account and sandbox provisioning

Provide clear, documented administrative entry points for creating and managing human user accounts.

### Developer provisioning

A single administrative function or procedure should:

1. Create an individual PostgreSQL `LOGIN` role.
2. Grant membership in `utt_developer`.
3. Create a dedicated, initially **empty** sandbox schema owned by that login.
4. Configure schema permissions so all developers can read objects subsequently created in the sandbox, but only its owner can modify them.
5. Configure default privileges for future sandbox objects.
6. Return the created login and sandbox schema name.

Example administrative interface:

```sql
CALL utt_pkg.create_developer('alice');
```

The exact function or procedure name can follow existing UTT conventions.

The sandbox must initially contain no tables, views, functions or other user-defined objects. It is simply an empty workspace with its ownership and privileges configured.

### Administrator provisioning

Provide a corresponding entry point for creating an individual administrator account and granting membership in `utt_admin`.

Example:

```sql
CALL utt_pkg.create_admin('bob');
```

Administrators do not automatically receive personal sandboxes. An administrator who also conducts research may be explicitly provisioned with a developer sandbox.

### General requirements

- Only authorized administrators may use these provisioning entry points.
- Prevent duplicate account creation and sandbox-name collisions.
- Do not overwrite or reset existing sandboxes.
- Never store plaintext passwords in UTT tables or SQL initialization files.
- Support secure credential setup through PostgreSQL administration or an appropriate deployment mechanism.
- Clearly distinguish account creation, account deactivation, and sandbox deletion.
- Do not automatically delete a sandbox when an account is deactivated.
- Document how to provision the first administrator during initial deployment, without requiring a pre-existing `utt_admin` member.
- Keep all role definitions, provisioning routines and privilege configuration in `902-create-privilege-roles.sql`.

The intended routine administrative workflow is:

**Create developer → automatically create empty sandbox → immediately ready for use.**

No additional manual `GRANT`, `ALTER DEFAULT PRIVILEGES`, schema creation or ownership adjustments should be necessary.

Keep the solution PostgreSQL-native, minimal, readable and maintainable.

**Do not redesign the UTT metadata model, mirror history or functional-module architecture as part of this task.**