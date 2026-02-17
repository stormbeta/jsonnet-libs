#!/usr/bin/jsonnet -J jsonnetunit/jsonnetunit

local utils = (import '../utils/utils.libsonnet');
local spec = (import 'spec_extended.libsonnet') { mode: 'json' };
local v = spec;

local TestSuite = (import 'testsuite.libsonnet') { filename: std.thisFile };

TestSuite.RunTests({
  local log = utils.log,
  local all = function(boolArray)
    std.foldl(function(a, b) a && b, boolArray, true),

  local types = [
    ['a-string', 'string'],
    [0, 'number'],
    [[], 'array'],
    [{}, 'object'],
    [true, 'boolean'],
    [null, 'null'],
  ],

  // Old behavior was that strings were treated as type names by default
  // Now we want all strings to be literals by default, and types should be explicit
  // At least when placed directly in the spec
  'test primitive type behavior and naming': [
    {
      value: t[0],
      equals: spec.Validate(t[0], spec.Is(t[1])),
    }
    for t in types
  ] + [
    {
      value: t[0],
      match: v.Any,
      assertThat: v.RawValidate(t[0], t[1]).failed,
    }
    for t in types
  ],

  'test type aliases': [
    {
      value: t[0],
      match: v.Any,
      assertThat: !v.RawValidate(t[0], t[1]).failed,
    }
    for t in [
      ['a-string', v.String],
      [0, v.Number],
      [[], v.Array],
      [{}, v.Object],
      [true, v.Boolean],
      [null, v.Null],
    ]
  ],

  'test missing field': {
    value: utils.safeGet(
      spec.Validate({}, { hello: 'string' }),
      ['errors', 0]
    ),
    match: {
      'error': 'Required field does not exist: .hello',
      path: '.hello',
    },
  },

  local data = {
    myArray: ['hello', 'world'],
  },
  'test generic array template': [
    {
      value: spec.Validate(data, { myArray: v.ArrayOf('string') }),
      equals: data,
    },
    {
      value: spec.Validate(data, { myArray: v.ArrayOf('number') }).errors[0],
      match: { path: '.myArray[0]' },
    },
  ],

  'test generic object template': {
    local data = {
      blue: 'one',
      red: 'two',
    },
    value: [
      spec.Validate(data, v.MapOf('string')),
      spec.Validate(data, v.MapOf(v.String)),
      spec.Validate(data, v.MapOf('array')).errors[0],
    ],
    match: [
      data,
      data,
      { path: '.blue' },
    ],
  },

  'test correct path string for nested generic object error': {
    local data = {
      hello: [
        { good: 'world' },
        { good: 'world', bad: 5 },
      ],
    },
    value: spec.Validate(data, {
      hello: v.ArrayOf(v.MapOf('string')),
    }).errors[0],
    match: {
      path: '.hello[1].bad',
      expected: 'string',
      found: 'number',
    },
  },

  'test safe stringification of functions in schema': {
    local data = { hello: 'world' },
    value: spec.Validate(data, v.MapOf(
      v.Either(['number', v.MapOf(v.Either(['number', 'string']))])
    )).errors[0],
    match: {
      expected: 'number | map{number | string}',
    },
  },

  'test optional error output stringification': {
    local data = {
      hello: 'no',
    },
    value: spec.Validate(data, {
      hello: v.Optional(v.ArrayOf('string')),
    }).errors[0],
    match: {
      expected: 'array[string]?',
    },
  },

  'test mismatched array length': {
    local data = [0, 1, 2],
    value: spec.Validate(data, [v.Number, v.Number]).errors[0],
    match: {
      actual_length: 3,
      expect_length: 2,
    },
  },

  'test StrictMap errors on unknown fields': {
    value: spec.Validate({ expected: 'field', unknown: 'field' },
                         v.StrictMap({ expected: v.String })).errors[0],
    match: {
      fields: ['unknown'],
    },
    assertThat: std.startsWith(self.value.err, 'Unknown fields'),
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
    value: [
      v.RawValidate(data, { option: v.Optional('boolean') })
      for data in datas
    ],
    match: v.Any,
    assertThat: all([
      std.length(self.value[0].errors) == 0 && std.objectHas(self.value[0].value, 'option'),
      std.length(self.value[1].errors) > 0,
      std.length(self.value[2].errors) == 0 && !std.objectHas(self.value[2].value, 'option'),
    ]),
  },

  local schema_entriesToObject = function(key) v.ArrayOf({ [key]: v.String }),
  'test schema_entriesToObject': {
    local data = [
      [{ name: 'hello' }, { key: 'bye' }],
      [{ name: 'hello' }, { name: 'bye' }],
    ],
    value: [
      v.TypeCheck(schema_entriesToObject('name'), entries, mode='json')
      for entries in data
    ],
    match: v.Any,
    assertThat: all([
      self.value[0].errors[0].path == '[1].name',
      !std.member(self.value[1], 'errors'),
    ]),
  },


})
