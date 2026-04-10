#!/usr/bin/env bash
WORKING_DIR=$(pwd)

nvim --headless --noplugin -u scripts/minimal_init.vim -c "PlenaryBustedDirectory $WORKING_DIR/lua/tests/ { minimal_init = '$WORKING_DIR/scripts/minimal_init.vim' }"
