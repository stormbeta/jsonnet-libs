# spec.libsonnet

Pure jsonnet library for adding type checking to calls

**Motivation**

Because jsonnet is purely functional, it can be tricky to debug issues that happen in more complex
scripts with intermediate data structures and layered functions, especially keeping track of the
structure between different contexts.

This library aims to add inline type and constraint checks that can produce human-readable errors
instead of a cryptic stack trace.

NOTE: This is not intended as a JSON spec validator - you could use it that way, but there are many
better tools and libraries for that.

**Example**

```jsonnet
local t = (import 'spec.libsonnet') { file: std.thisFile };

local spec = {
  hello: t.String,
  entries: t.ArrayOf({
    name: t.String,
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

t.TypeCheck(spec, data),
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

        spec.libsonnet:433:9-18       function <anonymous>
        example.jsonnet:24:1-26
```

- This works for arbitrarily nested structures and types

- Path is a `jq`-style reference.

- The `?` in the "expected" field signifies that this field or item was optional


**Custom Validator Example**

```jsonnet
local t = (import 'spec.libsonnet') { file: std.thisFile };

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
      name: t.String,
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


### spec Reference

**Primitives**

Primitives in the spec are matched literally by default, i.e. must match input exactly

To check the type of the input rather than its value:

* Call `Is(...)` with the type name, e.g. 'string', 'object', 'number', 'array', 'boolean', etc.

* Call the capitalized aliases, e.g `String`, `Object`, etc.

* Things like `ArrayOf` will assume strings are references to type names and not the literal string.

**Objects or arrays**

In the spec, are used to recurse down and validate nested values. By default, only fields present in
the spec will be checked and all others ignored.

For everything else, see type functions below:

Type Functions
-------------------

Helpers to specify other kinds of constraints

Enum([VALUES...])

  Data must equal one of the provided literals

Optional(SPEC)

  Will match data against provided spec if it exists
  If it doesn't exist, it will be ignored
  If used on a missing field value, the field will not be in the output

ArrayOf(SPEC)

  Will check that all values in the array match the spec
  (i.e. array must have homogenous type)

MapOf(SPEC)

  Will check that all fields in the object have values of the same provided type
  There's no spec for the keys since keys are always strings in JSON


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

SPEC:
  has same structure as data, but indicates expected types/values

DATA:
  raw input data

VDATA:
  Wrapped input data with metadata fields
  MAYBE_VDATA => indicates the vdata object may have a missing 'value' field

VDATA structure = {
  specDescription: human-friendly name of current spec context / expected type

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
      specDescription: ...
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
  * Recommended: Inject { specDescription: ... } after vdata - if you don't, you won't get human-readable expected: ... in error output

CONTEXT:
  Array of type/value tuples used to construct a jq-like path for error reporting

// TODO: Consider deprecating composed validations - this adds a ton of complexity and doesn't actually compose intuitively
//       I'm fairly certain there's some nasty bugs hiding in it as well due to limitations of jsonnet
//       I'd rather see this library remain pretty basic as something I can actually use and maintain


**Extended Functions**

These are functions that may be helpful, but add complexity to the output / reporting

Import `spec_extended.libsonnet` instead to enable these:

Either([SPECS...])

  Will check that data matches at least one of the provided specs

All([SPECS...])

  Checks that all specs match - mostly intended for use with CustomValidators
