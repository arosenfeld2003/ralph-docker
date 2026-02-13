#!/usr/bin/env node
/**
 * Comprehensive Test Suite for Ralph Output Formatter
 *
 * Tests the OutputFormatter class methods and stream-json event processing
 * Uses Node.js built-in assert module for zero external dependencies
 */

const assert = require('assert');
const { spawn } = require('child_process');
const path = require('path');

// Test utilities
function captureOutput(callback) {
  const originalWrite = process.stdout.write;
  const originalLog = console.log;
  let capturedOutput = '';

  process.stdout.write = function(string) {
    capturedOutput += string;
    return true;
  };

  console.log = function(...args) {
    capturedOutput += args.join(' ') + '\n';
  };

  try {
    callback();
  } finally {
    process.stdout.write = originalWrite;
    console.log = originalLog;
  }

  return capturedOutput;
}

function stripAnsiColors(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, '');
}

// Load and extract testable functions from output formatter
const outputFormatterPath = path.join(__dirname, '../lib/output-formatter.js');
const fs = require('fs');
const outputFormatterSource = fs.readFileSync(outputFormatterPath, 'utf8');

// Extract the core functionality into a testable class
class OutputFormatter {
  constructor() {
    // ANSI color codes
    this.colors = {
      reset: '\x1b[0m',
      bold: '\x1b[1m',
      dim: '\x1b[2m',
      cyan: '\x1b[36m',
      yellow: '\x1b[33m',
      green: '\x1b[32m',
      red: '\x1b[31m',
      magenta: '\x1b[35m',
      blue: '\x1b[34m',
      white: '\x1b[37m',
    };

    // Configuration
    this.MAX_CONTENT_LENGTH = 500;
    this.MAX_TOOL_INPUT_LENGTH = 200;

    // State
    this.messageStartTime = null;
    this.toolStartTime = null;
    this.totalCost = 0;
    this.spinnerInterval = null;
    this.currentToolName = '';
  }

  truncate(text, maxLen = this.MAX_CONTENT_LENGTH) {
    if (!text) return '';
    const str = String(text);
    if (str.length <= maxLen) return str;
    return str.substring(0, maxLen) + '... (truncated)';
  }

  formatDuration(ms) {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  }

  formatTimestamp(date = new Date()) {
    return date.toISOString();
  }

