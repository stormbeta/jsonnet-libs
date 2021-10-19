#!/usr/bin/env jsonnet

/*
=== Schema Reference ===

Primitives, e.g. 'string', 'object', 'number', 'array', etc.
  These are matched directly using jsonnet's std.type(...)

Objects or arrays in the schema are used to recurse down and validate nested values

Function extensions
-------------------

Enum([VALUES...])
  Data must literally equal one of the provided values

Optional(SCHEMA)
  Will match data gainst provided schema if it exists
  If it doesn't exist, it will be ignored
  If used on a field value, the field will not be in the output

Array(SCHEMA)
  Will check that all values in the array match the schema
  (i.e. array must have homogenous type)

MapOf(SCHEMA)
  Will check that all fields in the object have values of the same provided type
  There's no schema for the keys since keys are always string in JSON

Either([SCHEMAS...])
  Will check that data matches at least one of the provided schemas

Custom(FUNCTION(DATA)->[ERRORS...])
  Uses provided function to validate data directly.
  If error array is empty, data is valid

If you want to write your own function, it must look something like this:
function(...)
  function(validate, vdata) -> vdata
     // CAUTION: vdata.value is allowed to be null here, and you must handle that case!
     // 'validate' arg is the internal validator function with signature `validate(vdata, schema)`
     // NOTE: if you choose not to call the internal validator, you must ensure you return an intact vdata object yourself!

Example identity function:
```jsonnet
  example: function(schema)
    function(validate, vdata)
      validate(vdata, schema)
```

Example no-op function that returns input with no further validation
```jsonnet
  example: function(validate, vdata)
    vdata
```

You can also safely nest things however you want, e.g.:
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

CONTEXT:
  Array of type/value tuples used to construct a jq-like path for error reporting
*/

local
  contains = function(collection, ref)
    if std.type(collection) == 'object' then
      std.objectHas(collection, ref)
    else
      std.member(collection, ref),

  combine = function(items)
    std.foldl(
      function(sum, item) sum + item,
      items,
      []
    ),

  prettyPrintErrors = function(errors)
    std.join('\n\n', [
      local maxLength = function(a, b) std.max(a, std.length(b));
      local maxLabelLen = std.foldl(maxLength, std.objectFields(err), 0) + 1;
      std.join('\n', [
        local labelLen = std.length(label);
        std.asciiUpper(label) + ':'
        + std.repeat(' ', maxLabelLen - labelLen) + err[label]
        for label in std.objectFields(err)
      ])
      for err in errors
    ]) + '\n',


  // safe field reference with default if field not present
  maybeGet = function(object, field, default={})
    if std.objectHas(object, field)
    then object[field]
    else default,

  // TODO: move to library function
  // Functions cannot be inspected or converted to strings
  // But we still want meaningful error output on function-based validation
  // so functions have the option of including a 'schemaString' into the vdata
  // result, which we obtain by making a dummy call on the extension function
  schemaToString = function(validate, schema)
    local traverse = function(_schema)
      local type = std.type(_schema);
      if type == 'function' && std.length(_schema) == 2 then
        // TODO: This a horrible hack
        //       But there might not be a better way, we need to be able to inspect
        //       schema top-down to report useful errors
        local inspect = _schema(validate, { context: [] });
        if std.objectHas(inspect, 'schemaString') then
          inspect.schemaString
        else
          '<function>'
      else if type == 'object' then {
        [field]: traverse(_schema[field])
        for field in std.objectFields(_schema)
      }
      else if type == 'array' then [
        traverse(item)
        for item in _schema
      ]
      else _schema;
    std.toString(traverse(schema))
;


