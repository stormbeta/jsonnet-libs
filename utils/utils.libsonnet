#!/usr/bin/env jsonnet

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


  contains:: function(collection, ref)
    if std.type(collection) == 'object' then
      std.member(std.objectFields(collection), ref)
    else
      std.member(collection, ref),


  // safe field reference with default if field not present
  optional:: function(object, field, default={})
    if self.contains(object, field)
    then object[field]
    else default,


  // safe deep field navigation
  safeGet:: function(object, fields, default={})
    if std.length(fields) > 0 && self.contains(object, fields[0])
    then (
      if std.length(fields) == 1 then
        self.optional(object, fields[0], default)
      else
        self.safeGet(self.optional(object, fields[0], null),
                     std.slice(fields, 1, std.length(fields), 1),
                     default)
    )
    else default,


  // Given a list of entries, merge-reduce all entries with matching values for the given key
  // Useful for appending overrides to lists of entries, e.g. kuberentes resources
  mergeEntriesByKey:: function(key, entries)
    [
      std.foldl(function(acc, item) acc + item, group, {})
      for group in [
        std.filter(function(entry) entry[key] == name, entries)
        for name in std.set(std.map(function(entry) entry[key], entries))
      ]
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

  // TODO: add entryList/object converters

  // TODO: add entryList merge function from charon-config work
}