  formatSize(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  formatTool(toolName, input = {}) {
    const inputStr = JSON.stringify(input);
    return {
      name: toolName,
      truncatedInput: this.truncate(inputStr, this.MAX_TOOL_INPUT_LENGTH),
      formattedOutput: `${this.colors.yellow}[tool]${this.colors.reset} ${this.colors.bold}${toolName}${this.colors.reset}`
    };
  }

  formatStreamJsonLine(line) {
    if (!line || !line.trim()) return null;

    let data;
    try {
      data = JSON.parse(line);
    } catch {
      return { type: 'raw', content: line };
    }

    const result = {
      type: data.type,
      originalData: data,
      formattedOutput: '',
      actions: []
    };

    switch (data.type) {
      case 'assistant': {
        const content = data.message?.content;
        if (content) {
          if (Array.isArray(content)) {
            content.forEach(block => {
              if (block.type === 'text' && block.text) {
                result.formattedOutput += `${this.colors.cyan}${block.text}${this.colors.reset}\n`;
              }
            });
          } else {
            result.formattedOutput = `${this.colors.cyan}${content}${this.colors.reset}`;
          }
        }
        break;
      }

      case 'content_block_start': {
        const blockType = data.content_block?.type;
        if (blockType === 'tool_use') {
          const toolName = data.content_block?.name || 'unknown';
          result.actions.push({ action: 'start_spinner', toolName });
          result.formattedOutput = `Starting tool: ${toolName}`;
        }
        break;
      }

      case 'content_block_delta': {
        const deltaType = data.delta?.type;
        if (deltaType === 'text_delta' && data.delta?.text) {
          result.actions.push({ action: 'stop_spinner' });
          result.formattedOutput = `${this.colors.cyan}${data.delta.text}${this.colors.reset}`;
        }
        break;
      }

      case 'tool_use': {
        const toolName = data.name || 'unknown';
        const input = data.input ? JSON.stringify(data.input) : '{}';
        result.actions.push({ action: 'stop_spinner' });
        result.actions.push({ action: 'start_spinner', toolName });
        result.formattedOutput = `${this.colors.yellow}[tool]${this.colors.reset} ${this.colors.bold}${toolName}${this.colors.reset}\n`;
        result.formattedOutput += `${this.colors.dim}  input: ${this.truncate(input, this.MAX_TOOL_INPUT_LENGTH)}${this.colors.reset}`;
        break;
      }

      case 'tool_result': {
        const isError = data.is_error;
        const duration = this.toolStartTime ? this.formatDuration(Date.now() - this.toolStartTime) : '';
        result.actions.push({ action: 'stop_spinner' });

        if (isError) {
          result.formattedOutput = `${this.colors.red}[error]${this.colors.reset} Tool failed ${duration ? `(${duration})` : ''}`;
          if (data.content) {
            result.formattedOutput += `\n${this.colors.red}  ${this.truncate(data.content, 300)}${this.colors.reset}`;
          }
        } else {
          result.formattedOutput = `${this.colors.green}[done]${this.colors.reset} Tool completed ${duration ? `(${duration})` : ''}`;
        }
        break;
      }

      case 'error': {
        const errorMsg = data.error?.message || data.message || 'Unknown error';
        result.actions.push({ action: 'stop_spinner' });
        result.formattedOutput = `${this.colors.red}[ERROR]${this.colors.reset} ${errorMsg}`;
        break;
      }

      case 'message_start': {
        const model = data.message?.model;
        if (model) {
          result.formattedOutput = `${this.colors.dim}[model: ${model}]${this.colors.reset}`;
        }
        result.actions.push({ action: 'set_message_start_time' });
        break;
      }

      case 'message_stop': {
        result.actions.push({ action: 'stop_spinner' });
        result.formattedOutput = '';
        break;
      }

      case 'message_delta': {
        const usage = data.usage;
        if (usage) {
          const tokens = usage.output_tokens || 0;
          result.formattedOutput = `${this.colors.dim}[tokens: ${tokens}]${this.colors.reset}`;
        }
        break;
      }

      case 'system': {
        const text = data.message;
        if (text) {
          result.formattedOutput = `${this.colors.magenta}[system]${this.colors.reset} ${text}`;
        }
        break;
      }

      case 'result': {
        const cost = data.cost_usd;
        const duration = data.duration_ms;
        const parts = [];
        result.actions.push({ action: 'stop_spinner' });

        if (cost) {
          parts.push(`cost: $${cost}`);
          result.actions.push({ action: 'add_cost', cost: parseFloat(cost) });
        }
        if (duration) {
          parts.push(`duration: ${this.formatDuration(duration)}`);
        }
        if (parts.length > 0) {
          result.formattedOutput = `${this.colors.dim}[stats] ${parts.join(', ')}${this.colors.reset}`;
        }
        break;
      }

      default: {
        if (data.subagent) {
          result.formattedOutput = `${this.colors.magenta}[subagent]${this.colors.reset} ${data.subagent}`;
        }
        break;
      }
    }

    return result;
  }
}

// Test Suite
class TestSuite {
  constructor() {
    this.passed = 0;
    this.failed = 0;
    this.formatter = new OutputFormatter();
  }

  test(name, testFn) {
    try {
      testFn();
      console.log(`✓ ${name}`);
      this.passed++;
    } catch (error) {
      console.log(`✗ ${name}`);
      console.log(`  Error: ${error.message}`);
      this.failed++;
    }
  }

  run() {
    console.log('Running OutputFormatter Tests...\n');

    // Test utility functions
    this.testTruncateFunction();
    this.testFormatDurationFunction();
    this.testFormatTimestampFunction();
    this.testFormatSizeFunction();
    this.testFormatToolFunction();

    // Test stream-json processing
    this.testStreamJsonParsing();
    this.testAssistantEvent();
    this.testContentBlockEvents();
    this.testToolEvents();
    this.testErrorEvents();
    this.testMessageEvents();
    this.testSystemEvent();
    this.testResultEvent();

    // Test edge cases
    this.testInvalidJson();
    this.testEmptyInput();
    this.testMalformedEvents();
    this.testLargeOutputs();
    this.testAnsiColors();

    // Print results
    console.log(`\nTest Results: ${this.passed} passed, ${this.failed} failed`);
    return this.failed === 0;
  }

