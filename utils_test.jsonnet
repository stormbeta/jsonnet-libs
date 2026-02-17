#!/usr/bin/env jsonnet

local utils = (import 'utils.libsonnet') {
  log+: { level:: self.TRACE },
};
local test = (import 'testsuite.libsonnet') { filename: std.thisFile };

test.RunTests({
  local log = utils.log,

  'test log level set': {
    value: log.level,
    equals: log.TRACE,
  },

  'test safeGet basic': {
    value: utils.safeGet({ a: { b: { c: 'yay' } } }, ['a', 'b', 'c'], 'boo'),
    equals: 'yay',
  },

  'test safeGet defaults': {
    value: [
      utils.safeGet({ a: { b: { c: 'yay' } } }, ['a', 'b', 'nope'], 'default'),
      utils.safeGet({ a: { b: { c: 'yay' } } }, ['never'], 'default'),
    ],
    equals: ['default', 'default'],
  },

  local arr = ['one', 2, { name: 'three' }, [4, 5], 6, 7],
  'test utils.tail and utils.last': [
    { value: utils.tail(arr)[0], equals: 2 },
    { value: utils.tail(utils.tail(arr)[2]), equals: [5] },
    { value: utils.last(utils.tail(arr)), equals: 7, assertThat: utils.last(arr) == 7 },
    // Ensure base case is no-op
    { value: utils.tail([]), equals: [] },
  ],

  local struct = { arr: ['one', { field: 'obj' }], other: 'field', a: { b: [{ c: 'd' }] } },
  'test advanced safeGet behavior': [
    { value: utils.safeGet(struct, ['arr', 0]), equals: 'one' },
    { value: utils.safeGet(struct, ['arr', 1, 0], null), equals: null },
    { value: utils.safeGet(struct, ['arr', 1, 'field']), equals: 'obj' },
    { value: utils.safeGet(struct, ['a', 'b', 0]), equals: { c: 'd' } },
  ],

  local entries = [
    { key: 'one', value: 1 },
    { key: 'oops', alt: 'zero' },
    { key: 'one', value: null, Null: true },
  ],
  'test findBy': [
    { value: utils.findBy(entries, 'key', 'one')[0].value, equals: 1 },
    { value: utils.findBy(entries, 'alt', 'zero')[0], match: { key: 'oops' } },
    { value: utils.findBy(entries, 'value', null)[0], match: { Null: true } },
    { value: utils.findBy(entries, 'key', 'one'), assertThat: std.length(self.value) == 2 },
  ],
  'test safeGet entry mapping': [
    { value: utils.safeGet(entries, { key: 'oops' }, null), match: { key: 'oops' } },
  ],

  'test safeGet edge cases': {
    value: [
      utils.safeGet({ a: { b: { c: 'yay' } } }, [], 'default'),
      utils.safeGet({}, ['hello', 'world'], 'default'),
      utils.safeGet({ nothing: null }, ['nothing'], 'default'),
    ],
    equals: ['default', 'default', null],
  },

  'test safeGet/optional custom handler': {
    local upcase = function(_) std.asciiUpper(_),
    value: [
      utils.optional({ a: 'optional' }, 'a', 'bad', upcase),
      utils.safeGet({ a: { b: 'safeGet' } }, ['a', 'b'], 'bar', upcase),
    ],
    equals: [
      'OPTIONAL',
      'SAFEGET',
    ],
  },

  'test contains function': {
    value: [
      // true
      utils.contains(['alpha', 'beta', 'delta'], 'delta'),
      utils.contains({ hello: 'world', goodbye: 'world' }, 'hello'),
      utils.contains('hello world', 'world'),
      // false
      utils.contains(['alpha', 'beta', 'delta'], 'gamma'),
      utils.contains({ hello: 'world', goodbye: 'world' }, 'nothing'),
      utils.contains({ hello: 'world', goodbye: 'world' }, null),
      utils.contains('hello world', 'never'),
    ],
    equals: [
      true,
      true,
      true,
      false,
      false,
      false,
      false,
    ],
  },

  'test entries merge': {
    value: utils.combineEntriesByKey('name', [{
      name: 'one',
      value: 'no',
    }, {
      name: 'one',
      value: 'yes',
    }, {
      name: 'two',
      value: null,
    }]),

    equals: [{
      name: 'one',
      value: 'yes',
    }, {
      name: 'two',
      value: null,
    }],
  },

  local iMap = [1, -5, 5, 2, -3, 0],
  'test indexedFilterMap behavior': [
    {
      value: utils.indexedFilterMap(function(x) x >= 0, function(i, x) x * i, iMap),
      equals: [0, 10, 6, 0],
    },
    {
      value: utils.indexedFilterMap(
        function(x) x >= 0,
        function(i, x) { index: i + 1, value: x },
        iMap
      )[1],
      equals: { index: 3, value: 5 },
    },
  ],

  'test string case conversion': [
    {
      values: [
        utils.capitalize(s)
        for s in ['foobar', 'FOOBAR', 'Foobar', 'FoOBar']
      ],
      equals: 'Foobar',
    },
    {
      values: [
        utils.snakeToTitle(s)
        for s in ['foo_bar', 'FOO_BAR', 'foo_BAR', 'Foo_Bar', 'Foo_bar']
      ],
      equals: 'Foo Bar',
    },
  ],
})
