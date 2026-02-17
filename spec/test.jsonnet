#!/usr/bin/jsonnet -J jsonnetunit/jsonnetunit

local utils = (import '../utils/utils.libsonnet') {
  log+: {
    level:: self.TRACE,
  },
};
local v = (import 'schema.libsonnet') {
  JsonValidate:: function(data, schema) self.TypeCheck(schema, data, 'json'),
};
//local test = import 'jsonnetunit/test.libsonnet';
local test = import 'test.libsonnet';


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

  'test safe stringification of functions in schema': {
    local data = { hello: 'world' },
    actual: v.JsonValidate(data, v.MapOf(
      v.Either(['number', v.MapOf(v.Either(['number', 'string']))])
    )),
    expectThat: {
      result: self.actual.errors[0].expected == 'number OR map{number OR string}',
    },
  },

  'test optional error output stringification': {
    local data = {
      hello: 'no',
    },
    actual: v.JsonValidate(data, {
      hello: v.Optional(v.Array('string')),
    }),
    expectThat: {
      result: self.actual.errors[0].expected == 'array[string]?',
    },
  },

  'test mismatched array length': {
    local data = [0, 1, 2],
    actual: v.JsonValidate(data, ['number', 'number']),
    expectThat: {
      local err = self.actual.errors[0],
      result: all([err.actual == 3, err.expected == 2]),
    },
  },

  'test StrictMap errors on unknown fields': {
    actual: v.JsonValidate({
      expected: 'field',
      unknown: 'field',
    }, v.StrictMap({ expected: 'string' })),
    expectThat: {
      result: std.length(self.actual.errors) > 0 && self.actual.errors[0].fields[0] == 'unknown',
    },
  },

  'test optional field': {
    local datas = [
      // Value exists
      { option: true, static: 'static' },
      // Value exists but is wrong type
      { option: 'wrong-type', static: 'static' },
      // Value doesn't exist
      { static: 'static' },
    ],
    actual: [
      v.RawValidate(data, { option: v.Optional('boolean') })
      for data in datas
    ],
    expectThat: {
      result: all([
        std.length(self.actual[0].errors) == 0 && std.objectHas(self.actual[0].value, 'option'),
        std.length(self.actual[1].errors) > 0,
        std.length(self.actual[2].errors) == 0 && !std.objectHas(self.actual[2].value, 'option'),
      ]),
    },
  },

  local schema_entriesToObject = function(key) v.ArrayOf({ [key]: 'string' }),
  'test schema_entriesToObject': {
    local data = [
      [{ name: 'hello' }, { key: 'bye' }],
      [{ name: 'hello' }, { name: 'bye' }],
    ],
    actual: [
      v.TypeCheck(schema_entriesToObject('name'), entries, mode='json')
      for entries in data
    ],
    expectThat: {
      result: all([
        self.actual[0].errors[0].path == '[1].name',
        !std.member(self.actual[1], 'errors'),
      ]),
    },
  },

})
