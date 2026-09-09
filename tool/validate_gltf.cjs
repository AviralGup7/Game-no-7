#!/usr/bin/env node
// Optional deep glTF validation using Khronos' official validator.
// npm install --prefix .cache/asset-validation --no-audit --no-fund gltf-validator@2.0.0-dev.3.10
// node tool/validate_gltf.cjs
// No npm dependencies are required by the game or the offline Python checks.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

async function main() {
    let validator;
    try {
        validator = require(path.join(root, '.cache/asset-validation/node_modules/gltf-validator'));
    } catch {
        console.error('Install the optional validator first (command at the top of tool/validate_gltf.cjs).');
        return 1;
    }
    const manifest = JSON.parse(fs.readFileSync(path.join(root, 'assets/manifest.json'), 'utf8'));
    const derived = JSON.parse(fs.readFileSync(path.join(root, 'assets/characters/warden/build_report.json'), 'utf8'));
    const files = [...manifest.files, ...derived.files];
    const approved = new Set(files.map(file => path.resolve(root, file.path)));
    const models = files.filter(file => /\.(glb|gltf)$/.test(file.path));
    let errors = 0;
    let warnings = 0;
    const codes = new Set();
    for (const model of models) {
        const file = path.join(root, model.path);
        const result = await validator.validateBytes(new Uint8Array(fs.readFileSync(file)), {
            uri: path.basename(file),
            externalResourceFunction: async (uri) => {
                const dependency = path.resolve(path.dirname(file), decodeURIComponent(uri));
                if (!approved.has(dependency)) throw new Error(`Unapproved dependency: ${uri}`);
                return new Uint8Array(fs.readFileSync(dependency));
            },
        });
        errors += result.issues.numErrors;
        warnings += result.issues.numWarnings;
        for (const issue of result.issues.messages) {
            if (issue.severity === 0) console.error(model.path, issue.code, issue.message);
            if (issue.severity === 1) codes.add(issue.code);
        }
    }
    console.log(`Khronos glTF: ${models.length} models, ${errors} errors, ${warnings} warnings.`);
    if (warnings) console.log('Warnings:', [...codes].join(', '));
    return errors ? 1 : 0;
}

main().then(code => { process.exitCode = code; }).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
});