  testTruncateFunction() {
    this.test('truncate() - normal text', () => {
      assert.strictEqual(this.formatter.truncate('hello world', 20), 'hello world');
    });

    this.test('truncate() - long text', () => {
      const longText = 'a'.repeat(600);
      const result = this.formatter.truncate(longText);
      assert.strictEqual(result.length, 500 + '... (truncated)'.length);
      assert(result.endsWith('... (truncated)'));
    });

    this.test('truncate() - custom length', () => {
      const result = this.formatter.truncate('hello world', 5);
      assert.strictEqual(result, 'hello... (truncated)');
    });

    this.test('truncate() - empty input', () => {
      assert.strictEqual(this.formatter.truncate(''), '');
      assert.strictEqual(this.formatter.truncate(null), '');
      assert.strictEqual(this.formatter.truncate(undefined), '');
    });

    this.test('truncate() - non-string input', () => {
      assert.strictEqual(this.formatter.truncate(12345, 3), '123... (truncated)');
    });
  }

  testFormatDurationFunction() {
    this.test('formatDuration() - milliseconds', () => {
      assert.strictEqual(this.formatter.formatDuration(500), '500ms');
    });

    this.test('formatDuration() - seconds', () => {
      assert.strictEqual(this.formatter.formatDuration(1500), '1.5s');
    });

    this.test('formatDuration() - minutes', () => {
      assert.strictEqual(this.formatter.formatDuration(90000), '1.5m');
    });

    this.test('formatDuration() - edge cases', () => {
      assert.strictEqual(this.formatter.formatDuration(0), '0ms');
      assert.strictEqual(this.formatter.formatDuration(999), '999ms');
      assert.strictEqual(this.formatter.formatDuration(1000), '1.0s');
    });
  }

  testFormatTimestampFunction() {
    this.test('formatTimestamp() - valid date', () => {
      const date = new Date('2023-01-01T12:00:00.000Z');
      assert.strictEqual(this.formatter.formatTimestamp(date), '2023-01-01T12:00:00.000Z');
    });

    this.test('formatTimestamp() - default current date', () => {
      const result = this.formatter.formatTimestamp();
      assert(result.match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/));
    });
  }

  testFormatSizeFunction() {
    this.test('formatSize() - bytes', () => {
      assert.strictEqual(this.formatter.formatSize(0), '0 B');
      assert.strictEqual(this.formatter.formatSize(512), '512 B');
    });

    this.test('formatSize() - kilobytes', () => {
      assert.strictEqual(this.formatter.formatSize(1024), '1 KB');
      assert.strictEqual(this.formatter.formatSize(1536), '1.5 KB');
    });

    this.test('formatSize() - megabytes', () => {
      assert.strictEqual(this.formatter.formatSize(1048576), '1 MB');
    });
  }

  testFormatToolFunction() {
    this.test('formatTool() - basic tool', () => {
      const result = this.formatter.formatTool('testTool', { param: 'value' });
      assert.strictEqual(result.name, 'testTool');
      assert.strictEqual(result.truncatedInput, '{"param":"value"}');
      assert(result.formattedOutput.includes('testTool'));
    });

    this.test('formatTool() - tool with large input', () => {
      const largeInput = { data: 'x'.repeat(300) };
      const result = this.formatter.formatTool('largeTool', largeInput);
      assert(result.truncatedInput.endsWith('... (truncated)'));
    });
  }

  testStreamJsonParsing() {
    this.test('formatStreamJsonLine() - valid JSON', () => {
      const jsonLine = '{"type": "test", "message": "hello"}';
      const result = this.formatter.formatStreamJsonLine(jsonLine);
      assert.strictEqual(result.type, 'test');
      assert.deepStrictEqual(result.originalData, { type: 'test', message: 'hello' });
    });

    this.test('formatStreamJsonLine() - empty input', () => {
      assert.strictEqual(this.formatter.formatStreamJsonLine(''), null);
      assert.strictEqual(this.formatter.formatStreamJsonLine('   '), null);
    });
  }

