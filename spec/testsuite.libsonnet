#!/usr/bin/env jsonnet

// TODO: Extend schema.libsonnet instead of making a separate object?

{
  schema:: (import 'schema.libsonnet') { mode: 'json' },
  TestSuite:: function(tests) std.trace('\n' + std.join('\n', [
    local check = function(case)
      local values = if 'values' in case then case.values else [case.value];
      if !std.isObject(case) then
        error std.toString(case) + ' is not a test case object!'
      else if !('value' in case != 'values' in case) then
        error 'Test case must specify value or values to test against!'
      else if !('match' in case != 'equals' in case) then
        error 'Test case must specify either equals or match patterns'
      else if 'match' in case then
        [$.schema.Validate(value, case.match) for value in values]
      else if 'equals' in case then
        [$.schema.Validate(value, $.schema.Equals(case.equals)) for value in values];
    local result = std.filter(
      function(t) std.isObject(t) && 'errors' in t,
      std.flatMap(
        function(test) check(test),
        if std.type(tests[name]) == 'array' then
          [testCase for testCase in tests[name]]
        else
          [tests[name]]
      )
    );
    if std.length(result) > 0
    then 'FAILED: ' + name + '\n' + $.schema.prettyPrintErrors(std.flatMap(function(x) x.errors, result), '  ')
    else 'PASSED: ' + name
    for name in std.objectFields(tests)
  ]), 'All tests passed!'),
}
