#!/usr/bin/env bash

git clone https://github.com/yugui/jsonnetunit.git 2>/dev/null || true
for file in $(find test -name '*sonnet'); do
  $file | jq .
done
