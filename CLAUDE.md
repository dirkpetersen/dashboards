# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Monorepo for AWS dashboard web apps. Each dashboard is a standalone Flask app in its own directory that monitors specific AWS services. Currently contains:
- **bedrock-usage**: Bedrock invocation tracking, token usage, and cost analysis (see `bedrock-usage/CLAUDE.md`)

## Common Commands

```bash
# Setup
python3 -m venv .venv
pip install -r requirements.txt

# Run a dashboard (default port 5000)
.venv/bin/python bedrock-usage/app.py
.venv/bin/python bedrock-usage/app.py --port 8080

# Syntax check
python3 -m py_compile bedrock-usage/app.py

# Test API
curl -s http://localhost:5000/api/usage | python3 -m json.tool | head -20
curl -s "http://localhost:5000/api/usage?days=7" | python3 -m json.tool
time curl -s http://localhost:5000/api/usage > /dev/null

# Deploy as systemd service
./install-systemd.sh bedrock-usage 5000
./uninstall-systemd.sh bedrock-usage

# Deploy to Lambda
AWS_PROFILE=deploy-admin ./setup-lambda.sh bedrock-usage
AWS_PROFILE=deploy-admin ./remove-lambda.sh bedrock-usage app.example.com
```

## Configuration

Environment variables with a hierarchy (checked in order):
1. `{VAR}_{DASHBOARD_NAME}` — e.g., `AWS_PROFILE_BEDROCK_USAGE`
2. `{VAR}` — e.g., `AWS_PROFILE`
3. Hardcoded default

`DASHBOARD_NAME` is derived from the script filename: `bedrock-usage.py` → `BEDROCK_USAGE`.

Variables: `AWS_PROFILE`, `SUBNETS_ONLY` (comma-separated CIDRs; localhost always allowed), `FQDN` (Lambda deployments).

Copy `.env.default` to `.env` to configure.

## Architecture

Each dashboard is a Flask app (`{name}/app.py`) with these standard components:

- **`get_config(var, default=None)`** — config lookup with the hierarchy above
- **`check_subnet_access()`** — `@app.before_request` middleware enforcing `SUBNETS_ONLY`; returns 403 JSON if denied
- **`_query_cache` / `_cache_ttl`** — in-memory dict caching CloudWatch query IDs for 10 min to avoid redundant API calls
- **Routes**: `/` renders the HTML template; `/api/usage` returns JSON; additional routes for features (pricing, matrix, etc.)
- **Templates**: `{name}-template.html` (main), `{name}-template-*.html` (additional views) using Chart.js + moment.js

App entry point: `app.run(debug=True, host='0.0.0.0', port=args.port)` with `--port` arg and `PORT` env var.

## Lambda Deployment: Settings Persistence

`setup-lambda.sh` saves `SUBNETS_ONLY` and `FQDN` to `~/.lambda-deployments/{function-name}.metadata` after each deploy. On the next deploy, omitted flags are restored from this file. Explicit args always override. This avoids repeating access control settings on code-only updates.

## Adding a New Dashboard

1. `mkdir {name} && cp bedrock-usage/app.py {name}/app.py`
2. Copy and rename the HTML template(s)
3. Implement dashboard-specific data fetching in `app.py`
4. Test: `.venv/bin/python {name}/app.py --port 5001`
5. Deploy: `./install-systemd.sh {name} 5001`

Config variables automatically use `_{NAME}` suffix based on the filename.
