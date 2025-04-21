#!/usr/bin/env bash

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    export $(cat .env | xargs)
fi 