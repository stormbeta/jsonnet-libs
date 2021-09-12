#!/usr/bin/env jsonnet -J ../jsonnetunit

local utils = (import '../utils.libsonnet') {
  log+: {
    level:: self.TRACE,
  },
};
local test = import 'jsonnetunit/test.libsonnet';

test.suite({
  local log = utils.log,

  'test log level set': {
    actual: log.level,
    expect: log.TRACE,
  },

  'test safeGet basic': {
    actual: utils.safeGet({ a: { b: { c: 'yay' } } }, ['a', 'b', 'c'], 'boo'),
    expect: 'yay',
  },

  'test safeGet defaults': {
    actual: [
      utils.safeGet({ a: { b: { c: 'yay' } } }, ['a', 'b', 'nope'], 'default'),
      utils.safeGet({ a: { b: { c: 'yay' } } }, ['never'], 'default'),
    ],
    expect: ['default', 'default'],
  },

  'test safeGet edge cases': {
    actual: [
      utils.safeGet({ a: { b: { c: 'yay' } } }, [], 'default'),
      utils.safeGet({}, ['hello', 'world'], 'default'),
      utils.safeGet({ nothing: null }, ['nothing'], 'default'),
    ],
    expect: ['default', 'default', null],
  },

  'test contains function': {
    actual: [
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
    expect: [
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
    actual: utils.mergeEntriesByKey('name', [{
      name: 'one',
      value: 'no',
    }, {
      name: 'one',
      value: 'yes',
    }, {
      name: 'two',
      value: null,
    }]),

    expect: [{
      name: 'one',
      value: 'yes',
    }, {
      name: 'two',
      value: null,
    }],
  },
})
