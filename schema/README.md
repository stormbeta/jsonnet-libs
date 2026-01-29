# schema.libsonnet

Pure jsonnet library for adding type checking to calls

**Motivation**

Because jsonnet is purely functional, it can be tricky to debug issues that happen in more complex
scripts with intermediate data structures and layered functions, especially keeping track of the
structure between different contexts.

This library aims to add inline type and constraint checks that can produce human-readable errors
instead of a cryptic stack trace.

NOTE: This is not intended as a JSON schema validator - you could use it that way, but there are many
better tools and libraries for that.

**Example**

```jsonnet
local t = (import 'schema.libsonnet') { file: std.thisFile };

local schema = {
  hello: 'string',
  entries: t.ArrayOf({
    name: 'string',
    value: t.Optional('number'),
  }),
  strList: t.ArrayOf('string'),
  maybe: t.Optional('boolean'),
};

local data = {
  hello: 'world',
  entries: [{
    name: 'one',
    value: 1,
  }, {
    name: 'missing',
  }],
  strList: ['one', 'two', 'three'],
};

t.TypeCheck(schema, data),
```

This will pass, returning data in-place. But if we accidentally made the first value in
entries a string instead of a number, e.g. `value: "1"`:

```
RUNTIME ERROR:
ACTUAL:   string
EXPECTED: number?
FILE:     example.jsonnet
PATH:     .entries[0].value
VALUE:    "1"

        schema.libsonnet:433:9-18       function <anonymous>
        example.jsonnet:24:1-26
```

- This works for arbitrarily nested structures and types

- Path is a `jq`-style reference.

- The `?` in the "expected" field signifies that this field or item was optional


**Custom Validator Example**

```jsonnet
local t = (import 'schema.libsonnet') { file: std.thisFile };

local IntRange = function(min, max)
  t.CustomValidator(
    'IntRange', function(data)
      {
        result: data >= min && data <= max,
        expected: '%s <= N <= %s' % [min, max],
        actual: data,
        message: 'Out of range',
      }
  );

local data = {
  number_names: [
    { name: 'one', value: 1 },
    { name: 'two', value: 2 },
    { name: 'four', value: 4 },
  ],
};

t.TypeCheck(
  {
    number_names: t.ArrayOf({
      name: 'string',
      value: IntRange(3, 9),
    }),
  },
  data
)
```

Result:

```
ACTUAL:   1
EXPECTED: 3 <= N <= 9
FILE:     example.jsonnet
MESSAGE:  Out of range
PATH:     .number_names[0].value

ACTUAL:   2
EXPECTED: 3 <= N <= 9
FILE:     example.jsonnet
MESSAGE:  Out of range
PATH:     .number_names[1].value
```


### Schema Reference

Primitive names are matched using jsonnet's std.type

E.g. 'string', 'object', 'number', 'array', 'boolean', etc.

Objects or arrays in the schema are used to recurse down and validate nested values

For everything else, see type functions below:

Type Functions
-------------------

Helpers to specify other kinds of constraints

Enum([VALUES...])

  Data must equal one of the provided literals

Optional(SCHEMA)

  Will match data against provided schema if it exists
  If it doesn't exist, it will be ignored
  If used on a missing field value, the field will not be in the output

ArrayOf(SCHEMA)

  Will check that all values in the array match the schema
  (i.e. array must have homogenous type)

MapOf(SCHEMA)

  Will check that all fields in the object have values of the same provided type
  There's no schema for the keys since keys are always strings in JSON

Either([SCHEMAS...])

  Will check that data matches at least one of the provided schemas

All([SCHEMAS...])

  Checks that all schemas match - mostly intended for use with CustomValidators

Validator(NAME, function(DATA) => RESULT_OBJECT)

  Custom validator helper
    Name: type name or minimal descriptor used for ref in other errors
    RESULT_OBJECT: {
      result: boolean condition,
      expected: string describing what was expected,
      message: descriptive error message
    }

  Uses provided function to validate data directly.
  If provided function returns `true`, data is considered valid
  If it returns anything else, input data will be considered invalid
  `err` is used for the resulting error message
  if it contains `%s` this will be replaced by the stringified version of the input data


You can also safely nest type functions
```jsonnet
  example: v.Optional(
    v.Custom(function(array)
      if !(std.type(array) == 'array' && std.length(array) >= 3) then
        'ERROR: Expected array of length >= 3'
    )),
```

=== GLOSSARY ===

SCHEMA:
  has same structure as data, but indicates expected types/values

DATA:
  raw input data

VDATA:
  Wrapped input data with metadata fields
  MAYBE_VDATA => indicates the vdata object may have a missing 'value' field

VDATA structure = {
  schemaDescription: human-friendly name of current schema context / expected type

  value: Optional<DATA>,

  errors: ARRAY[{
    path: contextPath,
    error: message,
    ...
  }],

  context: ARRAY[{
    type: field|index,
    value: field name or index number
  }]

  optional: Optional<BOOLEAN>
}

### Advanced: Type Function Anatomy

You can write your own type functions so long as they adhere to this pattern:


```jsonnet
// NOTE: if defining these outside of the libsonnet file,
//       replace $ with the library import var
function(...)
  function(vdata) // -> vdata
    // Extend from passed in vdata object, e.g. `vdata { ... }`
    vdata {
      // Add human-readable description for errors
      schemaDescription: ...
    } +
    // REQUIRED: Check if vdata.value exists, if not return $.withMissingError
    if $.valueMissing(vdata) then
      $.withMissingError
    else
      if CONDITION then
        $.withError({
          error: 'MESSAGE'
          value: std.toString(vdata.value)
        })
      else
        {}
...
Internal utility:
```


VALIDATOR FUNCTIONS
Contract:
  * _MUST_ check if vdata.value field exists, if not return $.withMissingError
  * Recommended: Extend from passed vdata object - if you don't, withError/withMissingError will not work
  * Recommended: Inject { schemaDescription: ... } after vdata - if you don't, you won't get human-readable expected: ... in error output

CONTEXT:
  Array of type/value tuples used to construct a jq-like path for error reporting

// TODO: Consider deprecating composed validations - this adds a ton of complexity and doesn't actually compose intuitively
//       I'm fairly certain there's some nasty bugs hiding in it as well due to limitations of jsonnet
//       I'd rather see this library remain pretty basic as something I can actually use and maintain


---

# Thoughts

Consider renaming to something like constraints.libsonnet?

Also consider reworking into something more meant for unit testing
