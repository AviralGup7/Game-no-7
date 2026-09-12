"""Software rasterizer used to verify a shipped focus GLB (authoring only).

`docs/agent_skills/03` §5 verifies the environment sets with a compiled C rasterizer fed by
a sidecar `.gltf` plus PPM textures. A focus gets the stricter version of the same idea with
no sidecar and no compiler: this reads the **file that ships** — the GLB's accessors, its
embedded PNGs and its material — and renders that. A wrong accessor stride, a mismatched
texture view, a UV island outside its padding or a flipped tangent hands out a visibly wrong
picture, so "the authoring script produced something" can never again be mistaken for "the
engine can draw it".

The shading is honest rather than decorative: linearised textures, a shadowed key light, a
cool fill, a rim light, hemispheric ambient, GGX-flavoured specular with a metal/dielectric
Fresnel split, normal mapping through the *authored* tangent frame, threshold bloom over the
emissive band, and an ACES-ish filmic curve. Pure Python; nothing but `math` and `struct`.
"""
from __future__ import annotations

import math

from . import glb as glb_codec


def clamp(value, low=0.0, high=1.0):
    return low if value < low else high if value > high else value


def srgb_to_linear(channel):
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def linear_to_srgb(value):
    return 12.92 * value if value <= 0.0031308 else 1.055 * (value ** (1.0 / 2.4)) - 0.055


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def length3(a):
    return math.sqrt(dot(a, a))


def normalize(a, fallback=(0.0, 0.0, 1.0)):
    size = length3(a)
    return (a[0] / size, a[1] / size, a[2] / size) if size > 1e-12 else fallback


def add_scaled(a, b, scale):
    return (a[0] + b[0] * scale, a[1] + b[1] * scale, a[2] + b[2] * scale)


