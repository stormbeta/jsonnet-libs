#!/usr/bin/env jsonnet -J jsonnetunit

local utils = (import '../utils/utils.libsonnet') {
  log+: {
    level:: self.TRACE,
  },
};
local v = import 'schema.libsonnet';
local test = import 'jsonnetunit/test.libsonnet';


test.suite({
  local log = utils.log,
  local all = function(boolArray)
    std.foldl(function(a, b) a && b, boolArray, true),

  'test basic primitives': {
    local data = [
      'a-string',
      0,
      [],
      {},
      true,
      null,
    ],
    local schema = [
      'string',
      'number',
      'array',
      'object',
      'boolean',
      'null',
    ],
    expect: data,
    actual: v.JsonValidate(data, schema),
  },

  'test missing field': {
    local data = {},
    actual: v.JsonValidate(data, { hello: 'string' }),
    expectThat: {
      err:: self.actual.errors[0],
      result: self.err['error'] == 'required field does not exist!'
              && self.err.path == '.hello',
    },
  },

  'test generic array template': {
    local data = {
      myArray: ['hello', 'world'],
    },
    actual: [
      v.JsonValidate(data, { myArray: v.Array('string') }),
      v.JsonValidate(data, { myArray: v.Array('number') }),
    ],
    expectThat: {
      result: all([
        self.actual[0] == data,
        self.actual[1].errors[0].path == '.myArray[0]',
      ]),
    },
  },

  'test generic object template': {
    local data = {
      blue: 'one',
      red: 'two',
    },
    actual: [
      v.JsonValidate(data, v.MapOf('string')),
      v.JsonValidate(data, v.MapOf('array')),
    ],
    expectThat: {
      result: all([
        self.actual[0] == data,
        self.actual[1].errors[0].path == '.blue',
      ]),
    },
  },

  'test correct path string for nested generic object error': {
    local data = {
      hello: [
        { good: 'world' },
        { good: 'world', bad: 5 },
      ],
    },
    actual: v.JsonValidate(data, {
      hello: v.Array(v.MapOf('string')),
    }),
    expectThat: {
      local err = self.actual.errors[0],
      result: all([
        err.path == '.hello[1].bad',
        err.expected == 'string',
        err.actual == 'number',
      ]),
    },
  },
})
