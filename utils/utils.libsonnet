#!/usr/bin/env jsonnet

// TODO: Add tests for newly added functions

{
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


  // safe field reference with default if field not present
  //   local cfg = { configField: "value" };
  //   ...
  //   utils.optional(config, 'configField', {}) == "value"
  //   utils.optional(config, 'missingField', "none") == "none"
  optional:: function(object, field, default={}, handler=function(v) v)
    if self.contains(object, field)
    then handler(object[field])
    else default,

  // Safe deep field indexing using a list of keys
  //   local cfg = { outer: { inner: { most: "value" } } };
  //   ...
  //   utils.safeGet(cfg, ['outer', 'inner', 'most'], {}) == "value"
  //   utils.safeGet(cfg, ['outer', 'oops', 'most'], {}) == {}
  safeGet:: function(object, fields, default={}, handler=function(v) v)
    if std.length(fields) > 0 && self.contains(object, fields[0])
    then (
      if std.length(fields) == 1 then
        handler(object[fields[0]])
      else
        self.safeGet(object[fields[0]],
                     std.slice(fields, 1, std.length(fields), 1),
                     default)
    )
    else default,


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


  // Converts object to list of entries
  // Injects keyName as a field to each entry
  objectToEntries:: function(keyName, object)
    [
      object[key] { [keyName]: key }
      for key in std.objectFields(object)
    ],


  // Non-recursive version of std.prune(...)
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
}
