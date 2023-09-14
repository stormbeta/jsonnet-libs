#!/usr/bin/env jsonnet

local check = function(assertion, message) {
  message: if !assertion then message else null,
  assertion: assertion,
};

local assertAll = function(assertions)
  std.foldl(
    function(result, next) {
      messages: std.prune(result.messages + [next.message]),
      passed: result.passed && next.assertion,
    },
    assertions,
    { messages: ['Assertions failed:'], passed: true }
  );

local assertions = assertAll([
  check(false, 'assertion1 failed'),
  check(true, 'assertion2 failed'),
  check(false, 'assertion3 failed'),
]);

assert assertions.passed : std.join('\n', std.prune(assertions.messages));

{}