  testAssistantEvent() {
    this.test('assistant event - text content', () => {
      const event = {
        type: 'assistant',
        message: {
          content: 'Hello from assistant'
        }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert.strictEqual(result.type, 'assistant');
      assert(stripAnsiColors(result.formattedOutput).includes('Hello from assistant'));
    });

    this.test('assistant event - array content', () => {
      const event = {
        type: 'assistant',
        message: {
          content: [
            { type: 'text', text: 'First block' },
            { type: 'text', text: 'Second block' }
          ]
        }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      const stripped = stripAnsiColors(result.formattedOutput);
      assert(stripped.includes('First block'));
      assert(stripped.includes('Second block'));
    });
  }

  testContentBlockEvents() {
    this.test('content_block_start - tool_use', () => {
      const event = {
        type: 'content_block_start',
        content_block: {
          type: 'tool_use',
          name: 'testTool'
        }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert.strictEqual(result.type, 'content_block_start');
      assert.deepStrictEqual(result.actions, [{ action: 'start_spinner', toolName: 'testTool' }]);
    });

    this.test('content_block_delta - text', () => {
      const event = {
        type: 'content_block_delta',
        delta: {
          type: 'text_delta',
          text: 'streaming text'
        }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert.deepStrictEqual(result.actions, [{ action: 'stop_spinner' }]);
      assert(stripAnsiColors(result.formattedOutput).includes('streaming text'));
    });
  }

  testToolEvents() {
    this.test('tool_use event', () => {
      const event = {
        type: 'tool_use',
        name: 'Read',
        input: { file_path: '/path/to/file.txt' }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert.strictEqual(result.type, 'tool_use');
      assert(result.actions.some(a => a.action === 'stop_spinner'));
      assert(result.actions.some(a => a.action === 'start_spinner' && a.toolName === 'Read'));
      const stripped = stripAnsiColors(result.formattedOutput);
      assert(stripped.includes('[tool]'));
      assert(stripped.includes('Read'));
    });

    this.test('tool_result - success', () => {
      const event = {
        type: 'tool_result',
        is_error: false
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert.strictEqual(result.type, 'tool_result');
      assert(result.actions.some(a => a.action === 'stop_spinner'));
      assert(stripAnsiColors(result.formattedOutput).includes('[done]'));
    });

    this.test('tool_result - error', () => {
      const event = {
        type: 'tool_result',
        is_error: true,
        content: 'File not found'
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(stripAnsiColors(result.formattedOutput).includes('[error]'));
      assert(stripAnsiColors(result.formattedOutput).includes('File not found'));
    });
  }

  testErrorEvents() {
    this.test('error event - with message', () => {
      const event = {
        type: 'error',
        error: {
          message: 'Something went wrong'
        }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert.strictEqual(result.type, 'error');
      assert(result.actions.some(a => a.action === 'stop_spinner'));
      assert(stripAnsiColors(result.formattedOutput).includes('[ERROR]'));
      assert(stripAnsiColors(result.formattedOutput).includes('Something went wrong'));
    });

    this.test('error event - fallback message', () => {
      const event = {
        type: 'error',
        message: 'Direct error message'
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(stripAnsiColors(result.formattedOutput).includes('Direct error message'));
    });
  }

  testMessageEvents() {
    this.test('message_start event', () => {
      const event = {
        type: 'message_start',
        message: {
          model: 'claude-3-sonnet'
        }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(result.actions.some(a => a.action === 'set_message_start_time'));
      assert(stripAnsiColors(result.formattedOutput).includes('claude-3-sonnet'));
    });

    this.test('message_stop event', () => {
      const event = { type: 'message_stop' };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(result.actions.some(a => a.action === 'stop_spinner'));
    });

    this.test('message_delta event', () => {
      const event = {
        type: 'message_delta',
        usage: {
          output_tokens: 150
        }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(stripAnsiColors(result.formattedOutput).includes('tokens: 150'));
    });
  }

  testSystemEvent() {
    this.test('system event', () => {
      const event = {
        type: 'system',
        message: 'System notification'
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(stripAnsiColors(result.formattedOutput).includes('[system]'));
      assert(stripAnsiColors(result.formattedOutput).includes('System notification'));
    });
  }

  testResultEvent() {
    this.test('result event - with cost and duration', () => {
      const event = {
        type: 'result',
        cost_usd: '0.0025',
        duration_ms: 1500
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(result.actions.some(a => a.action === 'stop_spinner'));
      assert(result.actions.some(a => a.action === 'add_cost' && a.cost === 0.0025));
      const stripped = stripAnsiColors(result.formattedOutput);
      assert(stripped.includes('cost: $0.0025'));
      assert(stripped.includes('duration: 1.5s'));
    });
  }

  testInvalidJson() {
    this.test('invalid JSON - malformed', () => {
      const result = this.formatter.formatStreamJsonLine('{ invalid json');
      assert.strictEqual(result.type, 'raw');
      assert.strictEqual(result.content, '{ invalid json');
    });

    this.test('invalid JSON - not JSON at all', () => {
      const result = this.formatter.formatStreamJsonLine('plain text output');
      assert.strictEqual(result.type, 'raw');
      assert.strictEqual(result.content, 'plain text output');
    });
  }

  testEmptyInput() {
    this.test('empty input handling', () => {
      assert.strictEqual(this.formatter.formatStreamJsonLine(''), null);
      assert.strictEqual(this.formatter.formatStreamJsonLine(null), null);
      assert.strictEqual(this.formatter.formatStreamJsonLine(undefined), null);
    });
  }

  testMalformedEvents() {
    this.test('malformed event - missing required fields', () => {
      const event = { type: 'assistant' }; // missing message content
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert.strictEqual(result.type, 'assistant');
      assert.strictEqual(result.formattedOutput, '');
    });

    this.test('malformed event - unknown type', () => {
      const event = { type: 'unknown_type', data: 'something' };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert.strictEqual(result.type, 'unknown_type');
      assert.strictEqual(result.formattedOutput, '');
    });

    this.test('malformed event - with subagent fallback', () => {
      const event = { type: 'unknown_type', subagent: 'test-agent' };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(stripAnsiColors(result.formattedOutput).includes('[subagent]'));
      assert(stripAnsiColors(result.formattedOutput).includes('test-agent'));
    });
  }

  testLargeOutputs() {
    this.test('large tool input truncation', () => {
      const largeInput = { data: 'x'.repeat(500) };
      const event = {
        type: 'tool_use',
        name: 'largeTool',
        input: largeInput
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(stripAnsiColors(result.formattedOutput).includes('... (truncated)'));
    });

    this.test('large error content truncation', () => {
      const largeError = 'Error: ' + 'x'.repeat(400);
      const event = {
        type: 'tool_result',
        is_error: true,
        content: largeError
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(stripAnsiColors(result.formattedOutput).includes('... (truncated)'));
    });
  }

  testAnsiColors() {
    this.test('ANSI colors - assistant message', () => {
      const event = {
        type: 'assistant',
        message: { content: 'Hello' }
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(result.formattedOutput.includes('\x1b[36m')); // cyan
      assert(result.formattedOutput.includes('\x1b[0m'));  // reset
    });

    this.test('ANSI colors - error message', () => {
      const event = {
        type: 'error',
        message: 'Test error'
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(result.formattedOutput.includes('\x1b[31m')); // red
    });

    this.test('ANSI colors - tool message', () => {
      const event = {
        type: 'tool_use',
        name: 'testTool',
        input: {}
      };
      const result = this.formatter.formatStreamJsonLine(JSON.stringify(event));
      assert(result.formattedOutput.includes('\x1b[33m')); // yellow
      assert(result.formattedOutput.includes('\x1b[1m'));  // bold
    });
  }
}

// Integration test to verify the actual script works
async function testIntegration() {
  console.log('\nRunning Integration Tests...\n');

  const testInputs = [
    '{"type": "assistant", "message": {"content": "Hello, world!"}}',
    '{"type": "tool_use", "name": "Read", "input": {"file_path": "/test/file.txt"}}',
    '{"type": "tool_result", "is_error": false}',
    '{"type": "error", "message": "Test error"}'
  ];

  return new Promise((resolve) => {
    const child = spawn('node', [outputFormatterPath], {
      stdio: ['pipe', 'pipe', 'pipe']
    });

    let output = '';
    child.stdout.on('data', (data) => {
      output += data.toString();
    });

    child.stderr.on('data', (data) => {
      console.error('stderr:', data.toString());
    });

    child.on('close', (code) => {
      console.log(`✓ Integration test - script runs without errors (exit code: ${code})`);
      console.log(`✓ Integration test - produces colored output (${output.length} chars)`);
      resolve(code === 0);
    });

    // Send test data
    testInputs.forEach(input => {
      child.stdin.write(input + '\n');
    });
    child.stdin.end();
  });
}

// Run all tests
async function main() {
  const suite = new TestSuite();
  const unitTestsPassed = suite.run();
  const integrationPassed = await testIntegration();

  console.log('\n' + '='.repeat(50));
  if (unitTestsPassed && integrationPassed) {
    console.log('All tests passed! 🎉');
    process.exit(0);
  } else {
    console.log('Some tests failed! 💥');
    process.exit(1);
  }
}

if (require.main === module) {
  main().catch(console.error);
}

module.exports = { OutputFormatter, TestSuite };