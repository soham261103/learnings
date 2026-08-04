# Liquibase — Beginner's Reference

> **One-line summary:** Liquibase version-controls database changes like Git version-controls code — track what ran, apply only what's pending, roll back when needed.

**Official course:** [Liquibase Training](https://learn.liquibase.com/plus/my/training/152)

---

## Mental Model (remember this)

```
Changelog  →  ordered list of changes (the "script book")
Changeset  →  one atomic change inside it (one "page")
DATABASECHANGELOG → ledger of what already ran
```

**Unique changeset ID** = `author` + `id` + `filename`  
Liquibase never runs the same changeset twice.

---

## Why Use It?

| Benefit | What it means |
|---------|---------------|
| Version control | DB changes live in Git alongside app code |
| Safe deploys | Only pending changesets run; no double-apply |
| Rollback | Undo changes when something breaks |
| CI/CD | Automate DB updates in pipelines |
| Multi-DB | XML/YAML changelogs generate DB-specific SQL |

---

## How It Works

1. You write changes in a **changelog** (SQL, XML, YAML, or JSON).
2. Liquibase connects via **JDBC** and reads changesets in order.
3. It checks `DATABASECHANGELOG` — skips changesets already applied.
4. It runs pending changesets in a **transaction** (rolls back on failure).
5. It records success in `DATABASECHANGELOG`.

### Tracking Tables (auto-created on first run)

| Table | Purpose |
|-------|---------|
| `DATABASECHANGELOG` | History of executed changesets |
| `DATABASECHANGELOGLOCK` | Lock so two processes don't run at once |

---

## Setup

### `liquibase.properties`

Store defaults so you don't repeat flags every time. CLI flags **override** the file.

```properties
changelog-file=dbchangelog.xml
url=jdbc:postgresql://localhost:5432/DEVDB
username=dev
password=secret
classpath=../path/to/project
```

### JDBC Connection

```
jdbc:<database>://<host>:<port>/<database_name>
```

Example: `jdbc:postgresql://192.168.0.50:5432/DEVDB`

Built-in drivers: PostgreSQL, Oracle, MSSQL, MariaDB, SQLite, DB2, H2, Firebird.  
Others: drop the `.jar` into `liquibase/lib`.

---

## Changelogs & Changesets

### Changelog formats

| Format | Best for |
|--------|----------|
| **SQL** | Teams that prefer raw SQL; IDE-friendly |
| **XML / YAML / JSON** | DB-vendor independence; auto-generated SQL |

You can mix formats in one project.

### SQL (formatted)

```sql
--liquibase formatted sql

--changeset yourname:1
--comment: JIRA-1234 — create users table
create table users (
    id int primary key,
    name varchar(255) not null
);
--rollback drop table users;
```

### XML

```xml
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-latest.xsd">

    <changeSet id="1" author="yourname">
        <comment>JIRA-1234 — create users table</comment>
        <createTable tableName="users">
            <column name="id" type="int">
                <constraints primaryKey="true"/>
            </column>
            <column name="name" type="varchar(255)">
                <constraints nullable="false"/>
            </column>
        </createTable>
        <rollback>
            <dropTable tableName="users"/>
        </rollback>
    </changeSet>
</databaseChangeLog>
```

### Common Change Types

`createTable` · `addColumn` · `dropTable` · `createIndex` · `addForeignKeyConstraint`

### Comments by format

| Format | Syntax |
|--------|--------|
| SQL | `--comment: text` |
| XML | `<comment>text</comment>` |
| YAML | `comment: text` |
| JSON | `"comment": "text"` |

View all comments as HTML docs: `liquibase --changelog-file=dbchangelog.xml db-doc ./docs`

---

## Project Structure

```
db/changelog/
  db-changelog-root.xml          ← entry point
  releases/
    db.changelog-01.00.xml
    db.changelog-01.01.xml
    db.changelog-02.00.xml
```

**Root changelog** references child files:

```xml
<!-- Precise order -->
<include file="releases/db.changelog-01.00.xml"/>

<!-- All files in folder, alphabetical order -->
<includeAll path="releases"/>
```

**Naming tip:** Pad versions (`01.00` not `1.0`) so alphabetical order = release order.

---

## Commands Cheat Sheet

### Required flags (most commands)

```text
--changelog-file   --url   --username   --password
```

### Apply changes

| Command | Does |
|---------|------|
| `update-sql` | **Preview** SQL — nothing executes |
| `update` | **Apply** pending changesets |

```bash
liquibase --changelog-file=changelog.xml --url=jdbc:postgresql://localhost:5432/mydb \
          --username=user --password=pass update-sql   # preview first
liquibase ... update                                    # then apply
```

### Check status

| Command | Shows |
|---------|-------|
| `history` | Changesets **already deployed** |
| `status --verbose` | Changesets **not yet applied** |

```bash
liquibase history
liquibase --changelog-file=changelog.xml status --verbose
```

### Rollback

Always run the `*-sql` variant first to preview.

| Command | Rolls back… |
|---------|-------------|
| `rollback-count N` | Last N changesets |
| `rollback TAG` | Everything after tag `TAG` |
| `rollback-to-date YYYY-MM-DD` | Everything after a date |

```bash
liquibase tag version1.0                              # mark a safe point
liquibase --changelog-file=changelog.xml rollback-sql version1.0
liquibase --changelog-file=changelog.xml rollback version1.0
```

**Validate rollbacks in dev:** `update-testing-rollback` — deploys, rolls back, redeploys.

### Compare & capture

| Command | Purpose |
|---------|---------|
| `diff` | Report schema differences (no changes) |
| `diff-changelog` | Generate changelog to sync target → reference |
| `snapshot` | Capture DB state (JSON report) |
| `generate-changelog` | Create changelog to **recreate** current schema |

```bash
# Snapshot for later comparison
liquibase --output-file=snapshot.json snapshot --snapshotFormat=json

# Baseline an existing DB into Liquibase
liquibase --changelog-file=baseline.xml generate-changelog
```

**Diff output categories:** Missing · Unexpected · Changed

**Filter diff scope:** `--diffTypes=tables,views,indexes,foreignkeys`

### Snapshot vs generate-changelog

| | `snapshot` | `generate-changelog` |
|--|:---:|:---:|
| Capture current state | ✓ | ✓ |
| Produces runnable changesets | ✗ | ✓ |
| Recreate schema elsewhere | ✗ | ✓ |
| Use with `diff` | ✓ | indirect |

**Rule of thumb:** `snapshot` = capture & compare · `generate-changelog` = capture & recreate

### Other useful commands

```bash
liquibase --help                  # all commands
liquibase update --help           # help for one command
liquibase --log-level=FINE update # verbose logging (OFF, SEVERE, WARNING, INFO, FINE)
```

> Most commands have a `*-sql` sibling that prints SQL without executing.

---

## Best Practices

### 1. One change per changeset

Each changeset runs in one transaction. Multiple unrelated changes in one changeset make rollbacks messy and can leave partial state on auto-commit databases.

```xml
<!-- Good: atomic -->
<changeSet id="1" author="dev"><createTable .../></changeSet>
<changeSet id="2" author="dev"><addColumn .../></changeSet>

<!-- Avoid: two independent changes bundled -->
<changeSet id="1" author="dev">
    <createTable .../>
    <addColumn .../>
</changeSet>
```

Exception: related changes that must succeed together (e.g., a batch of seed inserts).

### 2. Preview before execute

```
update-sql  →  review  →  update
rollback-*-sql  →  review  →  rollback-*
```

### 3. Rollback strategy

| Approach | When |
|----------|------|
| **Fix forward** (new changeset) | Preferred — safest for production |
| Auto-rollback | Works for `addColumn`, `createIndex`, `createView`, etc. |
| Explicit `<rollback>` / `--rollback` | Required for `dropTable`, raw SQL, etc. |

```sql
--changeset dev:1
create table example (id int primary key);
--rollback drop table example;
```

### 4. Workflow checklist

1. Write changeset in changelog → commit to Git  
2. `status` — confirm pending changesets  
3. `update-sql` — review generated SQL  
4. `update` — apply to dev → test → promote through environments  
5. Tag releases (`liquibase tag v2.0`) for rollback anchors  

---

## Quick Recall Card

```
WHAT   → Version control for databases
WHO    → author + id + filename = unique changeset
WHERE  → DATABASECHANGELOG tracks what's done
HOW    → changelog → changesets → update
WHEN   → update-sql first, update second
WHY    → consistent, repeatable, reversible DB deploys
```
