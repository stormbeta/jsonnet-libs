#!/usr/bin/env jsonnet

// More advanced spec checks and functions

// TODO: move to utils.libsonnet?
local indexedFilterMap = function(conditional, func, array)
  [func(i, array[i]) for i in std.find(true, std.map(conditional, array))];

(import 'spec.libsonnet') {
  // TODO: Improve error output, especially if used for larger structural differences
  //       Might consider rending specs as actual formatted json
  // Check data against all provided specs, and return the result of the first one that matches (or error if none)
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

}
