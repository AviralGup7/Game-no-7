"""glTF 2.0 / GLB packing and reading for the skill focus recipe (authoring only).

The writer emits the same shape `tool/build_all_environment.py` established for the
modular environment sets — one BIN chunk, one mesh, one PBR material, textures embedded as
PNG buffer views — so nothing about the shipped format is special-cased. The reader exists
so the *verification* render can be taken from the file that actually ships: it decodes the
accessors and the embedded PNGs back into a drawable mesh, which fails loudly if an
accessor, a byte stride or a texture view is off, instead of shipping a model that only the
authoring script can read.

Component types, buffer views and accessor bounds follow the glTF 2.0 spec's alignment
rules: 4-byte component alignment, POSITION bounds mandatory, indices promoted to 16-bit
whenever the vertex count fits (halves the vertex buffer on mobile, which is what the rest
of this project does for its props).
"""
from __future__ import annotations

import base64
import json
import struct

from . import png as png_codec

FLOAT, USHORT, UINT = 5126, 5123, 5125
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963
TYPE_SIZE = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


class GlbWriter:
    """Accumulates buffer views + accessors and writes one GLB."""

    def __init__(self, generator, copyright_text=''):
        self.document = {'asset': {'version': '2.0', 'generator': generator},
                         'bufferViews': [], 'accessors': []}
        if copyright_text:
            self.document['asset']['copyright'] = copyright_text
        self.binary = bytearray()

    # ------------------------------------------------------------------ chunks

    def view(self, blob, target=None):
        """Append one buffer view, keeping the 4-byte accessor alignment the spec demands."""
        while len(self.binary) % 4:
            self.binary.append(0)
        offset = len(self.binary)
        self.binary.extend(blob)
        entry = {'buffer': 0, 'byteOffset': offset, 'byteLength': len(blob)}
        if target:
            entry['target'] = target
        self.document['bufferViews'].append(entry)
        return len(self.document['bufferViews']) - 1

    def packed(self, values, type_name, component, target=None, bounds=False):
        """Write an attribute/element array and return its accessor index."""
        format_char = {FLOAT: 'f', USHORT: 'H', UINT: 'I'}[component]
        width = TYPE_SIZE[type_name]
        count = len(values) // width
        blob = bytearray()
        for index in range(count):
            blob.extend(struct.pack('<' + format_char * width, *values[index * width:(index + 1) * width]))
        view = self.view(blob, target)
        accessor = {'bufferView': view, 'componentType': component, 'count': count, 'type': type_name}
        if bounds:
            low = [min(values[row * width + axis] for row in range(count)) for axis in range(width)]
            high = [max(values[row * width + axis] for row in range(count)) for axis in range(width)]
            accessor['min'] = low
            accessor['max'] = high
        self.document['accessors'].append(accessor)
        return len(self.document['accessors']) - 1

    def texture(self, blob, name):
        """Embed a PNG and return its image index."""
        view = self.view(blob)
        self.document.setdefault('images', []).append({'bufferView': view, 'mimeType': 'image/png', 'name': name})
        self.document.setdefault('samplers', []).append({'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 33071})
        return len(self.document['images']) - 1, len(self.document['samplers']) - 1

    def finish(self):
        self.document['buffers'] = [{'byteLength': len(self.binary)}]
        payload = json.dumps(self.document, separators=(',', ':'), ensure_ascii=True).encode()
        payload += b' ' * (-len(payload) % 4)
        binary = bytes(self.binary) + b'\x00' * (-len(self.binary) % 4)
        total = 28 + len(payload) + len(binary)
        return (struct.pack('<4sII', b'glTF', 2, total) +
                struct.pack('<II', len(payload), 0x4E4F534A) + payload +
                struct.pack('<II', len(binary), 0x004E4942) + binary)


def read(blob):
    """Return (document, binary) for a GLB, or (document, b'') for a .gltf with data URIs."""
    if blob[:4] != b'glTF':
        return json.loads(blob), b''
    _magic, version, length = struct.unpack_from('<4sII', blob, 0)
    if version != 2 or length != len(blob):
        raise ValueError('GLB header is not a complete glTF 2.0 file')
    offset, document, binary = 12, None, b''
    while offset < length:
        size, kind = struct.unpack_from('<II', blob, offset)
        offset += 8
        chunk = blob[offset:offset + size]
        offset += size
        if kind == 0x4E4F534A:
            document = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
    if document is None:
        raise ValueError('GLB has no JSON chunk')
    return document, binary


def accessor_values(document, binary, index):
    """Decode an accessor into a list of tuples (or floats for SCALAR)."""
    entry = document['accessors'][index]
    view = document['bufferViews'][entry['bufferView']]
    start = view.get('byteOffset', 0) + entry.get('byteOffset', 0)
    component = entry['componentType']
    width = TYPE_SIZE[entry['type']]
    format_char = {FLOAT: 'f', USHORT: 'H', UINT: 'I', 5120: 'b', 5121: 'B', 5122: 'h'}[component]
    stride = view.get('byteStride', struct.calcsize('<' + format_char) * width)
    size = struct.calcsize('<' + format_char)
    out = []
    for row in range(entry['count']):
        values = []
        for lane in range(width):
            offset = start + row * stride + lane * size
            values.append(struct.unpack_from('<' + format_char, binary, offset)[0])
        out.append(values[0] if width == 1 else tuple(values))
    return out


def image_blob(document, binary, index, external=None):
    image = document['images'][index]
    if 'uri' not in image:
        view = document['bufferViews'][image['bufferView']]
        start = view.get('byteOffset', 0)
        return binary[start:start + view['byteLength']]
    if image['uri'].startswith('data:'):
        return base64.b64decode(image['uri'].split(',', 1)[1])
    if external is None:
        raise ValueError('external texture without a resolver: ' + image['uri'])
    return external(image['uri'])


def texture_map(document, binary, index, external=None):
    """Decode an embedded texture into (width, height, channels, pixels)."""
    return png_codec.decode(image_blob(document, binary, index, external))
