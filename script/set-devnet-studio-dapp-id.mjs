#!/usr/bin/env bun
import fs from "node:fs";
import path from "node:path";

function usage() {
  console.error(
    "Usage: bun script/set-devnet-studio-dapp-id.mjs --file <path> --studio-dapp-id <uint>"
  );
}

function parseArgs(argv) {
  const out = { file: "", studioDappId: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--file") {
      out.file = argv[i + 1] ?? "";
      i += 1;
      continue;
    }
    if (arg === "--studio-dapp-id") {
      out.studioDappId = argv[i + 1] ?? "";
      i += 1;
      continue;
    }
  }
  return out;
}

const { file, studioDappId } = parseArgs(process.argv.slice(2));
if (!file || !studioDappId) {
  usage();
  process.exit(1);
}
if (!/^\d+$/.test(studioDappId)) {
  throw new Error(`invalid studio dapp id: ${studioDappId}`);
}

const filePath = path.resolve(file);
const raw = fs.readFileSync(filePath, "utf-8");
const parsed = JSON.parse(raw);
parsed.studioDappId = Number(studioDappId);
fs.writeFileSync(filePath, `${JSON.stringify(parsed, null, 2)}\n`);
console.log(`Updated ${filePath} with studioDappId=${parsed.studioDappId}`);
