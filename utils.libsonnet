#!/usr/bin/env jsonnet

// TODO: Add tests for newly added functions

{
  version:: '2.2',
  log:: {
    // Everything in jsonnet is an expression with a meaningful return value
    // So logging should wrap some kind of actual value and return it in-place
    ERROR:: 0,
    WARN:: 1,
    INFO:: 2,
    TRACE:: 3,

    level:: self.WARN,

    // Don't need a level for error since we already have the `error` builtin
    withWarning:: function(msg, any)
      if self.level > 0
      then std.trace('\n\t[WARN] ' + msg, any)
      else any,

    withLog:: function(msg, any)
      if self.level > 1
      then std.trace('\n\t[INFO] ' + msg, any)
      else any,

    trace:: function(any)
      if self.level > 2
      then std.trace(std.toString(any), any)
      else any,
  },


  combine:: function(parent, child) parent + child,


  // Get last item of array
  last:: function(array) array[std.length(array) - 1],

  // Combines std.filter with std.mapWithIndex into one operation
  indexedFilterMap:: function(conditional, func, array)
    [func(i, array[i]) for i in std.find(true, std.map(conditional, array))],

  // Merge-reduce array of objects
  mergeObjectArray:: function(objectArray)
    assert std.all([std.type(item) == 'object' for item in objectArray]);
    std.foldl(self.combine, objectArray, {}),


  // Similar to `if ref in collection` in Python
  contains:: function(collection, ref)
    if std.type(collection) == 'object' then
      std.member(std.objectFields(collection), ref)
    else
      std.member(collection, ref),


  // Find objects in array with field keyName matching keyValue
  // Returns empty array if none found
  findBy:: function(objectArray, keyName, keyValue)
    [
      entry
      for entry in objectArray
      if std.isObject(entry) && keyName in entry && entry[keyName] == keyValue
    ],


  // safe field reference with default if field not present
  //   local cfg = { configField: "value" };
  //   ...
  //   utils.optional(config, 'configField', {}) == "value"
  //   utils.optional(config, 'missingField', "none") == "none"
  optional:: function(object, field, default={}, handler=function(v) v)
    if field in object
    then handler(object[field])
    else default,

  // All except the first item of an array, equivalent to python's array[1:-1]
  tail:: function(array)
    std.slice(array, 1, std.length(array), 1),

  // Safe deep field/array indexing using a list of keys
  // collection: array | object
  // path: [string|number|object] | string
  //   for each item in path array:
  //     string: use as field name if current target is an object
  //     number: use as index if current target is an array
  //     object: use to find an object by the given key-values in an array
  //     If none of these match or types don't align, returns default
  //   path is string: alias for utils.optional
  //   local cfg = { top: "top_value", outer: { inner: { most: "value" } } };
  //   ...
  //   utils.safeGet(cfg, ['outer', 'inner', 'most'], {}) == "value"
  //   utils.safeGet(cfg, ['outer', 'oops', 'most'], {}) == {}
  //   utils.safeGet(cfg, 'top', "") == "top_value"
  //   utils.safeGet(cfg, 'missing', "default") == "default"
  safeGet:: function(collection, path, default={}, handler=function(v) v)
    local pathLength = std.length(path);
    if !std.isArray(path) then
      self.safeGet(collection, [path], default, handler)
    else if pathLength == 0 then
      default
    else
      // TODO: Should show warning if head is object and has more than one entry
      local head = path[0];
      local keyName = std.objectFields(head)[0],
            keyValue = head[keyName],
            found = self.findBy(collection, keyName, keyValue);
      local next =
        if (std.isString(head) && std.isObject(collection) && head in collection)
           || (std.isNumber(head) && std.isArray(collection) && std.length(collection) >= head + 1) then
          [true, collection[head]]
        else if std.isObject(head) && std.isArray(collection) && std.length(std.objectFields(head)) == 1 && std.length(found) == 1 then
          [true, found[0]]
        else
          [false, default];
      if !next[0] then
        default
      else if pathLength > 1 then
        self.safeGet(next[1], self.tail(path), default, handler)
      else
        handler(next[1])
  ,

  // TODO: belongs in testsuite really
  inspect(collection, path, context=[])::
    local contextPath = function(ctx)
      if std.length(ctx) == 0 then '.' else
        std.foldl(
          function(path, ctxEntry)
            path +
            if ctxEntry.type == 'index' then
              '[%i]' % ctxEntry.value
            else if ctxEntry.type == 'entry' then
              '{%s=%s}' % ctxEntry.value
            else
              // Use more explicit notation if key contains . character already
              if std.member(std.stringChars(ctxEntry.value), '.') then
                '.["' + ctxEntry.value + '"]'
              else
                '.' + ctxEntry.value,
          ctx,
          ''
        );
    local pathLength = std.length(path);
    if !std.isArray(path) then
      self.inspect(collection, [path])
    else if pathLength == 0 then
      { err: 'Path empty', context: context }
    else
      // TODO: Should show warning if head is object and has more than one entry
      local head = path[0];
      local keyName = std.objectFields(head)[0],
            keyValue = head[keyName],
            found = self.findBy(collection, keyName, keyValue);
      local expectedType =
        if std.isString(head) || std.isObject(head) then 'object'
        else if std.isNumber(head) then 'array'
        else 'invalid';
      local next =
        if (std.isString(head) && std.isObject(collection) && head in collection)
           || (std.isNumber(head) && std.isArray(collection) && std.length(collection) >= head + 1) then
          [true, collection[head]]
        else if std.isObject(head) && std.isArray(collection) && std.length(std.objectFields(head)) == 1 && std.length(found) == 1 then
          [true, found[0]]
        else if expectedType == 'invalid' then
          [false, {
            err: 'Invalid path element type, must be field name, index number, or { key: value }',
            element: head,
            type: std.type(head),
          }]
        else if expectedType != std.type(collection) then
          [false, {
            err: 'Type mismatch, %s cannot be applied to %s' % [std.type(head), std.type(collection)],
            expected: expectedType,
            element: head,
          }]
        else
          [false, {
            err: std.toString(head) + ' not found',
            collection: expectedType,
            f: std.type(collection),
          }];
      if !next[0] then
        { err: '' }
      else if pathLength > 1 then
        self.inspect(next[1], self.tail(path), context + [{
          type: if std.isString(head) then 'field' else if std.isNumber(head) then 'index' else 'entry',
          value: head,
        }])
      else
        { value: next[1] },

  // Given a list of entries, merge-reduce all entries with matching values for the given key
  // Useful for appending overrides to lists of entries, e.g. kuberentes resources
  combineEntriesByKey:: function(key, entries, mergeMethod=self.mergeObjectArray)
    [
      mergeMethod(group)
      for group in [
        std.filter(function(entry) entry[key] == name, entries)
        for name in std.set(std.map(function(entry) entry[key], entries))
      ]
    ],


  // Converts list of entries to object form using key for the key values
  // Implicitly left-merges entries with the same key
  entriesToObject:: function(key, entries, mergeMethod=self.mergeObjectArray)
    local mergedEntries = self.combineEntriesByKey(key, entries, mergeMethod);
    {
      [entry[key]]: entry
      for entry in mergedEntries
    },


  /* Inverse operator of entriesToObject
  Converts object to list of entries
  Injects keyName as a field to each entry
    local obj = {
      one: {
        name: 'one',
        value: 'xyz',
      },
      two: {
        name: 'two',
        value: 'abc',
      },
    }
    utils.objectToEntries('name', obj) == [
      { name: 'one', value: 'xyz' },
      { name: 'two', value: 'abc' },
    ]
  //*/
  objectToEntries:: function(keyName, object)
    [
      object[key] { [keyName]: key }
      for key in std.objectFields(object)
    ],


  // std.prune wipes all fields with a null value,
  // this non-recursive version only deletes top-level fields that are null
  shallowPrune:: function(object)
    {
      [field]: object[field]
      for field in std.objectFields(object)
      if object[field] != null
    },


  // Forcibly mark specified top-level fields as mergeable in object
  // Useful for integrating data from plain non-jsonnet sources (e.g. YAML/JSON)
  makeMergeableOn:: function(object, fields)
    {
      [field]: (if std.member(fields, field) && ( field in super)
                then (super[field] + object[field])
                else object[field])
      for field in std.objectFields(object)
    },


  // Find index of entry matching conditional in array
  // Returns -1 if none found
  indexOf:: function(conditional, array)
    local results = std.find(true, std.map(conditional, array));
    if std.length(results) == 0 then -1 else results[0],

  // Convert any string to only the first letter being capitalized
  capitalize(word)::
    if std.length(word) == 0 then word
    else std.asciiUpper(std.substr(word, 0, 1)) +
         std.asciiLower(std.substr(word, 1, std.length(word) - 1)),

  // snake_case => Title Case
  snakeToTitle(str)::
    std.join(' ', std.map(self.capitalize, std.split(str, '_'))),
}
