#!/bin/bash
# Git add workaround for Windows permission issues
GIT_INDEX_FILE=.git/index.tmp git add "$@"
mv .git/index.tmp .git/index 2>/dev/null || true
