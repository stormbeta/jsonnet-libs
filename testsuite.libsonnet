#!/usr/bin/env jsonnet

// TODO:
//   [ ]: Need easier way to print values for debugging
//   [ ]: Intermediate object for test results for better flexibility
//   [ ]: Make match/equals optional if using assertThat

{
  spec:: (import 'spec/spec.libsonnet') { mode: 'json' },
  filename: std.thisFile,

  // NOTE: You cannot use something like std.all to throw error if tests fail
  //       because jsonnet is lazily evaluated, meaning the very first test to fail
  //       will cause it to abort with an error instead of running all tests
  // TODO: Could I trick it by manifesting the last item in the array and AND'ing it with std.all?
  RunTests(tests)::
    local results = self.test_results(tests);
    std.trace(
      ('\n === %s === \n' % self.filename) +
      std.join('\n', std.map(function(r) r.logLine, results)),
      if std.all(std.map(function(r) r.passed == r.tests, results)) then
        true
      else
        false
    ),

  test_results(tests):: [
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
      else if !('match' in case != 'equals' in case) && !('assertThat' in case) then
        error 'Must have "match" or "equals" fields, or optionally an "assertThat" boolean\nYou can use `match: spec.Any` if you just have an assert'
      else if 'match' in case then
        [$.spec.CheckRaw($.spec.RawValidate(value, case.match) + assertThat(case)) for value in values]
      else if 'equals' in case then
        [$.spec.CheckRaw($.spec.RawValidate(value, $.spec.Equals(case.equals)) + assertThat(case)) for value in values]
      else if 'assertThat' in case then
        // NOTE: This ignores the values field completely
        [assertThat(case)];
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
