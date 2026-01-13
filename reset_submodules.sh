#!/bin/bash
# Reset and reinitialize git submodules
# Usage: ./reset_submodules.sh
#
# Use this when switching branches causes submodule conflicts

set -e

echo "Cleaning up submodules..."

# Remove submodule directories
sudo rm -rf cereal opendbc panda laika_repo rednose_repo msgq_repo body tinygrad_repo

echo "Submodule directories removed."

# Reinitialize submodules
echo "Reinitializing submodules..."
git submodule update --init --recursive

echo "Done! Submodules have been reset."
