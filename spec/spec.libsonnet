#!/usr/bin/env jsonnet

// https://github.com/stormbeta/jsonnet-libs/blob/main/spec/spec.libsonnet

// See README.md for usage

local
  contains = function(collection, ref)
    if std.type(collection) == 'object' then
      ref in collection
    else
      std.member(collection, ref),

  combine = function(items)
    std.foldl(
      function(sum, item) sum + item,
      items,
      []
    )
;

{
  // ArrayOf(MapOf(string)) => string
  prettyPrintErrors(errors, indent='')::
    std.join('\n\n', [
      local maxLength = function(a, b) std.max(a, std.length(b));
      local maxLabelLen = std.foldl(maxLength, std.objectFields(err), 0) + 1;
      std.join('\n', [
        local labelLen = std.length(label);
        indent + std.asciiUpper(label) + ':'
        + std.repeat(' ', maxLabelLen - labelLen) + err[label]
        for label in std.objectFields(err)
      ])
      for err in errors
    ]) + '\n',

  // jq-style representation of current context in object
  // @context: [{type: field|index, value: ...}]
  //                   @field: string
  //                   @index: number
  contextPath(context)::
    if std.length(context) == 0 then
      '.'
    else
      std.foldl(
        function(path, contextEntry)
          path +
          if contextEntry.type == 'index' then
            '[%i]' % contextEntry.value
          else
            // Use more explicit notation if key contains . character already
            if std.member(std.stringChars(contextEntry.value), '.') then
              '.["' + contextEntry.value + '"]'
            else
              '.' + contextEntry.value,
        context,
        ''
      ),

  // Functions cannot be inspected or converted to strings
  // But we still want meaningful error output on function-based validation
  // so functions have the option of including a 'specDescription' into the vdata
  // result, which we obtain by making a dummy call on the type function
  specToString(spec)::
    local traverse = function(_spec)
      local type = std.type(_spec);
      if type == 'function' then
        if std.length(_spec) != 1 then
          error 'validators must have one argument'
        else
          // A bit messy, but only way to inspect spec top-down to report useful errors
          local inspect = _spec({ context: [] });
          if 'specDescription' in inspect then
            inspect.specDescription
          else
            '<function>'
      else if type == 'object' then {
        [field]: traverse(_spec[field])
        for field in std.objectFields(_spec)
      }
      else if type == 'array' then [
        traverse(item)
        for item in _spec
      ]
      else _spec;
    std.toString(traverse(spec)),

  // Optional: `import spec.libsonnet) { filename: std.thisFile };`
  // Will inject filename of including file into default error outputs
  __file__:: if 'filename' in self then { file: $.filename } else {},

  // Simple error injector, automatically includes 'expected' and 'context' fields
  // super<VDATA> + withError(string|{LABEL: string}) -> VDATA
  withError(message)::
    {
      local context = super.context,
      local specDescription = super.specDescription,
      local optional = if 'optional' in self then self.optional else false,
      errors+: [
        $.__file__
        {
          path: $.contextPath(context),
          expected: specDescription +
                    if optional then '?' else '',
        } +
        if std.type(message) == 'string' then
          { 'error': message }
        else
          message,
      ],
    },

  // Inject standard missing field error
  // All function validators should return this if VDATA.value is missing
  // super<VDATA> + withMissingError() -> VDATA
  withMissingError:: {
    local ctx = self,
    errors+: [{
      path: $.contextPath(ctx.context),
      'error': 'Required field does not exist: ' + self.path,
      expected: ctx.specDescription,
    }],
  },

  // Functions to wrap data in vdata structure
  bind:: {
    // Wrap value of field with field name as context
    // VDATA(vdata.value[field])
    fieldValue: function(vdata, field)
      (if field in vdata.value then { value: vdata.value[field] } else {}) +
      {
        errors+: [],
        context: vdata.context + [{ type: 'field', value: field }],
      },

    // index:: VDATA -> integer -> VDATA
    // Wrap array element with index as context
    // VDATA(vdata.value[index])
    index(vdata, index):: {
      value: vdata.value[index],
      errors+: [],
      context: vdata.context + [{ type: 'index', value: index }],
    },

    // For arrays and objects, we only need to keep value and error fields
    // * 'optional' is used in object bind to strip missing values
    // * 'specDescription' is only used for error reporting, and at this point every
    //    value has already been validated and any errors collected

    // array:: [VDATA] -> VDATA
    // Assume every element of array has already been wrapped, and wrap array itself as VDATA struct
    array(vdata_array):: {
      // TODO: handle Optional correctly in arrays
      //       will probably need to convert to mapWithIndex
      value: [item.value for item in vdata_array],
      errors+: combine([item.errors for item in vdata_array]),
    },

    // object:: {KEY: VDATA ...} -> VDATA
    // Assume every value has already been wrapped, and wrap object itself as VDATA struct
    object(vdata_map):: {
      value+: {
        [field]: vdata_map[field].value
        for field in std.objectFields(vdata_map)
        if !(std.get(vdata_map[field], 'optional', false) && !contains(vdata_map[field], 'value'))
      },
      errors+: combine([
        field_vdata.errors
        for field_vdata in std.objectValues(vdata_map)
        if !(std.get(field_vdata, 'optional', false) && !contains(field_vdata, 'value'))
      ]),
    },
  },

  // Assume strings are primitive type names when passed to other validator functions
  assumeType(spec):: if std.type(spec) == 'string' then self.Is(spec) else spec,

  // Primitive type checks
  Is(type):: function(vdata)
    vdata { specDescription: type } +
    if !('value' in vdata) then
      $.withMissingError
    else
      local vtype = std.type(vdata.value);
      if vtype != type && type != 'any' then
        $.withError({
          'error': 'Type mismatch',
          //expected: self.expected_type,
          expected: type,
          found: vtype,
        })
      else
        {},
  Any:: self.Is('any'),
  String:: self.Is('string'),
  Number:: self.Is('number'),
  Boolean:: self.Is('boolean'),
  Array:: self.Is('array'),
  Object:: self.Is('object'),
  Null:: self.Is('null'),

  // Helper to make it easier to write basic custom conditionals
  Validator(specDescription, customFunction)::
    function(vdata)
      vdata { specDescription: specDescription } +
      (
        if !('value' in vdata) then
          $.withMissingError
        else
          local ftype = std.type(customFunction);
          local result =
            if ftype == 'object'
            then { value:: vdata.value } + customFunction
            else customFunction(vdata.value);
          if std.type(result) == 'boolean' && result then
            vdata
          else if std.type(result) == 'object' && 'result' in result then
            if result.result then
              vdata
            else
              $.withError(result { actual_value: vdata.value, result:: null })
          else
            // Treat result as string-like error message or value
            $.withError(std.toString(result))
      ),

  // Check that all values in the array match the same spec (similar to Array<T> in java)
  ArrayOf(_spec)::
    local spec = self.assumeType(_spec);
    function(vdata)
      vdata
      { specDescription: 'array[%s]' % $.specToString(spec) } +
      if !('value' in vdata) then
        $.withMissingError
      else if std.type(vdata.value) != 'array' then
        $.withError({
          actual_type: std.type(vdata.value),
          value: vdata.value,
        })
      else
        $.bind.array(
          std.mapWithIndex(
            function(index, _)
              $.validate($.bind.index(vdata, index), spec),
            vdata.value
          )
        ),

  // Check that all fields in the data match the same spec (similar to Map<String,T> in java)
  MapOf(_spec)::
    local spec = self.assumeType(_spec);
    function(vdata)
      vdata
      { specDescription: 'map{%s}' % $.specToString(spec) } +
      if !('value' in vdata) then
        $.withMissingError
      else
        if std.type(vdata.value) != 'object' then
          $.withError({
            actual_type: std.type(vdata.value),
            value: vdata.value,
          })
        else
          $.bind.object({
            [field]: $.validate($.bind.fieldValue(vdata, field), spec)
            for field in std.objectFields(vdata.value)
          }),

  // Validate field value if it exists, otherwise ignore
  // NOTE: Optional is special-cased by necessity
  Optional(_spec)::
    local spec = self.assumeType(_spec);
    function(vdata)
      $.validate(vdata, spec) +
      { optional: true },

  // This is already the default behavior for primitives
  Equals(literal, message='Value mismatch')::
    function(vdata)
      vdata {
        specDescription: std.toString(literal),
      }
      + if !('value' in vdata) then
        $.withMissingError
      else
        if vdata.value != literal then
          $.withError({
            'error': message,
            found: vdata.value,
          })
        else {},
  // alias - deprecate
  Literal:: self.Equals,

  // Check that value is one of a provided list of literals
  Enum(literalsArray)::
    function(vdata)
      vdata {
        specDescription:
          '{%s}' % std.join(', ', literalsArray),
      }
      +
      if !('value' in vdata) then
        $.withMissingError
      else
        if !std.member(literalsArray, vdata.value) then
          $.withError({
            'error': 'Value not allowed',
            value: std.toString(vdata.value),
          })
        else {},

  validate(vdata, spec, err=null)::  // => VDATA
    local dataType = std.type(vdata.value);
    local specType = std.type(spec);

    vdata
    // Generate and inject spec description field for human-friendly errors
    { specDescription: $.specToString(spec) }
    +
    // Passthrough existing error array so it can be extended instead of overwritten in return
    { errors+: if err != null then [err] else [] }
    +

    // This must be done first, or else type functions like Optional will never
    // get the opportunity to handle missing values before it becomes an error
    // Caveat is this means all type functions *MUST* handle the possibility
    // of a missing value themselves!
    if specType == 'function' then
      spec(vdata)

    // Check if field is missing
    else if !('value' in vdata) then
      $.withMissingError

    // Recurse into object spec
    else if specType == 'object' && dataType == 'object' then
      $.bind.object({
        [field]: $.validate(
          $.bind.fieldValue(vdata, field),
          if field in spec then
            spec[field]
          else
            $.Any
        )
        for field in std.set(std.objectFields(spec) + std.objectFields(vdata.value))
      })

    // Recurse into fixed array spec - this will likely be a rare case
    // as most arrays are not fixed length/positional
    // TODO: Consider making this an alias for ArrayOf(...) instead
    //       and make this the special case?
    else if specType == 'array' && dataType == 'array' then
      if std.length(spec) != std.length(vdata.value) then
        $.withError({
          'error': 'Array length does not match spec',
          expect_length: std.length(spec),
          actual_length: std.length(vdata.value),
        })
      else
        $.bind.array(
          std.mapWithIndex(
            function(index, _)
              $.validate($.bind.index(vdata, index), spec[index])
            , spec
          )
        )

    // Assume literal value check
    else
      if vdata.value == spec then
        {}
      else
        $.withError({
          path: $.contextPath(vdata.context),
          found_type: dataType,
          actual: (if dataType == 'string'
                   then '"' + vdata.value + '"'
                   else vdata.value),
        }),

  // Returns raw vdata result, can be extended before checking
  RawValidate(input, spec)::
    $.validate({
      value: input,
      context: [],
      errors+: [],
      failed:: std.length(self.errors) > 0,
    }, spec),

  // One of: error, warn, json
  // TODO: Get rid of "json" mode in favor of things just using RawValidate
  mode: 'error',
  // Processes results, returning original value if spec passes, otherwise pretty prints errors
  // if mode==json, returns just the errors object
  CheckRaw(result, mode=self.mode)::
    if std.length(result.errors) > 0 then
      local err = '\n' + $.prettyPrintErrors(result.errors);
      if mode == 'warn' then
        std.trace(err, result.value)
      else if mode == 'json' then
        { errors+: result.errors }
      else
        error err
    else
      result.value,

  // Reconstructs and returns input data in-line
  // Intended for inline validation for functions and templates
  TypeCheck(spec, data, mode=self.mode)::
    self.CheckRaw(self.RawValidate(data, spec), mode),

  Validate(data, spec, mode=self.mode)::
    self.TypeCheck(spec, data, mode),
}
