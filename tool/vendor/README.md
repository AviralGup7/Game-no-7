# Art-review viewer dependencies

The dev-only viewers use the vendored three.js files, not a CDN or a game runtime
network dependency. `tool/` is excluded from the Android export.

The missing `three.core.js` import of the existing `three.module.js` was restored
from the **same** upstream revision (three.js r185):

- Repository: https://github.com/mrdoob/three.js
- Revision: `2431a09f46f34c560bc8e44b33be0e567723d5b9`
- Source path: `build/three.core.js`
- SHA-256: `3718df126d69c125362a03340913204470d8c50238605150e57f808840fb7759`
- Licence: MIT, Three.js Authors. Notice: `ASSET_LICENSES/threejs-pbr.txt`.

The already-vendored `three.module.js` was compared byte-for-byte to that revision
(SHA-256 `bbf5ed13fe4373f5bd38b14ea8e62e9f157327da5638edc6d3863e08b167c9c7`).
`test_hero_fidelity.py` checks that relative imports throughout this vendor module
graph exist so a missing core/helper cannot leave the viewer permanently loading.
