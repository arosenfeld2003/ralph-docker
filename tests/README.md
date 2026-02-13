# Ralph Docker Test Suite

This directory contains comprehensive tests for the Ralph Docker framework shell scripts.

## Structure

```
tests/
├── README.md                 # This file
├── run_tests.sh             # Main test runner script
└── test_shell_scripts.sh    # Comprehensive shell script tests
```

## Running Tests

### Run All Tests
```bash
cd tests
./run_tests.sh
```

### Run Tests with Verbose Output
```bash
./run_tests.sh -v
```

### Run Tests with Fail-Fast Mode
```bash
./run_tests.sh --fail-fast
```

### List Available Tests
```bash
./run_tests.sh --list
```

## Test Coverage

The test suite covers:

### format-output.sh
- ✅ `truncate_text()` function with various text lengths
- ✅ JSON stream parsing and formatting
- ✅ ANSI color code handling
- ✅ Error message formatting
- ✅ Invalid JSON passthrough

### loop.sh
- ✅ Logging functions (`log_info`, `log_warn`, `log_error`, `log_success`)
- ✅ Git operations and branch detection
- ✅ Environment variable handling (`RALPH_*` variables)
- ✅ Error detection patterns (model not found, connection errors)
- ✅ Iteration control logic

### extract-credentials.sh
- ✅ Operating system detection (macOS vs others)
- ✅ Directory creation with proper permissions
- ✅ File creation and permission setting (600)
- ✅ OAuth credential extraction workflow

### entrypoint.sh
- ✅ Authentication mode detection (OAuth, API key, LiteLLM)
- ✅ LiteLLM health check functionality
- ✅ Workspace verification
- ✅ Command routing and help system
- ✅ Environment configuration display

### Integration Tests
- ✅ Script existence and permissions
- ✅ Bash syntax validation
- ✅ Cross-script compatibility
- ✅ Help command functionality

## Test Framework Features

### Assertions
- `assert_equals(expected, actual, message)` - Test equality
- `assert_contains(haystack, needle, message)` - Test substring inclusion
- `assert_not_contains(haystack, needle, message)` - Test substring exclusion
- `assert_file_exists(file, message)` - Test file existence
- `assert_exit_code(code, command, message)` - Test command exit codes

### Setup/Teardown
- Automatic test environment creation and cleanup
- Temporary directory management
- Mock git repository setup
- Environment variable isolation

### Test Organization
- Grouped tests by script functionality
- Clear test naming and descriptions
- Comprehensive success and failure case coverage
- Integration testing across all components

## Environment Variables

- `RALPH_TEST_VERBOSE=1` - Enable verbose output
- `RALPH_TEST_FAIL_FAST=1` - Stop on first failure

## Test Data

Tests create temporary directories and files under `/tmp/ralph_tests_*` which are automatically cleaned up.

## Dependencies

- bash (4.0+)
- git
- curl (for health checks)
- jq (optional, for format-output.sh testing)

## Contributing

When adding new shell scripts or modifying existing ones:

1. Add corresponding tests to `test_shell_scripts.sh`
2. Test both success and failure scenarios
3. Include integration tests if the script interacts with others
4. Update this README with new test coverage information

## Troubleshooting

### Common Issues

1. **Tests fail with "command not found"**
   - Ensure all dependencies are installed
   - Check PATH includes the scripts directory

2. **Permission denied errors**
   - Run `chmod +x tests/*.sh` to make scripts executable

3. **Git-related test failures**
   - Tests create temporary git repositories automatically
   - Ensure git is properly configured with user.name and user.email

4. **Temporary file cleanup issues**
   - Tests automatically clean up, but manual cleanup: `rm -rf /tmp/ralph_tests_*`
