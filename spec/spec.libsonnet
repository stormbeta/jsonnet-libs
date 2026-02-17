#!/usr/bin/env jsonnet

// See README.md for usage

// NOTE: Don't use utils.libsonnet here as we may have it use this library later
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
    ),

  indexedFilterMap = function(conditional, func, array)
    [func(i, array[i]) for i in std.find(true, std.map(conditional, array))]
;


{
  // ArrayOf(MapOf(string)) => string
  prettyPrintErrors:: function(errors, indent='')
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
  contextPath:: function(context)
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
  specToString:: function(spec)
    local traverse = function(_spec)
      local type = std.type(_spec);
      if type == 'function' then
        if std.length(_spec) != 1 then
          error 'validators must have one argument'
        else
          // NOTE: This is a horrible hack, but might be unavoidable
          //       We need to be able to inspect spec top-down to report useful errors
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


  // Simple error injector, automatically includes 'expected' and 'context' fields
  // super<VDATA> + withError(string|{LABEL: string}) -> VDATA
  _filename:: if 'file' in self then { file: $.file } else {},
  withError:: function(message)
    {
      local context = super.context,
      local specDescription = super.specDescription,
      local optional = if 'optional' in self then self.optional else false,
      errors+: [
        $._filename
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
    // spec:: spec -> VDATA -> VDATA
    spec:: function(spec, vdata)
      vdata + $.validate(vdata, spec),

    // fieldName:: VDATA -> string -> VDATA
    fieldName:: function(vdata, field)
      (if field in vdata then { value: field } else {}) + {
        errors+: [],
        context: vdata.context + [{ type: 'field', value: field }],
      },

    // fieldValue:: VDATA -> string -> VDATA
    fieldValue: function(vdata, field)
      (if field in vdata.value then { value: vdata.value[field] } else {}) +
      {
        errors+: [],
        context: vdata.context + [{ type: 'field', value: field }],
      },

    // index:: VDATA -> integer -> VDATA
    index:: function(vdata, index) {
      value: vdata.value[index],
      errors+: [],
      context: vdata.context + [{ type: 'index', value: index }],
    },

    // For arrays and objects, we only need to keep value and error fields
    // * 'optional' is used in object bind to strip missing values
    // * 'specDescription' is only used for error reporting, and at this point every
    //    value has already been validated and any errors collected

    // array:: [VDATA] -> VDATA
    array:: function(vdata_array) {
      // TODO: handle Optional correctly in arrays
      //       will probably need to convert to mapWithIndex
      value: [item.value for item in vdata_array],
      errors+: combine([item.errors for item in vdata_array]),
    },

    // object:: {KEY: VDATA ...} -> VDATA
    object:: function(vdata_map) {
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
    vdata { specDescription: '%s' % type } +
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

  // Helper to make it easier to write basic custom conditionals
  Validator:: function(specDescription, customFunction)
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
  // TODO: We should make this the default when encountering `[...]` syntax in spec
  //       It's rare that anyone would want an array with an exact length and diferrent types for each positional element
  ArrayOf:: function(_spec)
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
  // Compatibility
  Array:: self.ArrayOf,

  // Check that all fields in the data match the same spec (similar to Map<String,T> in java)
  MapOf:: function(_spec)
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
          })
  ,


  // Validate field value if it exists, otherwise ignore
  // NOTE: Optional is special-cased by necessity
  Optional:: function(_spec)
    local spec = self.assumeType(_spec);
    function(vdata)
      $.validate(vdata, spec) +
      { optional: true },


  // TODO: Improve error output, especially if used for larger structural differences
  //       Might consider rending specs as actual formatted json
  // Check data against all provided specs, and return the result of the first one that matches (or error if none)
  //Advanced - move to seperate file
  Either:: function(_specs)
    local specs = [self.assumeType(s) for s in _specs];
    function(vdata)
      local results = std.map(
        function(spec) $.validate(vdata, spec), specs
      );
      local valid = std.filter(
        function(_vdata) std.length(_vdata.errors) == 0, results
      );
      vdata {
        specDescription:
          std.join(' | ', ([$.specToString(s) for s in specs])),
      } +
      if !('value' in vdata) then
        $.withMissingError
      else if std.length(valid) == 0 then
        $.withError({
          actual:
            std.type(vdata.value),
          value:
            (if std.type(vdata.value) == 'string'
             then '"' + vdata.value + '"'
             else std.toString(vdata.value)),
        })
      else
        valid[0],

  // Check all specs and return error from the first failed match
  // Limited utility - prefer specifying all requirements in custom validators directly rather than trying to combine them
  //Advanced - move to seperate file
  All:: function(specs)
    // return first element matching condition, without eval'ing whole list
    local lazyFind(list, condition) =
      if list == [] then null
      else if condition(list[0]) then list[0]
      else lazyFind(list[1:], condition);
    function(vdata)
      local results = std.map(
        function(spec) $.validate(vdata, spec), specs
      );
      local valid = std.all([
        std.length(_vdata.errors) == 0
        for _vdata in results
      ]);
      vdata {
        specDescription:
          std.join(' AND ', ([$.specToString(s) for s in specs])),
      } +
      if !('value' in vdata) then
        $.withMissingError
      else if std.type(specs) != 'array' then
        $.withError({
          'error': 'All([specS...]) expects list, got %s' % std.type(specs),
        })
      else if !valid then
        // Some custom functions may fail if using All(...) to
        // combine a standard type check with the custom validator
        // as the custom validator may assume the data type
        lazyFind(results, function(r) std.length(r.errors) > 0)
      else
        vdata,

  Literal:: function(literal, message='Value mismatch')
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
  Equals:: self.Literal,

  //Advanced - move to seperate file
  AllowedFields:: function(fields)
    function(vdata)
      vdata { specDescription: 'AllowedFields(%s)' % std.join(',', fields) } +
      if !('value' in vdata) then
        $.withMissingError
      else
        if !std.isObject(vdata.value) then
          $.withError({
            expected: 'object containing any of these fields: ' + std.toString(fields),
            found: std.type(vdata.value),
          })
        else
          local diff = [
            field
            for field in std.objectFields(vdata.value)
            if !(std.member(fields, field))
          ];
          if std.length(diff) != 0 then
            $.withError({
              expected: 'Only fields named ' + std.toString(fields),
              disallowed: diff,
            })
          else
            {},

  //Advanced - move to seperate file
  HasNamedEntry:: function(match, key='name')
    local name = match[key];
    function(vdata)
      vdata { specDescription: 'HasNamedEntry()' } +
      if !('value' in vdata) then $.withMissingError
      else if std.type(vdata.value) != 'array' then
        $.withError('Cannot check entries of non-array type')
      else
        local entryMatches = indexedFilterMap(
          function(e) std.type(e) == 'object' && key in e && e[key] == name,
          function(i, e) $.validate($.bind.index(vdata, i),
                                    match { [key]: $.Equals(match[key]) }),
          vdata.value
        );
        if std.length(entryMatches) == 0 then
          $.withError({
            result: false,
            'error': "No entry with { '%s': '%s' } found in array" % [key, name],
          })
        else
          local failed = std.filter(function(e) std.length(e.errors) > 0, entryMatches);
          if std.length(failed) == 0 then
            entryMatches[0]
          else
            failed[0],

  // Check that value is one of a provided list of literals
  Enum:: function(literalsArray)
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

  // Validate spec as normal, but cause error if any unknown data/fields present
  // NOTE: this also implicitly freezes the spec for the object
  StrictMap:: function(_spec)
    local spec = self.assumeType(_spec);
    function(vdata)
      // Pass through to normal validation first, then check for extra fields
      $.validate(vdata, spec) +
      { specDescription: 'StrictMap' } +
      if std.type(spec) != 'object' || std.type(vdata.value) != 'object' then
        $.withError({
          'error': 'StrictMap requires object spec, got %s instead' % std.type(spec),
        })
      else
        local diff = std.setDiff(
          std.objectFields(vdata.value),
          std.objectFields(spec)
        );
        if std.length(diff) != 0 then
          $.withError({
            err: 'Unknown fields in strict map',
            fields: diff,
          })
        else
          {},

  validate:: function(vdata, spec, err=null)  // => VDATA
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
  RawValidate:: function(input, spec)
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
  TypeCheck:: function(spec, data, mode=self.mode)
    self.CheckRaw(self.RawValidate(data, spec), mode),

  Validate:: function(data, spec, mode=self.mode)
    self.TypeCheck(spec, data, mode),
}
