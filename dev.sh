#!/bin/bash

WORKING_DIR="$(pwd)"
PLUGIN_DIR="$HOME/.config/nvim/lua/plugins"

usage() {
  echo "Usage: $0 [-c <command>]"
  echo "  -c <command>   Command to run: install (create symlink), uninstall (remove symlink)"
  exit 1
}

while getopts "c:h" opt; do
  case "$opt" in
  c) COMMAND="$OPTARG" ;;
  h) usage ;;
  *) usage ;;
  esac
done

case "$COMMAND" in
install)
  ln -sf "$WORKING_DIR/plugin/dev-pie.lua" "$PLUGIN_DIR/dev-pie.lua"
  echo "Installed pie plugin (symlink) to $PLUGIN_DIR"
  exit 0
  ;;
uninstall)
  rm -f "$PLUGIN_DIR/dev-pie.lua"
  echo "Uninstalled pie plugin from $PLUGIN_DIR"
  exit 0
  ;;
esac
