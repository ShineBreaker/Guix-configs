#!/usr/bin/env bash
set -euo pipefail

provider="${1:?provider required}"
config="${CRUSH_CONFIG:-${HOME}/.local/share/crush/crush.json}"

node -e '
const fs = require("fs");
const provider = process.argv[1];
const config = process.argv[2];
const data = JSON.parse(fs.readFileSync(config, "utf8"));
const key = data.providers?.[provider]?.api_key;
if (!key) process.exit(1);
process.stdout.write(key);
' "$provider" "$config"
