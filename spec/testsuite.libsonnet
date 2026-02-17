#!/usr/bin/env jsonnet

// TODO:
//   [ ]: Need easier way to print values for debugging
//   [ ]: Intermediate object for test results for better flexibility
//   [ ]: Make match/equals optional if using assertThat

{
  spec:: (import 'spec.libsonnet') { mode: 'json' },
  filename: std.thisFile,

  RunTests(tests)::
    local results = self.TestResults(tests);
    std.trace(
      ('\n === %s === \n' % self.filename) +
      std.join('\n', std.map(function(r) r.logLine, results)),
      if std.all(std.map(function(r) r.passed == r.tests, results)) then
        true
      else
        false
    ),

  TestResults(tests):: [
    local assertThat = function(c)
      if 'assertThat' in c then
        if c.assertThat then {} else {
          errors+: [{ 'error': 'Test case assertion failed!', value: c.value }],
        }
      else {};
    local check = function(case)
      local values = if 'values' in case then case.values else [case.value];
      if !std.isObject(case) then
        error std.toString(case) + ' is not a test case object!'
      else if !('value' in case != 'values' in case) then
        error 'Test case must specify value or values to test against!'
      else if !('match' in case != 'equals' in case) then
        error 'Must have "match" or "equals" fields, and optionally an "assertThat" boolean\nYou can use `match: spec.Any` if you just have an assert'
      else if 'match' in case then
        [$.spec.CheckRaw($.spec.RawValidate(value, case.match) + assertThat(case)) for value in values]
      else if 'equals' in case then
        [$.spec.CheckRaw($.spec.RawValidate(value, $.spec.Equals(case.equals)) + assertThat(case)) for value in values];
    local result =
      std.flatMap(
        function(test) check(test),
        if std.type(tests[name]) == 'array' then
          [testCase for testCase in tests[name]]
        else
          [tests[name]]
      );
    local failed = std.filter(
      function(t) std.isObject(t) && 'errors' in t,
      result
    );
    local numTests = std.length(result);

    {
      passed: numTests - std.length(failed),
      tests: numTests,
      logLine: '[ %s/%s PASSED ]' % std.map(std.toString, [numTests - std.length(failed), std.length(result)]) +
               if std.length(failed) > 0 then
                 ' ' + name + '\n' + $.spec.prettyPrintErrors(std.flatMap(function(x) x.errors, failed), '  ')
               else
                 ' ' + name,
    }
    for name in std.objectFields(tests)
  ],
}
