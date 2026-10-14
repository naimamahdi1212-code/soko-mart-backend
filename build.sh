#!/usr/bin/env bash
# Render build step. Run with:  bash build.sh
set -o errexit
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py migrate
