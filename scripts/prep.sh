#!/bin/bash

sudo systemctl restart docker
docker compose up -d
uv sync
# uv run poe start
# uv run poe gui
