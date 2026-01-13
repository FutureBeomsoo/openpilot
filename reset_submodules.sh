#!/bin/bash
# Reset and reinitialize git submodules
# Usage: ./reset_submodules.sh
#
# Use this when switching branches causes submodule conflicts

set -e

echo "Deinitializing submodules..."
sudo git submodule deinit -f --all

echo "Reinitializing submodules..."
git submodule update --init --recursive

echo "Done! Submodules have been reset."