def mix3(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def scaled3(a, factor):
    return (a[0] * factor, a[1] * factor, a[2] * factor)


def light(direction, colour, energy):
    """A directional light. `direction` points from the surface toward the light."""
    return {'direction': normalize(direction), 'colour': colour, 'energy': energy}


# --------------------------------------------------------------------- projection


class Camera:
    """Pinhole camera plus the matching clip matrix, so the floor and the mesh agree."""

    def __init__(self, eye, target, fov, aspect, up=(0.0, 1.0, 0.0), near=0.02, far=24.0):
        self.eye = tuple(eye)
        self.forward = normalize(sub(target, eye), (0.0, 0.0, -1.0))
        self.right = normalize(cross(self.forward, up), (1.0, 0.0, 0.0))
        self.up = cross(self.right, self.forward)
        self.tan_half = math.tan(math.radians(fov) * 0.5)
        self.aspect = aspect
        self.near, self.far = near, far

    def ray(self, ndc_x, ndc_y):
        direction = (self.forward[0] + self.right[0] * ndc_x * self.tan_half * self.aspect + self.up[0] * ndc_y * self.tan_half,
                     self.forward[1] + self.right[1] * ndc_x * self.tan_half * self.aspect + self.up[1] * ndc_y * self.tan_half,
                     self.forward[2] + self.right[2] * ndc_x * self.tan_half * self.aspect + self.up[2] * ndc_y * self.tan_half)
        return normalize(direction)

    def clip(self):
        """Row-major 4x4 model→clip matrix consistent with `ray`."""
        right, up, forward, eye = self.right, self.up, self.forward, self.eye
        view = (right[0], right[1], right[2], -dot(right, eye),
                up[0], up[1], up[2], -dot(up, eye),
                -forward[0], -forward[1], -forward[2], dot(forward, eye),
                0.0, 0.0, 0.0, 1.0)
        tangent = 1.0 / self.tan_half
        projection = (tangent / self.aspect, 0.0, 0.0, 0.0,
                      0.0, tangent, 0.0, 0.0,
                      0.0, 0.0, (self.far + self.near) / (self.near - self.far),
                      2.0 * self.far * self.near / (self.near - self.far),
                      0.0, 0.0, -1.0, 0.0)
        return matrix_multiply(projection, view)


def matrix_multiply(a, b):
    out = [0.0] * 16
    for row in range(4):
        for column in range(4):
            out[row * 4 + column] = (a[row * 4] * b[column] + a[row * 4 + 1] * b[4 + column] +
                                     a[row * 4 + 2] * b[8 + column] + a[row * 4 + 3] * b[12 + column])
    return out


def project_point(matrix, point):
    """Row-major 4x4 times a point, matching `matrix_multiply`'s own convention."""
    x, y, z = point
    return (matrix[0] * x + matrix[1] * y + matrix[2] * z + matrix[3],
            matrix[4] * x + matrix[5] * y + matrix[6] * z + matrix[7],
            matrix[8] * x + matrix[9] * y + matrix[10] * z + matrix[11],
            matrix[12] * x + matrix[13] * y + matrix[14] * z + matrix[15])


# ------------------------------------------------------------------------ scene


class FocusScene:
    """A drawable view of a focus, decoded from the GLB exactly as it ships."""

    def __init__(self, blob):
        document, binary = glb_codec.read(blob)
        primitive = document['meshes'][0]['primitives'][0]
        attributes = primitive['attributes']
        self.positions = glb_codec.accessor_values(document, binary, attributes['POSITION'])
        self.normals = glb_codec.accessor_values(document, binary, attributes['NORMAL'])
        self.tangents = glb_codec.accessor_values(document, binary, attributes['TANGENT'])
        self.uvs = glb_codec.accessor_values(document, binary, attributes['TEXCOORD_0'])
        self.indices = glb_codec.accessor_values(document, binary, primitive['indices'])
        material = document['materials'][primitive.get('material', 0)]
        pbr = material.get('pbrMetallicRoughness', {})
        self.albedo = self._texture(document, binary, pbr['baseColorTexture']['index'])
        self.orm = self._texture(document, binary, pbr['metallicRoughnessTexture']['index'])
        self.normal_map = self._texture(document, binary, material['normalTexture']['index'])
        self.emissive = self._texture(document, binary, material['emissiveTexture']['index'])
        self.emissive_factor = tuple(material.get('emissiveFactor', (1.0, 1.0, 1.0)))
        extensions = material.get('extensions') or {}
        self.emissive_strength = float((extensions.get('KHR_materials_emissive_strength') or {}).get('emissiveStrength', 1.0))
        self.extras = document.get('extras', {})
        low, high = bounds(self.positions)
        self.low, self.high = low, high
        self.centre = tuple((low[axis] + high[axis]) * 0.5 for axis in range(3))
        self.radius = max(1e-4, 0.5 * max(high[0] - low[0], high[1] - low[1], high[2] - low[2]))

    @staticmethod
    def _texture(document, binary, index):
        width, height, channels, pixels = glb_codec.texture_map(document, binary, index)
        return {'width': width, 'height': height, 'channels': channels, 'pixels': pixels,
                'linear': None}

    def sample(self, texture, u, v):
        """Bilinear texel fetch inside one clamped, non-tiled atlas island."""
        width, height, channels, pixels = texture['width'], texture['height'], texture['channels'], texture['pixels']
        x = clamp(u) * width - 0.5
        y = clamp(v) * height - 0.5
        x0, y0 = int(math.floor(x)), int(math.floor(y))
        fx, fy = x - x0, y - y0
        x1, y1 = min(max(x0 + 1, 0), width - 1), min(max(y0 + 1, 0), height - 1)
        x0, y0 = min(max(x0, 0), width - 1), min(max(y0, 0), height - 1)
        row0, row1 = y0 * width, y1 * width
        out = []
        for channel in range(3):
            a = pixels[(row0 + x0) * channels + channel] if channels >= 3 else pixels[row0 + x0]
            b = pixels[(row0 + x1) * channels + channel] if channels >= 3 else pixels[row0 + x1]
            c = pixels[(row1 + x0) * channels + channel] if channels >= 3 else pixels[row1 + x0]
            d = pixels[(row1 + x1) * channels + channel] if channels >= 3 else pixels[row1 + x1]
            top = a + (b - a) * fx
            bottom = c + (d - c) * fx
            out.append((top + (bottom - top) * fy) / 255.0)
        return tuple(out)

    def triangles(self):
        indices = self.indices
        for index in range(0, len(indices) - 2, 3):
            yield indices[index], indices[index + 1], indices[index + 2]


def bounds(points):
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    return low, high


# --------------------------------------------------------------------- shadows


def shadow_map(scene, camera, light_direction, size=192, span=1.6):
    """Ortho depth pass from the key light over the prop's own bounds.

    A hand-placed blob cannot follow a 40-part silhouette; one 192² depth pass can, and it
    costs far less than the beauty pass.
    """
    target = scene.centre
    eye = add_scaled(target, light_direction, span * 2.2)
    view_camera = Camera(eye, target, 2.0 * math.degrees(math.atan(span / (span * 2.2))), 1.0)
    # An orthographic projection along the light is the shadow map's own clip matrix.
    centre = target
    left, right, bottom, top = centre[0] - span, centre[0] + span, centre[1] - span, centre[1] + span
    basis = (view_camera.right, view_camera.up, view_camera.forward)
    depth = [1e30] * (size * size)
    projected = []
    for point in scene.positions:
        local = sub(point, centre)
        u = dot(basis[0], local)
        v = dot(basis[1], local)
        w = dot(basis[2], local)
        projected.append(((u + span) / (2.0 * span), (v + span) / (2.0 * span), w))
    for a, b, c in scene.triangles():
        first, second, third = projected[a], projected[b], projected[c]
        area = (second[0] - first[0]) * (third[1] - first[1]) - (second[1] - first[1]) * (third[0] - first[0])
        if abs(area) < 1e-12:
            continue
        inverse = 1.0 / area
        min_x = max(0, int(min(first[0], second[0], third[0]) * size) - 1)
        max_x = min(size - 1, int(max(first[0], second[0], third[0]) * size) + 1)
        min_y = max(0, int(min(first[1], second[1], third[1]) * size) - 1)
        max_y = min(size - 1, int(max(first[1], second[1], third[1]) * size) + 1)
        for row in range(min_y, max_y + 1):
            base = row * size
            py = (row + 0.5) / size
            for column in range(min_x, max_x + 1):
                px = (column + 0.5) / size
                w0 = ((second[0] - first[0]) * (py - first[1]) - (second[1] - first[1]) * (px - first[0])) * inverse
                w1 = ((third[0] - second[0]) * (py - second[1]) - (third[1] - second[1]) * (px - second[0])) * inverse
                w2 = 1.0 - w0 - w1
                if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
                    continue
                depth_value = first[2] * w2 + second[2] * w0 + third[2] * w1
                index = base + column
                if depth_value < depth[index]:
                    depth[index] = depth_value
    return {'depth': depth, 'size': size, 'basis': basis, 'centre': centre, 'span': span}


def shadow_amount(map_data, point, normal=None, bias=0.010):
    """Percentage-closer bilinear test, with a normal offset in front of it.

    A 192² map over a 3.2 m span resolves about 17 mm per texel, and a depth test without an
    offset lands self-shadow acne on every curved surface of a 0.4 m prop. Pushing the sample
    point a texel and a half along its own normal is the classic fix; PCF then softens the edge
    so the shadow still reads as cast rather than as pasted on.
    """
    size, span, centre = map_data['size'], map_data['span'], map_data['centre']
    basis = map_data['basis']
    depth = map_data['depth']
    if normal is not None:
        point = add_scaled(point, normal, 1.5 * (2.0 * span / size) + bias * span)
    local = sub(point, centre)
    u = (dot(basis[0], local) + span) / (2.0 * span)
    v = (dot(basis[1], local) + span) / (2.0 * span)
    w = dot(basis[2], local)
    if not (0.0 <= u <= 1.0 and 0.0 <= v <= 1.0):
        return 1.0
    x = u * size - 0.5
    y = v * size - 0.5
    x0, y0 = int(math.floor(x)), int(math.floor(y))
    fx, fy = x - x0, y - y0
    total = 0.0
    for row in (0, 1, 2):
        for column in (0, 1, 2):
            sample_x = clamp(x0 + column - 1, 0, size - 1)
            sample_y = clamp(y0 + row - 1, 0, size - 1)
            stored = depth[sample_y * size + sample_x]
            lit = 1.0 if stored > w - bias * span else 0.0
            total += lit / 9.0
    return 0.22 + 0.78 * total


# --------------------------------------------------------------------- renderer


def render(scene, width=512, height=512, eye=None, fov=26.0, key=None, fill=None, rim=None,
           sky=None, ground=None, floor=True, samples=2, background=(0.017, 0.026, 0.038),
           bloom=0.85, exposure=1.0):
    """Shade one focus on a studio floor; returns {rgb, alpha, width, height}."""
    centre = scene.centre
    # Frame the whole silhouette with a margin: a cropped hero shot hides the very detail
    # (rams, strakes, sockets) the render exists to verify.
    reach = max(scene.high[0] - scene.low[0], scene.high[1] - scene.low[1], scene.high[2] - scene.low[2])
    distance = max(1.45, reach * 0.5 / math.tan(math.radians(fov) * 0.5) * 1.42)
    eye = eye or (centre[0] + distance * 0.60, centre[1] + distance * 0.50, centre[2] + distance * 0.62)
    camera = Camera(eye, (centre[0], centre[1] * 0.94, centre[2]), fov, width / height)
    key = key or light((-0.58, 0.74, 0.36), (1.0, 0.94, 0.85), 0.66)
    fill = fill or light((0.72, 0.30, -0.52), (0.40, 0.53, 0.76), 0.17)
    rim = rim or light((0.06, 0.42, -0.92), (0.52, 0.76, 1.0), 0.34)
    sky = sky or (0.20, 0.25, 0.33)
    ground = ground or (0.062, 0.058, 0.054)
    clip = camera.clip()
    shadows = shadow_map(scene, camera, key['direction'])

    scale = max(1, int(samples))
    buffer_width, buffer_height = width * scale, height * scale
    count = buffer_width * buffer_height
    colour = [0.0] * (count * 3)
    emission = [0.0] * (count * 3)
    depth = [1e30] * count
    coverage = bytearray(count)

    floor_y = scene.low[1] - 0.0006
    if floor:
        _floor_pass(camera, colour, buffer_width, buffer_height, floor_y, scene, key, shadows,
                    sky, ground, background)
    _geometry_pass(scene, clip, camera, colour, emission, depth, coverage, buffer_width, buffer_height,
                   key, fill, rim, sky, ground, shadows)

    return _composite(colour, emission, coverage, buffer_width, buffer_height, width, height,
                      scale, bloom, exposure, background)


def _floor_pass(camera, colour, width, height, floor_y, scene, key, shadows, sky, ground, background):
    eye = camera.eye
    for row in range(height):
        ndc_y = 1.0 - 2.0 * (row + 0.5) / height
        base = row * width
        for column in range(width):
            ndc_x = 2.0 * (column + 0.5) / width - 1.0
            ray = camera.ray(ndc_x, ndc_y)
            index = (base + column) * 3
            if ray[1] > -1e-4:
                horizon = mix3(background, scaled3(background, 2.6), clamp(0.5 + 0.5 * ray[1]))
                colour[index], colour[index + 1], colour[index + 2] = horizon
                continue
            distance = (floor_y - eye[1]) / ray[1]
            point = (eye[0] + ray[0] * distance, floor_y, eye[2] + ray[2] * distance)
            radius = math.hypot(point[0] - scene.centre[0], point[2] - scene.centre[2])
            light_amount = shadow_amount(shadows, point, (0.0, 1.0, 0.0), 0.012)
            falloff = clamp(1.0 - radius / 4.2) ** 1.5
            normal = (0.0, 1.0, 0.0)
            diffuse = max(0.0, dot(normal, key['direction'])) * light_amount
            albedo = (0.085, 0.095, 0.115)
            value = scaled3(albedo, 0.06 + 1.35 * diffuse * key['energy'] * 0.32)
            # Both terms ride the same falloff so the plate fades into the background instead
            # of ending on a visible ring at the edge of the light.
            value = add_scaled(value, mix3(ground, sky, 0.75), (0.9 * falloff + 0.25) * falloff)
            # A soft contact gradient under the prop: the shadow map handles the shape,
            # this only stops the base from looking like it is floating on air.
            contact = clamp(1.0 - radius / (scene.radius * 1.9))
            value = scaled3(value, 1.0 - 0.55 * contact * (1.0 - light_amount))
            fog = clamp(distance / 5.5) ** 0.85
            colour[index] = _mix(value[0], background[0], fog)
            colour[index + 1] = _mix(value[1], background[1], fog)
            colour[index + 2] = _mix(value[2], background[2], fog)


def _mix(a, b, t):
    return a + (b - a) * t


def _geometry_pass(scene, clip, camera, colour, emission, depth, coverage, width, height,
                   key, fill, rim, sky, ground, shadows):
    positions, normals, tangents, uvs = scene.positions, scene.normals, scene.tangents, scene.uvs
    for a, b, c in scene.triangles():
        screen = []
        for index in (a, b, c):
            x, y, z, w = project_point(clip, positions[index])
            if w <= 1e-7:
                screen = None
                break
            # The perspective divide is what makes this agree with `Camera.ray`: without it the
            # mesh lands somewhere else than the floor and background the camera rays describe.
            x, y = x / w, y / w
            screen.append(((x * 0.5 + 0.5) * width, (1.0 - (y * 0.5 + 0.5)) * height, w))
        if screen is None:
            continue
        min_x = max(0, int(min(p[0] for p in screen)))
        max_x = min(width - 1, int(max(p[0] for p in screen)) + 1)
        min_y = max(0, int(min(p[1] for p in screen)))
        max_y = min(height - 1, int(max(p[1] for p in screen)) + 1)
        if min_x > max_x or min_y > max_y:
            continue
        ax, ay, _ = screen[0]
        bx, by, _ = screen[1]
        cx, cy, _ = screen[2]
        # glTF front faces are CCW as seen from the camera. This projection turns that into a
        # negative screen-space area because the pixel row axis runs downward, so the faces with
        # a positive area are the ones facing away and they are the ones dropped.
        area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        if area < 0.0:
            continue
        if abs(area) < 1e-9:
            continue
        inverse = 1.0 / area
        for row in range(min_y, max_y + 1):
            py = row + 0.5
            line = row * width
            for column in range(min_x, max_x + 1):
                px = column + 0.5
                w1 = ((bx - ax) * (py - ay) - (by - ay) * (px - ax)) * inverse
                w2 = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) * inverse
                w0 = 1.0 - w1 - w2
                if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
                    continue
                view_depth = w0 * screen[0][2] + w1 * screen[1][2] + w2 * screen[2][2]
                slot = line + column
                if view_depth >= depth[slot]:
                    continue
                depth[slot] = view_depth
                coverage[slot] = 255
                weight = w0 / screen[0][2] + w1 / screen[1][2] + w2 / screen[2][2]
                if weight <= 1e-12:
                    continue
                mu0 = (w0 / screen[0][2]) / weight
                mu1 = (w1 / screen[1][2]) / weight
                mu2 = 1.0 - mu0 - mu1
                point = tuple(mu0 * positions[a][axis] + mu1 * positions[b][axis] + mu2 * positions[c][axis]
                              for axis in range(3))
                normal = normalize(tuple(mu0 * normals[a][axis] + mu1 * normals[b][axis] + mu2 * normals[c][axis]
                                         for axis in range(3)))
                tangent = normalize(tuple(mu0 * tangents[a][axis] + mu1 * tangents[b][axis] + mu2 * tangents[c][axis]
                                          for axis in range(3)))
                handed = mu0 * tangents[a][3] + mu1 * tangents[b][3] + mu2 * tangents[c][3]
                u = mu0 * uvs[a][0] + mu1 * uvs[b][0] + mu2 * uvs[c][0]
                v = mu0 * uvs[a][1] + mu1 * uvs[b][1] + mu2 * uvs[c][1]
                shade(scene, point, normal, tangent, handed, u, v, camera.eye, colour, emission,
                      slot * 3, key, fill, rim, sky, ground, shadows)


