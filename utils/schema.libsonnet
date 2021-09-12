#!/usr/bin/env jsonnet

/* DESIGN issues:
Current model is to raise error at point of invalidity, and otherwise return input data

But jsonnet doesn't have any concept of exception handling, so errors are always immediately failures,
and all possible data types are themselves valid JSON except functions (which is how we're fudging it now)

We can kind of fudge enum/field optionals, but there's no good way to do union types since we can't recover to try a different type if the first type fails to validate

Array optionals are kind of a headache, and I'm not sure I even want to bother supporting that regardless
I can't really think of any scenario in which positional Array optionals even make sense
---
We might want to re-write this to make error handling far more explicit
E.g. return value of validate would always have multiple sections.
Another reason to do it that way: it would dramatically simplify unit testing of error conditions
---

Rationale for jsonnet:
No external dependencies beyond jsonnet itself :)
Ridiculously easy to unit-test due to the inherent limits of jsonnet
TODO: Actually write said unit tests lol
*/

local
  contains = function(collection, ref)
    if std.type(collection) == 'object' then
      std.member(std.objectFields(collection), ref)
    else
      std.member(collection, ref),

  // jq-style representation of current context in object
  // @context: [{type: field|index|FIELD_MISSING, value: ...}]
  contextPath = function(context)
    std.foldl(
      function(path, contextEntry)
        path +
        if contextEntry.type == 'index'
        then '[' + std.toString(contextEntry.value) + ']'
        else '.' + contextEntry.value,
      context,
      ''
    );

{
  // Extension type spec:
  // function(validationFunction, intput, context)
  //   validationFunction: TODO: probably not needed if we just re-arranged the lib scripts to make
  //   everything in the same scope
  // If type of nearest context is 'FIELD_MISSING', **MUST** return true/false
  //   true: error if field is missing
  //  false: field allowed to be missing, field will not appear in output
  // Otherwise, it should act the same as the main validation functions:
  //   If valid, return input
  //   Otherwise raise meaningful error

  // Validate every item in an arbitrary-length array matches the provided schema
  Array:: function(schema)
    function(validationFunction, input, context)
      if context[std.length(context) - 1].type == 'FIELD_MISSING' then
        true
      else
        std.mapWithIndex(
          function(index, _)
            validationFunction(input[index], schema, context + [{ type: 'index', value: index }]),
          input
        ),

  // Validate the value of every field in the object matches the provided schema
  Fields:: function(schema)
    function(validationFunction, input, context)
      if context[std.length(context) - 1].type == 'FIELD_MISSING' then
        true
      else if std.type(input) == 'object' then
        {
          [field]: validationFunction(input[field], schema, context + [{ type: 'field', value: field }])
          for field in std.objectFields(input)
        }
      else
        // Re-use normal top-level type failure error
        validationFunction(input, 'object', context),

  // Allows an object field to be missing
  // NOTE: Positional entries in arrays not supported!
  Optional:: function(schema)
    function(validationFunction, input, context)
      // TODO: Add logging info call to indicate optional not found
      if context[std.length(context) - 1].type == 'FIELD_MISSING' then
        false
      else
        validationFunction(input, schema, context),

  Enum:: function(literalsArray)
    if std.type(literalsArray) != 'array' then
      error 'SCHEMA INVALID'
    else
      function(validationFunction, input, context)
        if context[std.length(context) - 1].type == 'FIELD_MISSING' then
          true
        else
          if 0 < std.length(std.filter(
            function(item) input == item, literalsArray
          ))
          then input
          else error 'Schema failure:\n'
                     + '    PATH: ' + contextPath(context) + '\n'
                     + 'EXPECTED: Literal matching one of ' + std.toString(literalsArray) + '\n'
                     + '  ACTUAL: ' + std.toString(input) + '\n',

  // Not yet supported, unsupportable without large scale refactor since we can't catch errors
  // Workaround: cast multi-type to 'any' :(
  //Union:: function(schemaArray) ...,

  // Returns input if it matches schema, error if not
  validate:: function(input, schema, context=[])
    local inputType = std.type(input),
          schemaType = std.type(schema);

    if schema == 'any' then
      input

    else if schemaType == 'object' && inputType == 'object' then
      {
        // Validate input data
        [field]:
          if contains(input, field) then
            if std.type(schema[field]) != 'function' then
              $.validate(input[field], schema[field], context + [{ type: 'field', value: field }])
            else
              schema[field]($.validate, input[field], context + [{ type: 'field', value: field }])
          else error 'Schema failure:\n'
                     + ' PATH: ' + contextPath(context) + '\n'
                     + 'ERROR: field "' + field + '" does not exist!\n'
        for field in std.objectFields(schema)
        // Ugly helper to ensure optional fields don't show up in output if they weren't in input
        if !(std.type(schema[field]) == 'function'
             && !contains(input, field)
             && !schema[field](null, null, [{ type: 'FIELD_MISSING', value: null }]))
      }

    else if schemaType == 'array' && inputType == 'array' then
      if std.length(input) != std.length(schema) then
        error 'Schema failure:\n'
              + ' PATH: ' + contextPath(context) + '[]\n'
              + 'ERROR: length mismatch: '
              + std.toString(std.length(input)) + ' != ' + std.toString(std.length(schema))
      else std.mapWithIndex(
        function(index, _)
          $.validate(input[index], schema[index], context + [{ type: 'index', value: index }]),
        schema
      )

    else if std.member(['array', 'object'], schema) && std.member(['array', 'object'], inputType) then
      input

    else if schemaType == 'function' then
      schema($.validate, input, context)

    else
      if inputType == schema then
        input
      else
        error 'Schema failure:\n'
              + '    PATH: ' + contextPath(context) + '\n'
              + 'EXPECTED: ' + schema + '\n'
              + '  ACTUAL: ' + inputType + '\n'
              + '   VALUE: ' + (if inputType == 'string'
                                then '"' + input + '"'
                                else std.toString(input)) + '\n',
}
