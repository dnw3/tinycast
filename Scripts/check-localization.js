#!/usr/bin/env node
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.resolve(__dirname, "..");
const catalogPath = path.join(root, "Tinycast/Resources/Localizable.xcstrings");
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
const failures = [];
function signature(text) {
  return [...text.replace(/%%/g, "").matchAll(/%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.\d+)?(?:hh|ll|h|l|z|t|j)?[@diuoxXfFeEgGaAcCsSp]/g)]
    .map((match) => match[0].replace(/^%\d+\$/, "%")).sort().join("|");
}
function values(unit) {
  if (unit.stringUnit) return [unit.stringUnit.value];
  return Object.values(unit.variations ?? {}).flatMap((variants) => Object.values(variants).flatMap(values));
}
for (const filename of [catalogPath, path.join(root, "Tinycast/Resources/InfoPlist.xcstrings")]) {
  const data = JSON.parse(fs.readFileSync(filename, "utf8"));
  if (data.sourceLanguage !== "en") failures.push(`${filename}: source language must be en`);
  for (const [key, entry] of Object.entries(data.strings)) {
    if (entry.shouldTranslate === false) continue;
    const chinese = entry.localizations?.["zh-Hans"];
    if (!chinese || values(chinese).length === 0) {
      failures.push(`Missing Chinese: ${key}`);
      continue;
    }
    const expected = filename === catalogPath ? signature(key) : "";
    for (const value of values(chinese)) {
      if (!value.trim()) failures.push(`Empty Chinese: ${key}`);
      if (signature(value) !== expected) failures.push(`Format arguments differ: ${key}`);
    }
  }
}
function visit(directory, action) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) visit(full, action);
    else action(full);
  }
}
if (process.argv[2]) {
  visit(path.resolve(process.argv[2]), (file) => {
    if (!file.endsWith(".stringsdata")) return;
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    for (const entry of data.tables?.Localizable ?? []) {
      if (!Object.hasOwn(catalog.strings, entry.key)) failures.push(`Not in catalog: ${entry.key} (${data.source})`);
    }
  });
}
if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log(`✓ localization: ${Object.keys(catalog.strings).length} keys, Chinese and format arguments checked`);
