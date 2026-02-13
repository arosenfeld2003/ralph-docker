#!/bin/bash
# Test runner script for Ralph Docker tests

set -e

echo "Running Ralph Docker Tests..."
echo "============================="

# Check if tests directory exists
if [ ! -d "tests" ]; then
    echo "Error: tests directory not found"
    exit 1
fi

# Run output formatter tests
echo "Running output formatter tests..."
node tests/test_output_formatter.js

echo ""
echo "All tests completed successfully!"