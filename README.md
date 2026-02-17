# Jsonnet Libraries

## `testsuite.libsonnet`

Unit testing framework for jsonnet, utilizes `spec.libsonnet` for significantly more friendly and
powerful matching patterns compared to existing libraries

Used by the other libraries in this repo for testing

## `spec.libsonnet`

Spec and type checking library. Has its own [README.md](spec/README.md)

## `utils.libsonnet`

Collection of misc utility functions for navigating and managing json data structures

**Notable:**

* `safeGet`: allows safely digging into deeply nested objects by passing it a list of keys, indices,
  or even a {key: value} pair object for lists of entry objects

* `objectToEntries` / `entriesToObject`: allows easy conversion between object-type maps and lists
  of entries like those favored by k8s' config entities. Also makes it much easier to flatten/merge
  entries lists cleanly