{
  VData:: {
    // DATA => VDATA
    lift:: function(data) {
      value: data,
      errors: [],
      context: [],
    },

    bindField:: function(vdata, field)
      (if contains(vdata.value, field) then
         { value: vdata.value[field] }
       else {})
      + {
        errors: [],
        context: vdata.context + [{ type: 'field', value: field }],
      },

    bindIndex:: function(vdata, index) {
      value: vdata.value[index],
      errors: [],
      context: vdata.context + [{ type: 'index', value: index }],
    },

    // VDATA => DATA else ERRORS
    unwrap:: function(vdata)
      if std.length(vdata.errors) == 0
      then vdata.value
      else error (std.foldl(
                    function(sum, err) sum + '\n' + err,
                    vdata.errors,
                    ''
                  )),

    // [VDATA] => VDATA
    rebindArray:: function(vdata_array) {
      // TODO: handle Optional correctly in arrays
      //       will probably need to convert to mapWithIndex
      value: [item.value for item in vdata_array],
      errors: combine([item.errors for item in vdata_array]),
    },

    // {K: VDATA, ...} => VDATA
    rebindObject:: function(vdata_map) {
      value+: {
        [field]: vdata_map[field].value
        for field in std.objectFields(vdata_map)
        if !(maybeGet(vdata_map[field], 'optional', false) && !contains(vdata_map[field], 'value'))
      },
      errors+: combine([
        field_vdata.errors
        for field_vdata in std.objectValues(vdata_map)
        if !(maybeGet(field_vdata, 'optional', false) && !contains(field_vdata, 'value'))
      ]),
    },
  },

  // jq-style representation of current context in object
  // @context: [{type: field|index|FIELD_MISSING, value: ...}]
  contextString:: function(context)
    if std.length(context) == 0 then
      '.'
    else
      std.foldl(
        function(path, contextEntry)
          path +
          if contextEntry.type == 'index' then
            '[%i]' % contextEntry.value
          else
            '.' + contextEntry.value,
        context,
        ''
      ),

  addError:: function(vdata, message, label='error')
    vdata {
      errors+: [
        { path: $.contextString(vdata.context) } +
        if std.type(message) == 'string' then
          { [label]: message }
        else
          message,
      ],
    },

  missingError:: function(vdata)
    $.addError(vdata, 'required field does not exist!'),

  // Helper to make it easy to write basic custom conditionals
  // Return true/non-string for validness
  Custom:: function(customFunction, errMessage='%s')
    function(validate, vdata)
      { schemaString: 'custom' } +
      (if !std.objectHas(vdata, 'value') then
         $.missingError(vdata)
       else
         local result = customFunction(vdata.value);
         if std.type(result) == 'boolean' && result
         then vdata
         else $.addError(vdata, errMessage % vdata.value)),

  // Check that all values in the array match the same schema (similar to Array<T> in java)
  Array:: function(schema)
    function(validate, maybe_vdata)
      {
        context: maybe_vdata.context,
        schemaString: 'Array[%s]' + schemaToString(validate, schema),
      } +
      if !std.objectHas(maybe_vdata, 'value') then
        $.missingError(maybe_vdata)
      else if std.type(maybe_vdata.value) != 'array' then
        $.addError(maybe_vdata, 'Array[%s]' % schemaToString(validate, schema), 'expected')
      else
        $.VData.rebindArray(
          std.mapWithIndex(
            function(index, _)
              validate($.VData.bindIndex(maybe_vdata, index), schema)
            , maybe_vdata.value
          )
        ),

  // Check that all fields in the data match the same schema (similar to Map<String,T> in java)
  MapOf:: function(schema)
    function(validate, maybe_vdata)
      local schemaString = 'Map{%s}' % schemaToString(validate, schema);
      {
        context: maybe_vdata.context,
        schemaString: schemaString,
      } +
      (if contains(maybe_vdata, 'value') then
         if std.type(maybe_vdata.value) != 'object' then
           $.addError(maybe_vdata, {
             expected: schemaString,
             actual: std.type(maybe_vdata.value),
             value: maybe_vdata.value,
           })
         else
           $.VData.rebindObject({
             [field]: validate($.VData.bindField(maybe_vdata, field), schema)
             for field in std.objectFields(maybe_vdata.value)
           })
       else $.missingError(maybe_vdata)),

  // Validate if exists, otherwise ignore
  // TODO: Allow specifying a default value
  Optional:: function(schema)
    function(validate, maybe_vdata)
      // TODO: This is really ugly, and we should be handling schemaString better
      validate(maybe_vdata { schemaString: schemaToString(validate, schema) + '?' }, schema) {
        optional: true,
        schemaString: schemaToString(validate, schema) + '?',
      },

  // Check data against all provided schemas, and return the result of the first one that matches (or error if none)
  Either:: function(schemas)
    function(validate, maybe_vdata)
      local results =
        std.filter(
          function(_vdata) std.length(_vdata.errors) == 0,
          std.map(
            function(schema) validate(maybe_vdata, schema),
            schemas
          )
        );
      {
        schemaString:
          std.join('|', ([schemaToString(validate, s) for s in schemas])),
      } +
      if !contains(maybe_vdata, 'value') then
        $.missingError(maybe_vdata)
      else if std.length(results) == 0 then
        $.addError(maybe_vdata, {
          expected: 'ANY OF ' + schemaToString(validate, schemas),
          actual: std.type(maybe_vdata.value),
          value: (if std.type(maybe_vdata.value) == 'string'
                  then '"' + maybe_vdata.value + '"'
                  else std.toString(maybe_vdata.value)),
        })
      else
        results[0],

  Enum:: function(literalsArray)
    // TODO: handle missing vdata.value case
    function(validate, maybe_vdata)
      { schemaString: 'Enum' } +
      if std.member(literalsArray, maybe_vdata.value) then
        maybe_vdata
      else
        $.addError(maybe_vdata, {
          expected: 'Literal matching one of ' + std.toString(literalsArray),
          actual: std.toString(maybe_vdata.value),
        }),

  RawValidate:: function(input, schema)
    local validate = function(vdata, schema)  // => VDATA
      local dataType = std.type(vdata.value);
      local schemaType = std.type(schema);

      // This must be done first, or else extensions like Optional will never
      // get the opportunity to handle missing values before it becomes an error
      // Caveat is this means all extension handlers *MUST* handle the possibility
      // of a missing value themselves!
      if schemaType == 'function' then
        schema(validate, vdata)

      // Check if field is missing
      else if !contains(vdata, 'value') then
        $.addError(vdata, {
          'error': 'required field does not exist!',
        })

      else if schema == 'any' then
        vdata

      // Recurse into object schema
      else if schemaType == 'object' && dataType == 'object' then
        // TODO: additional validator to force strict checking
        //       i.e. data has no fields that aren't in schema
        // TODO: unknown fields in the data are silently ignored/dropped, which probably isn't desirable default behavior
        { context: vdata.context } +
        $.VData.rebindObject({
          [field]: validate($.VData.bindField(vdata, field), schema[field])
          for field in std.objectFields(schema)
        })

      // Recurse into fixed array schema - this will likely be a rare case
      // as most arrays are not fixed length/positional
      else if schemaType == 'array' && dataType == 'array' then
        { context: vdata.context } +
        if std.length(schema) != std.length(vdata.value) then
          $.addError(vdata, {
            'error': 'Array length does not match schema',
            expected: std.length(schema),
            actual: std.length(vdata.value),
          })
        else
          $.VData.rebindArray(
            std.mapWithIndex(
              function(index, _)
                validate($.VData.bindIndex(vdata, index), schema[index])
              , schema
            )
          )

      else if std.member(['array', 'object'], schema) && std.member(['array', 'object'], dataType) then
        vdata

      else
        if dataType == schema then
          vdata
        else
          vdata {
            errors+: [{
              path: $.contextString(vdata.context),
              // TODO: This is really messy - we could maybe handle schemaString explicitly
              //       like we do with the context path?
              expected: maybeGet(vdata, 'schemaString', schema),
              actual: dataType,
              value: (if dataType == 'string'
                      then '"' + vdata.value + '"'
                      else std.toString(vdata.value)),
            }],
          };
    validate($.VData.lift(input), schema),

  JsonValidate:: function(data, schema)
    local result_vdata = self.RawValidate(data, schema);
    if std.length(result_vdata.errors) > 0 then
      { errors: result_vdata.errors }
    else
      result_vdata.value
  ,

  Validate:: function(data, schema)
    local result_vdata = self.RawValidate(data, schema);
    if std.length(result_vdata.errors) > 0 then
      error '\n' + prettyPrintErrors(result_vdata.errors)
    else
      result_vdata.value,
}
