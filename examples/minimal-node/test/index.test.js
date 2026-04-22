const { add, multiply } = require('../src/index');
const assert = require('assert');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  PASS: ${name}`);
    passed++;
  } catch (e) {
    console.error(`  FAIL: ${name} - ${e.message}`);
    failed++;
  }
}

console.log('Running tests...\n');

test('add(1, 2) should return 3', () => {
  assert.strictEqual(add(1, 2), 3);
});

test('add(0, 0) should return 0', () => {
  assert.strictEqual(add(0, 0), 0);
});

test('multiply(2, 3) should return 6', () => {
  assert.strictEqual(multiply(2, 3), 6);
});

console.log(`\nResults: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  process.exit(1);
}
