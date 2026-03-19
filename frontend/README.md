# EurekaClaw Frontend Prototype

This directory contains the EurekaClaw control center frontend. It is now wired to a
lightweight backend server that can read live configuration, inspect capabilities,
and launch real EurekaClaw sessions.

## What it includes

- A research workspace dashboard
- A guided setup / installation wizard
- A system status surface for capabilities and assets
- Live config loading and saving through the backend
- Live session creation and pipeline polling through the backend
- Live LLM authentication testing from the config form

## How to preview

From the repository root, run:

```bash
eurekaclaw ui
```

Then open:

```text
http://127.0.0.1:8080/
```

You can also choose a different bind address:

```bash
eurekaclaw ui --host 127.0.0.1 --port 8080
```

This UI depends on the normal EurekaClaw Python environment. If project
dependencies are not installed yet, the server will not start correctly.
