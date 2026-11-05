#!/usr/bin/env bash
# Stops the workflows, Mailpit and Temporal. Run history stays in runtime/temporal.db.
pkill -f joget_workflows.jar && echo "workflows stopped"
pkill -f "mailpit --smtp 127.0.0.1:1026" && echo "mailpit stopped"
pkill -f "temporal server start-dev" && echo "temporal stopped"
exit 0