def shade(scene, point, normal, tangent, handed, u, v, eye, colour, emission, index,
          key, fill, rim, sky, ground, shadows):
    albedo_map = scene.sample(scene.albedo, u, v)
    albedo = tuple(srgb_to_linear(channel) for channel in albedo_map)
    occlusion, roughness, metallic = scene.sample(scene.orm, u, v)
    roughness = max(0.045, roughness)
    bump = tuple(channel * 2.0 - 1.0 for channel in scene.sample(scene.normal_map, u, v))
    bitangent = normalize(cross(normal, tangent), (1.0, 0.0, 0.0))
    if handed < 0.0:
        bitangent = scaled3(bitangent, -1.0)
    surface = normalize((tangent[0] * bump[0] + bitangent[0] * bump[1] + normal[0] * bump[2],
                         tangent[1] * bump[0] + bitangent[1] * bump[1] + normal[1] * bump[2],
                         tangent[2] * bump[0] + bitangent[2] * bump[1] + normal[2] * bump[2]),
                        normal)
    view = normalize(sub(eye, point))
    f_zero = (0.04 + (albedo[0] - 0.04) * metallic, 0.04 + (albedo[1] - 0.04) * metallic,
              0.04 + (albedo[2] - 0.04) * metallic)
    exponent = max(2.0, 2.0 / (roughness * roughness))
    normalisation = (exponent + 8.0) / (8.0 * math.pi)
    to_viewer = max(dot(surface, view), 0.10)
    # A Blinn lobe scaled by Smith-style visibility, so a broad lobe on brushed alloy cannot
    # add up to a white sheet: the highlight is what sells the material, not the fill light.
    visibility = min(1.0 / (4.0 * to_viewer), 2.4) * (1.0 - roughness * 0.55)
    result = [0.0, 0.0, 0.0]
    for source, shadowed in ((key, True), (fill, False), (rim, False)):
        direction = source['direction']
        cosine = dot(surface, direction)
        if cosine <= 0.0:
            continue
        halfway = normalize(add_scaled(direction, view, 1.0))
        facing = max(0.0, dot(surface, halfway))
        to_eye = max(0.0, dot(halfway, view))
        fresnel = 0.012 + 0.988 * (1.0 - to_eye) ** 5.0
        glint = normalisation * (facing ** exponent) * visibility
        # A turntable preview is lit like a product shot: the softboxes give form, and the
        # prop's own shadow map is kept for the floor only. Self-shadowing a 0.4 m prop from
        # a 192² map over a 3.2 m span lands in a resolution where every chamfer spoke turns
        # into a streak, and a streak in a verification render reads as a modelling error.
        attenuation = shadow_amount(shadows, point, surface) if (shadowed and shadows) else 1.0
        energy = source['energy'] * cosine * attenuation
        diffuse = (1.0 - metallic * 0.92) * (1.0 - fresnel * 0.55)
        for channel in range(3):
            specular = (f_zero[channel] + (1.0 - f_zero[channel]) * fresnel) * glint
            result[channel] += (albedo[channel] * diffuse + specular) * energy * source['colour'][channel]
    hemisphere = 0.5 + 0.5 * surface[1]
    ambient = mix3(ground, sky, hemisphere)
    for channel in range(3):
        result[channel] += albedo[channel] * ambient[channel] * (0.35 + 0.65 * occlusion)
    # Metals have no diffuse term to save them, so they need the environment back: the same
    # hemisphere the ambient uses, sampled along the reflected ray and scaled by (1 - roughness).
    mirrored = add_scaled(surface, view, -2.0 * dot(surface, view))
    reflection = mix3(ground, sky, 0.5 + 0.5 * mirrored[1])
    polish = (1.0 - roughness) ** 1.4 * (0.05 + 0.95 * metallic) * occlusion
    for channel in range(3):
        result[channel] += reflection[channel] * polish * 0.55 + albedo[channel] * polish * 0.18
    glow_map = scene.sample(scene.emissive, u, v)
    glow = tuple(srgb_to_linear(glow_map[channel]) * scene.emissive_factor[channel] * scene.emissive_strength
                 for channel in range(3))
    for channel in range(3):
        result[channel] += glow[channel]
        colour[index + channel] = result[channel]
        emission[index + channel] = glow[channel]


def _composite(colour, emission, coverage, buffer_width, buffer_height, width, height, scale,
               bloom, exposure, background):
    """Bloom the emissive band, tone map, gamma encode, then box-down to the output size."""
    light_buffer = [0.0] * (buffer_width * buffer_height * 3)
    for row in range(buffer_height):
        source = row * buffer_width * 3
        for column in range(buffer_width):
            slot = source + column * 3
            for channel in range(3):
                light_buffer[slot + channel] = colour[slot + channel]
    if bloom > 0.0:
        bright = [0.0] * (buffer_width * buffer_height * 3)
        for row in range(buffer_height):
            source = row * buffer_width * 3
            for column in range(buffer_width):
                slot = source + column * 3
                for channel in range(3):
                    value = emission[slot + channel]
                    bright[slot + channel] = value * clamp((value - 0.30) / 0.70)
        small_width, small_height = max(2, buffer_width // 4), max(2, buffer_height // 4)
        downsampled = _box_blur(_downsample(bright, buffer_width, buffer_height, small_width, small_height),
                                small_width, small_height, radius=2, passes=3)
        for row in range(buffer_height):
            source_row = min(row // 4, small_height - 1)
            source = row * buffer_width * 3
            for column in range(buffer_width):
                target = source + column * 3
                small_column = min(column // 4, small_width - 1)
                offset = (source_row * small_width + small_column) * 3
                for channel in range(3):
                    light_buffer[target + channel] += bloom * downsampled[offset + channel]
    rgb = bytearray(width * height * 3)
    alpha = bytearray(width * height)
    for row in range(height):
        for column in range(width):
            total = [0.0, 0.0, 0.0]
            covered = 0
            for sub_row in range(scale):
                for sub_column in range(scale):
                    slot = ((row * scale + sub_row) * buffer_width + column * scale + sub_column)
                    covered += coverage[slot]
                    source = slot * 3
                    for channel in range(3):
                        total[channel] += tone_map(light_buffer[source + channel] * exposure)
            divisor = scale * scale
            offset = (row * width + column) * 3
            for channel in range(3):
                value = clamp(total[channel] / divisor)
                rgb[offset + channel] = int(clamp(linear_to_srgb(value)) * 255.0 + 0.5)
            alpha[row * width + column] = min(255, int(255.0 * covered / divisor) +
                                              (0 if covered else 0))
            if not covered:
                for channel in range(3):
                    rgb[offset + channel] = int(clamp(linear_to_srgb(background[channel])) * 255.0 + 0.5)
    return {'width': width, 'height': height, 'rgb': bytes(rgb), 'alpha': bytes(alpha),
            'background': background}


def tone_map(value):
    """ACES filmic approximation, enough to keep hot emissive from clipping to white."""
    value = max(0.0, value)
    numerator = value * (2.51 * value + 0.03)
    denominator = value * (2.43 * value + 0.59) + 0.14
    return numerator / denominator if denominator > 1e-9 else 0.0


def _downsample(source, width, height, target_width, target_height):
    out = [0.0] * (target_width * target_height * 3)
    block = max(1, width // target_width)
    for row in range(target_height):
        for column in range(target_width):
            total = [0.0, 0.0, 0.0]
            for sub_row in range(block):
                source_row = min(row * block + sub_row, height - 1)
                for sub_column in range(block):
                    source_column = min(column * block + sub_column, width - 1)
                    offset = (source_row * width + source_column) * 3
                    for channel in range(3):
                        total[channel] += source[offset + channel]
            offset = (row * target_width + column) * 3
            divisor = float(block * block)
            for channel in range(3):
                out[offset + channel] = total[channel] / divisor
    return out


def _box_blur(source, width, height, radius=2, passes=1):
    window = 2 * radius + 1
    current = source
    for _ in range(passes):
        result = [0.0] * len(current)
        for row in range(height):
            for column in range(width):
                total = [0.0, 0.0, 0.0]
                for offset in range(-radius, radius + 1):
                    sample = min(max(column + offset, 0), width - 1)
                    slot = (row * width + sample) * 3
                    for channel in range(3):
                        total[channel] += current[slot + channel]
                slot = (row * width + column) * 3
                for channel in range(3):
                    result[slot + channel] = total[channel] / window
        current = result
        for column in range(width):
            for row in range(height):
                total = [0.0, 0.0, 0.0]
                for offset in range(-radius, radius + 1):
                    sample = min(max(row + offset, 0), height - 1)
                    slot = (sample * width + column) * 3
                    for channel in range(3):
                        total[channel] += current[slot + channel]
                slot = (row * width + column) * 3
                for channel in range(3):
                    result[slot + channel] = total[channel] / window
        current = result
    return current
