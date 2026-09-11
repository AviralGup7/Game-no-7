#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

#define WIDTH 1920
#define HEIGHT 1080

typedef struct { float x, y, z; } Vec3;
typedef struct { float u, v; } Vec2;
typedef struct { uint8_t r, g, b; } Pixel;

typedef struct {
    Vec3 pos;
    Vec3 normal;
    Vec2 uv;
} Vertex;

typedef struct {
    int v0, v1, v2;
} Triangle;

typedef struct {
    int num_vertices;
    Vertex *vertices;
    int num_triangles;
    Triangle *triangles;
} Mesh;

typedef struct {
    int width, height;
    uint8_t *data;
} Texture;

static inline Vec3 vec3(float x, float y, float z) { return (Vec3){x, y, z}; }
static inline Vec3 vec3_add(Vec3 a, Vec3 b) { return (Vec3){a.x + b.x, a.y + b.y, a.z + b.z}; }
static inline Vec3 vec3_sub(Vec3 a, Vec3 b) { return (Vec3){a.x - b.x, a.y - b.y, a.z - b.z}; }
static inline Vec3 vec3_scale(Vec3 a, float s) { return (Vec3){a.x * s, a.y * s, a.z * s}; }
static inline float vec3_dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline Vec3 vec3_cross(Vec3 a, Vec3 b) {
    return (Vec3){ a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x };
}
static inline Vec3 vec3_norm(Vec3 a) {
    float l = sqrtf(vec3_dot(a, a));
    return (l > 1e-6f) ? vec3_scale(a, 1.0f / l) : vec3(0, 0, 1);
}

typedef struct { float m[4][4]; } Mat4;

static Mat4 mat4_ident() {
    Mat4 res = {0};
    res.m[0][0] = 1; res.m[1][1] = 1; res.m[2][2] = 1; res.m[3][3] = 1;
    return res;
}

static Mat4 mat4_translate(float tx, float ty, float tz) {
    Mat4 res = mat4_ident();
    res.m[0][3] = tx; res.m[1][3] = ty; res.m[2][3] = tz;
    return res;
}

static Mat4 mat4_scale(float sx, float sy, float sz) {
    Mat4 res = mat4_ident();
    res.m[0][0] = sx; res.m[1][1] = sy; res.m[2][2] = sz;
    return res;
}

static Mat4 mat4_mul(Mat4 a, Mat4 b) {
    Mat4 res = {0};
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            for (int k = 0; k < 4; k++) {
                res.m[r][c] += a.m[r][k] * b.m[k][c];
            }
        }
    }
    return res;
}

static Mat4 mat4_lookat(Vec3 eye, Vec3 target, Vec3 up) {
    Vec3 f = vec3_norm(vec3_sub(target, eye));
    Vec3 r = vec3_norm(vec3_cross(f, up));
    Vec3 u = vec3_cross(r, f);
    Mat4 res = {0};
    res.m[0][0] = r.x; res.m[0][1] = r.y; res.m[0][2] = r.z; res.m[0][3] = -vec3_dot(r, eye);
    res.m[1][0] = u.x; res.m[1][1] = u.y; res.m[1][2] = u.z; res.m[1][3] = -vec3_dot(u, eye);
    res.m[2][0] = -f.x; res.m[2][1] = -f.y; res.m[2][2] = -f.z; res.m[2][3] = vec3_dot(f, eye);
    res.m[3][3] = 1.0f;
    return res;
}

static Mat4 mat4_perspective(float fovy, float aspect, float znear, float zfar) {
    float tanHalf = tanf(fovy * 0.5f);
    Mat4 res = {0};
    res.m[0][0] = 1.0f / (aspect * tanHalf);
    res.m[1][1] = 1.0f / tanHalf;
    res.m[2][2] = -(zfar + znear) / (zfar - znear);
    res.m[2][3] = -(2.0f * zfar * znear) / (zfar - znear);
    res.m[3][2] = -1.0f;
    return res;
}

static Texture load_ppm(const char *filename) {
    Texture tex = {0, 0, NULL};
    FILE *f = fopen(filename, "rb");
    if (!f) return tex;
    char header[64];
    if (fscanf(f, "%63s", header) != 1 || strcmp(header, "P6") != 0) {
        fclose(f);
        return tex;
    }
    int maxval;
    if (fscanf(f, "%d %d %d", &tex.width, &tex.height, &maxval) != 3) {
        fclose(f);
        return tex;
    }
    fgetc(f);
    tex.data = (uint8_t*)malloc(tex.width * tex.height * 3);
    fread(tex.data, 1, tex.width * tex.height * 3, f);
    fclose(f);
    return tex;
}

static Vec3 sample_texture(const Texture *tex, float u, float v) {
    if (!tex || !tex->data) return vec3(0.7f, 0.7f, 0.7f);
    u = u - floorf(u);
    v = v - floorf(v);
    float fx = u * (tex->width - 1);
    float fy = v * (tex->height - 1);
    int x0 = (int)fx; int y0 = (int)fy;
    int x1 = (x0 + 1 < tex->width) ? x0 + 1 : x0;
    int y1 = (y0 + 1 < tex->height) ? y0 + 1 : y0;
    float wx = fx - x0; float wy = fy - y0;

    int idx00 = (y0 * tex->width + x0) * 3;
    int idx10 = (y0 * tex->width + x1) * 3;
    int idx01 = (y1 * tex->width + x0) * 3;
    int idx11 = (y1 * tex->width + x1) * 3;

    float r = ((tex->data[idx00] * (1-wx) + tex->data[idx10] * wx)*(1-wy) + (tex->data[idx01] * (1-wx) + tex->data[idx11] * wx)*wy) / 255.0f;
    float g = ((tex->data[idx00+1] * (1-wx) + tex->data[idx10+1] * wx)*(1-wy) + (tex->data[idx01+1] * (1-wx) + tex->data[idx10+1] * wx)*wy) / 255.0f;
    float b = ((tex->data[idx00+2] * (1-wx) + tex->data[idx10+2] * wx)*(1-wy) + (tex->data[idx01+2] * (1-wx) + tex->data[idx11+2] * wx)*wy) / 255.0f;
    return vec3(r, g, b);
}

typedef struct {
    Vec3 pos;
    Vec3 normal;
    Vec2 uv;
    float screen_x, screen_y, screen_z, inv_w;
} ShadedVertex;

static ShadedVertex transform_vertex(Vertex v, Mat4 model, Mat4 view, Mat4 proj) {
    ShadedVertex out;
    out.pos = v.pos;
    out.normal = v.normal;
    out.uv = v.uv;

    Vec3 world_p = {
        model.m[0][0]*v.pos.x + model.m[0][1]*v.pos.y + model.m[0][2]*v.pos.z + model.m[0][3],
        model.m[1][0]*v.pos.x + model.m[1][1]*v.pos.y + model.m[1][2]*v.pos.z + model.m[1][3],
        model.m[2][0]*v.pos.x + model.m[2][1]*v.pos.y + model.m[2][2]*v.pos.z + model.m[2][3]
    };

    float vx = view.m[0][0]*world_p.x + view.m[0][1]*world_p.y + view.m[0][2]*world_p.z + view.m[0][3];
    float vy = view.m[1][0]*world_p.x + view.m[1][1]*world_p.y + view.m[1][2]*world_p.z + view.m[1][3];
    float vz = view.m[2][0]*world_p.x + view.m[2][1]*world_p.y + view.m[2][2]*world_p.z + view.m[2][3];

    float cx = proj.m[0][0]*vx + proj.m[0][1]*vy + proj.m[0][2]*vz + proj.m[0][3];
    float cy = proj.m[1][0]*vx + proj.m[1][1]*vy + proj.m[1][2]*vz + proj.m[1][3];
    float cz = proj.m[2][0]*vx + proj.m[2][1]*vy + proj.m[2][2]*vz + proj.m[2][3];
    float cw = proj.m[3][0]*vx + proj.m[3][1]*vy + proj.m[3][2]*vz + proj.m[3][3];

    out.inv_w = 1.0f / (cw != 0.0f ? cw : 1e-6f);
    out.screen_x = (cx * out.inv_w * 0.5f + 0.5f);
    out.screen_y = (1.0f - (cy * out.inv_w * 0.5f + 0.5f));
    out.screen_z = cz * out.inv_w;
    return out;
}

static void rasterize_triangle(ShadedVertex v0, ShadedVertex v1, ShadedVertex v2,
                               const Texture *tex,
                               Pixel *fb, float *zb, int fb_w, int fb_h,
                               int vx, int vy, int vw, int vh,
                               Vec3 emissive_tint) {
    if (v0.screen_z < -1.0f || v0.screen_z > 1.0f ||
        v1.screen_z < -1.0f || v1.screen_z > 1.0f ||
        v2.screen_z < -1.0f || v2.screen_z > 1.0f) return;

    float p0x = vx + v0.screen_x * vw;
    float p0y = vy + v0.screen_y * vh;
    float p1x = vx + v1.screen_x * vw;
    float p1y = vy + v1.screen_y * vh;
    float p2x = vx + v2.screen_x * vw;
    float p2y = vy + v2.screen_y * vh;

    float min_x = fmaxf((float)vx, fminf(p0x, fminf(p1x, p2x)));
    float max_x = fminf((float)(vx + vw - 1), fmaxf(p0x, fmaxf(p1x, p2x)));
    float min_y = fmaxf((float)vy, fminf(p0y, fminf(p1y, p2y)));
    float max_y = fminf((float)(vy + vh - 1), fmaxf(p0y, fmaxf(p1y, p2y)));

    if (min_x > max_x || min_y > max_y) return;

    float area = (p1x - p0x) * (p2y - p0y) - (p1y - p0y) * (p2x - p0x);
    if (fabsf(area) < 1e-5f) return;
    float inv_area = 1.0f / area;

    Vec2 uv0_w = { v0.uv.u * v0.inv_w, v0.uv.v * v0.inv_w };
    Vec2 uv1_w = { v1.uv.u * v1.inv_w, v1.uv.v * v1.inv_w };
    Vec2 uv2_w = { v2.uv.u * v2.inv_w, v2.uv.v * v2.inv_w };

    Vec3 norm0_w = vec3_scale(v0.normal, v0.inv_w);
    Vec3 norm1_w = vec3_scale(v1.normal, v1.inv_w);
    Vec3 norm2_w = vec3_scale(v2.normal, v2.inv_w);

    Vec3 key_light = vec3_norm(vec3(0.65f, 0.85f, 0.70f));
    Vec3 fill_light = vec3_norm(vec3(-0.75f, 0.35f, 0.45f));
    Vec3 rim_light = vec3_norm(vec3(0.0f, -0.6f, -0.8f));

    for (int y = (int)min_y; y <= (int)max_y; y++) {
        for (int x = (int)min_x; x <= (int)max_x; x++) {
            float px = x + 0.5f;
            float py = y + 0.5f;

            float w0 = ((p1x - px) * (p2y - py) - (p1y - py) * (p2x - px)) * inv_area;
            float w1 = ((p2x - px) * (p0y - py) - (p2y - py) * (p0x - px)) * inv_area;
            float w2 = 1.0f - w0 - w1;

            if (w0 >= 0.0f && w1 >= 0.0f && w2 >= 0.0f) {
                float z = w0 * v0.screen_z + w1 * v1.screen_z + w2 * v2.screen_z;
                int fb_idx = y * fb_w + x;
                if (z < zb[fb_idx]) {
                    zb[fb_idx] = z;
                    float w = 1.0f / (w0 * v0.inv_w + w1 * v1.inv_w + w2 * v2.inv_w);
                    float u = (w0 * uv0_w.u + w1 * uv1_w.u + w2 * uv2_w.u) * w;
                    float v = (w0 * uv0_w.v + w1 * uv1_w.v + w2 * uv2_w.v) * w;

                    Vec3 N = vec3_norm(vec3_scale(vec3_add(vec3_add(vec3_scale(norm0_w, w0), vec3_scale(norm1_w, w1)), vec3_scale(norm2_w, w2)), w));
                    Vec3 tex_col = sample_texture(tex, u, v);

                    float diff = fmaxf(0.0f, vec3_dot(N, key_light)) * 0.82f +
                                 fmaxf(0.0f, vec3_dot(N, fill_light)) * 0.35f +
                                 fmaxf(0.0f, vec3_dot(N, rim_light)) * 0.20f + 0.30f;

                    // Specular highlight
                    Vec3 view_dir = vec3(0, 0, 1);
                    Vec3 half_v = vec3_norm(vec3_add(key_light, view_dir));
                    float spec = powf(fmaxf(0.0f, vec3_dot(N, half_v)), 32.0f) * 0.40f;

                    float em_lum = fmaxf(0.0f, (tex_col.x + tex_col.y + tex_col.z) / 3.0f - 0.65f) * 2.5f;

                    float r = fminf(1.0f, tex_col.x * diff + spec + em_lum * emissive_tint.x);
                    float g = fminf(1.0f, tex_col.y * diff + spec + em_lum * emissive_tint.y);
                    float b = fminf(1.0f, tex_col.z * diff + spec + em_lum * emissive_tint.z);

                    fb[fb_idx] = (Pixel){ (uint8_t)(r * 255.0f), (uint8_t)(g * 255.0f), (uint8_t)(b * 255.0f) };
                }
            }
        }
    }
}

static void draw_border_box(Pixel *fb, int x0, int y0, int w, int h, Pixel border, Pixel bg) {
    for (int y = y0; y < y0 + h && y < HEIGHT; y++) {
        for (int x = x0; x < x0 + w && x < WIDTH; x++) {
            if (x == x0 || x == x0 + w - 1 || y == y0 || y == y0 + h - 1) {
                fb[y * WIDTH + x] = border;
            } else if (bg.r != 0 || bg.g != 0 || bg.b != 0) {
                fb[y * WIDTH + x] = bg;
            }
        }
    }
}

static Mesh load_json_mesh(const char *json_path) {
    Mesh mesh = {0};
    FILE *f = fopen(json_path, "rb");
    if (!f) return mesh;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = (char *)malloc(sz + 1);
    fread(buf, 1, sz, f);
    buf[sz] = 0;
    fclose(f);

    int num_v = 0;
    char *p = strstr(buf, "\"verts_count\":");
    if (p) sscanf(p, "\"verts_count\": %d", &num_v);
    if (num_v <= 0) num_v = 11857;

    Vertex *verts = (Vertex *)malloc(num_v * sizeof(Vertex));

    p = strstr(buf, "\"verts\":");
    p = strchr(p, '['); p++;
    for (int i = 0; i < num_v; i++) {
        p = strchr(p, '[');
        if (!p) break;
        float x, y, z;
        sscanf(p + 1, "%f, %f, %f", &x, &y, &z);
        verts[i].pos = vec3(x, y, z);
        verts[i].normal = vec3(0, 0, 0);
        verts[i].uv = (Vec2){0, 0};
        p = strchr(p, ']'); p++;
    }

    int num_f = 0;
    p = strstr(buf, "\"faces_count\":");
    if (p) sscanf(p, "\"faces_count\": %d", &num_f);
    if (num_f <= 0) num_f = 11235;

    Triangle *tris = (Triangle *)malloc(num_f * 2 * sizeof(Triangle));
    int tri_cnt = 0;

    p = strstr(buf, "\"faces\":");
    p = strchr(p, '['); p++;
    for (int i = 0; i < num_f; i++) {
        p = strchr(p, '[');
        if (!p) break;
        int v0, v1, v2, v3;
        int n = sscanf(p + 1, "%d, %d, %d, %d", &v0, &v1, &v2, &v3);
        if (n >= 3) {
            tris[tri_cnt++] = (Triangle){v0, v1, v2};
            if (n == 4) tris[tri_cnt++] = (Triangle){v0, v2, v3};

            Vec3 p0 = verts[v0].pos;
            Vec3 p1 = verts[v1].pos;
            Vec3 p2 = verts[v2].pos;
            Vec3 fn = vec3_cross(vec3_sub(p1, p0), vec3_sub(p2, p0));
            verts[v0].normal = vec3_add(verts[v0].normal, fn);
            verts[v1].normal = vec3_add(verts[v1].normal, fn);
            verts[v2].normal = vec3_add(verts[v2].normal, fn);
            if (n == 4) verts[v3].normal = vec3_add(verts[v3].normal, fn);
        }
        p = strchr(p, ']'); p++;
    }
    for (int i = 0; i < num_v; i++) verts[i].normal = vec3_norm(verts[i].normal);
    free(buf);

    mesh.num_vertices = num_v;
    mesh.vertices = verts;
    mesh.num_triangles = tri_cnt;
    mesh.triangles = tris;
    return mesh;
}

void apply_wall_uv(Mesh *mesh, int wall_type) {
    for (int i = 0; i < mesh->num_vertices; i++) {
        float x = mesh->vertices[i].pos.x;
        float y = mesh->vertices[i].pos.y;
        float z = mesh->vertices[i].pos.z;

        if (wall_type == 0) { // Wall Military (Sector 07)
            if (x < -0.445f) {
                float u = 0.635f + (x - (-0.500f)) / 0.055f * 0.070f;
                float v = 0.010f + (0.134f - y) / 0.267f * 0.980f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (x >= -0.045f && x <= 0.045f) {
                float u = 0.635f + (x - (-0.045f)) / 0.090f * 0.070f;
                float v = 0.010f + (0.134f - y) / 0.267f * 0.980f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (x > 0.445f) {
                float u = 0.635f + (x - 0.445f) / 0.055f * 0.070f;
                float v = 0.010f + (0.134f - y) / 0.267f * 0.980f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (y > 0.085f) {
                float u = 0.610f + fmodf(fabsf(x) * 4.0f, 1.0f) * 0.350f;
                float v = 0.010f + (0.134f - y) / 0.048f * 0.080f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (y < -0.070f) {
                float u = 0.150f + fmodf(fabsf(x) * 4.0f, 1.0f) * 0.350f;
                float v = 0.720f + (-0.070f - y) / 0.063f * 0.240f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else {
                if (x >= -0.445f && x < -0.245f) {
                    float px = (x - (-0.445f)) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.400f + px * 0.157f, 0.010f + py * 0.117f};
                } else if (x >= -0.245f && x < -0.045f) {
                    float px = (x - (-0.245f)) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.166f + px * 0.156f, 0.585f + py * 0.095f};
                } else if (x >= 0.045f && x < 0.245f) {
                    float px = (x - 0.045f) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.400f + px * 0.157f, 0.410f + py * 0.117f};
                } else {
                    float px = (x - 0.245f) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.400f + px * 0.157f, 0.527f + py * 0.098f};
                }
            }
        } else if (wall_type == 1) { // Wall Hazard
            if (x < -0.445f) {
                float u = 0.640f + (x - (-0.500f)) / 0.055f * 0.070f;
                float v = 0.650f + (0.134f - y) / 0.267f * 0.330f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (x >= -0.045f && x <= 0.045f) {
                float u = 0.640f + (x - (-0.045f)) / 0.090f * 0.070f;
                float v = 0.650f + (0.134f - y) / 0.267f * 0.330f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (x > 0.445f) {
                float u = 0.640f + (x - 0.445f) / 0.055f * 0.070f;
                float v = 0.650f + (0.134f - y) / 0.267f * 0.330f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (y > 0.085f) {
                float u = 0.355f + fmodf(fabsf(x) * 4.0f, 1.0f) * 0.145f;
                float v = 0.020f + (0.134f - y) / 0.048f * 0.320f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (y < -0.070f) {
                float u = 0.780f + fmodf(fabsf(x) * 4.0f, 1.0f) * 0.200f;
                float v = 0.660f + (-0.070f - y) / 0.063f * 0.160f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else {
                if (x >= -0.445f && x < -0.245f) {
                    float px = (x - (-0.445f)) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.015f + px * 0.155f, 0.015f + py * 0.315f};
                } else if (x >= -0.245f && x < -0.045f) {
                    float px = (x - (-0.245f)) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.180f + px * 0.170f, 0.340f + py * 0.310f};
                } else if (x >= 0.045f && x < 0.245f) {
                    float px = (x - 0.045f) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.785f + px * 0.195f, 0.020f + py * 0.310f};
                } else {
                    float px = (x - 0.245f) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.630f + px * 0.140f, 0.340f + py * 0.310f};
                }
            }
        } else if (wall_type == 2) { // Wall Tech
            if (x < -0.445f) {
                float u = 0.520f + (x - (-0.500f)) / 0.055f * 0.080f;
                float v = 0.500f + (0.134f - y) / 0.267f * 0.460f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (x >= -0.045f && x <= 0.045f) {
                float u = 0.520f + (x - (-0.045f)) / 0.090f * 0.080f;
                float v = 0.500f + (0.134f - y) / 0.267f * 0.460f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (x > 0.445f) {
                float u = 0.520f + (x - 0.445f) / 0.055f * 0.080f;
                float v = 0.500f + (0.134f - y) / 0.267f * 0.460f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (y > 0.085f) {
                float u = 0.040f + fmodf(fabsf(x) * 4.0f, 1.0f) * 0.440f;
                float v = 0.740f + (0.134f - y) / 0.048f * 0.100f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (y < -0.070f) {
                float u = 0.740f + fmodf(fabsf(x) * 4.0f, 1.0f) * 0.220f;
                float v = 0.740f + (-0.070f - y) / 0.063f * 0.220f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else {
                if (x >= -0.445f && x < -0.245f) {
                    float px = (x - (-0.445f)) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.260f + px * 0.220f, 0.030f + py * 0.220f};
                } else if (x >= -0.245f && x < -0.045f) {
                    float px = (x - (-0.245f)) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.030f + px * 0.220f, 0.260f + py * 0.220f};
                } else if (x >= 0.045f && x < 0.245f) {
                    float px = (x - 0.045f) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.500f + px * 0.220f, 0.260f + py * 0.220f};
                } else {
                    float px = (x - 0.245f) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.260f + px * 0.220f, 0.500f + py * 0.220f};
                }
            }
        } else { // Wall Rusted
            if (x < -0.445f) {
                float u = 0.005f + (x - (-0.500f)) / 0.055f * 0.065f;
                float v = 0.020f + (0.134f - y) / 0.267f * 0.420f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (x >= -0.045f && x <= 0.045f) {
                float u = 0.005f + (x - (-0.045f)) / 0.090f * 0.065f;
                float v = 0.020f + (0.134f - y) / 0.267f * 0.420f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (x > 0.445f) {
                float u = 0.005f + (x - 0.445f) / 0.055f * 0.065f;
                float v = 0.020f + (0.134f - y) / 0.267f * 0.420f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (y > 0.085f) {
                float u = 0.500f + fmodf(fabsf(x) * 4.0f, 1.0f) * 0.480f;
                float v = 0.760f + (0.134f - y) / 0.048f * 0.080f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else if (y < -0.070f) {
                float u = 0.250f + fmodf(fabsf(x) * 4.0f, 1.0f) * 0.250f;
                float v = 0.460f + (-0.070f - y) / 0.063f * 0.270f;
                mesh->vertices[i].uv = (Vec2){u, v};
            } else {
                if (x >= -0.445f && x < -0.245f) {
                    float px = (x - (-0.445f)) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.040f + px * 0.200f, 0.020f + py * 0.420f};
                } else if (x >= -0.245f && x < -0.045f) {
                    float px = (x - (-0.245f)) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.250f + px * 0.250f, 0.750f + py * 0.230f};
                } else if (x >= 0.045f && x < 0.245f) {
                    float px = (x - 0.045f) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.500f + px * 0.240f, 0.020f + py * 0.420f};
                } else {
                    float px = (x - 0.245f) / 0.200f; float py = (0.085f - y) / 0.155f;
                    mesh->vertices[i].uv = (Vec2){0.750f + px * 0.230f, 0.020f + py * 0.420f};
                }
            }
        }
    }
}

void apply_ground_uv(Mesh *mesh) {
    for (int i = 0; i < mesh->num_vertices; i++) {
        float x = mesh->vertices[i].pos.x;
        float z = mesh->vertices[i].pos.z;
        float u = (x - (-0.5f)) / 1.0f;
        float v = (z - (-0.5f)) / 1.0f;
        mesh->vertices[i].uv = (Vec2){fmaxf(0.001f, fminf(0.999f, u)), fmaxf(0.001f, fminf(0.999f, v))};
    }
}

int main(int argc, char **argv) {
    int mode = (argc > 1) ? atoi(argv[1]) : 0; // 0 = wall variants, 1 = ground variants, 2 = environment showcase

    int W = 1920, H = 1080;
    Pixel *fb = (Pixel *)malloc(W * H * sizeof(Pixel));
    float *zb = (float *)malloc(W * H * sizeof(float));

    for (int y = 0; y < H; y++) {
        float ny = (float)y / H;
        for (int x = 0; x < W; x++) {
            float nx = (float)x / W;
            float d = hypotf(nx - 0.5f, ny - 0.5f);
            uint8_t bg = (uint8_t)(fmaxf(12.0f, 26.0f - d * 18.0f));
            uint8_t grid = (x % 40 == 0 || y % 40 == 0) ? 4 : 0;
            fb[y * W + x] = (Pixel){
                (uint8_t)(bg * 0.85f + grid),
                (uint8_t)(bg + grid * 1.5f),
                (uint8_t)(bg * 1.3f + grid * 2.0f)
            };
            zb[y * W + x] = 1.0f;
        }
    }

    Pixel card_bg = {15, 23, 36};

    if (mode == 0) {
        // MODE 0: ALL 4 WALL VARIANTS (2x2 Grid + Multi-bay Previews)
        Mesh wall_mesh = load_json_mesh("wall.json");

        system("convert data/models/wall/textures/Wall_albedo.png tool/tex_wall_mil.ppm");
        system("convert data/models/wall_hazard/textures/Wall_Hazard_albedo.png tool/tex_wall_haz.ppm");
        system("convert data/models/wall_tech/textures/Wall_Tech_albedo.png tool/tex_wall_tech.ppm");
        system("convert data/models/wall_rusted/textures/Wall_Rusted_albedo.png tool/tex_wall_rust.ppm");

        Texture tex_mil = load_ppm("tool/tex_wall_mil.ppm");
        Texture tex_haz = load_ppm("tool/tex_wall_haz.ppm");
        Texture tex_tech = load_ppm("tool/tex_wall_tech.ppm");
        Texture tex_rust = load_ppm("tool/tex_wall_rust.ppm");

        struct {
            int vx, vy, vw, vh;
            int wall_type;
            Texture *tex;
            Vec3 em_tint;
        } cards[4] = {
            { 40,   60, 890, 460, 0, &tex_mil,  {0.2f, 0.8f, 1.0f} },
            { 990,  60, 890, 460, 1, &tex_haz,  {1.0f, 0.7f, 0.1f} },
            { 40,  560, 890, 460, 2, &tex_tech, {0.1f, 0.6f, 1.0f} },
            { 990, 560, 890, 460, 3, &tex_rust, {1.0f, 0.2f, 0.1f} },
        };

        for (int c = 0; c < 4; c++) {
            int vx = cards[c].vx, vy = cards[c].vy, vw = cards[c].vw, vh = cards[c].vh;
            draw_border_box(fb, vx - 4, vy - 4, vw + 8, vh + 8, (Pixel){30, 58, 88}, card_bg);

            apply_wall_uv(&wall_mesh, cards[c].wall_type);

            Vec3 eye = {0.70f, 0.28f, 0.84f};
            Vec3 target = {0.0f, -0.01f, 0.0f};
            Vec3 up = {0.0f, 1.0f, 0.0f};
            Mat4 view = mat4_lookat(eye, target, up);
            Mat4 proj = mat4_perspective(33.0f * 3.14159f / 180.0f, (float)vw / vh, 0.1f, 20.0f);
            Mat4 model = mat4_ident();

            for (int i = 0; i < wall_mesh.num_triangles; i++) {
                Triangle t = wall_mesh.triangles[i];
                ShadedVertex v0 = transform_vertex(wall_mesh.vertices[t.v0], model, view, proj);
                ShadedVertex v1 = transform_vertex(wall_mesh.vertices[t.v1], model, view, proj);
                ShadedVertex v2 = transform_vertex(wall_mesh.vertices[t.v2], model, view, proj);
                rasterize_triangle(v0, v1, v2, cards[c].tex, fb, zb, W, H, vx, vy, vw, vh, cards[c].em_tint);
            }
        }

        FILE *out = fopen("data/models/wall/wall_variants_render.ppm", "wb");
        fprintf(out, "P6\n%d %d\n255\n", W, H);
        fwrite(fb, 1, W * H * 3, out);
        fclose(out);
        system("convert data/models/wall/wall_variants_render.ppm data/models/wall/wall_variants_render.png");
        system("rm -f data/models/wall/wall_variants_render.ppm tool/tex_wall_*.ppm");

    } else if (mode == 1) {
        // MODE 1: GROUND 3D MODEL & TEXTURE VARIANTS
        Mesh ground_mesh = load_json_mesh("ground.json");
        apply_ground_uv(&ground_mesh);

        system("convert data/models/ground/textures/Ground_albedo.png tool/tex_gnd_mil.ppm");
        system("convert data/models/ground_hazard/textures/Ground_Hazard_albedo.png tool/tex_gnd_haz.ppm");
        system("convert data/models/ground_tech/textures/Ground_Tech_albedo.png tool/tex_gnd_tech.ppm");

        Texture tex_mil = load_ppm("tool/tex_gnd_mil.ppm");
        Texture tex_haz = load_ppm("tool/tex_gnd_haz.ppm");
        Texture tex_tech = load_ppm("tool/tex_gnd_tech.ppm");

        // CARD 1: Main Perspective 3D Tile (Left)
        {
            int vx = 40, vy = 60, vw = 1120, vh = 960;
            draw_border_box(fb, vx - 4, vy - 4, vw + 8, vh + 8, (Pixel){30, 58, 88}, card_bg);

            Vec3 eye = {0.95f, 1.10f, 1.25f};
            Vec3 target = {0.0f, -0.02f, 0.0f};
            Vec3 up = {0.0f, 1.0f, 0.0f};
            Mat4 view = mat4_lookat(eye, target, up);
            Mat4 proj = mat4_perspective(35.0f * 3.14159f / 180.0f, (float)vw / vh, 0.1f, 20.0f);
            Mat4 model = mat4_ident();

            for (int i = 0; i < ground_mesh.num_triangles; i++) {
                Triangle t = ground_mesh.triangles[i];
                ShadedVertex v0 = transform_vertex(ground_mesh.vertices[t.v0], model, view, proj);
                ShadedVertex v1 = transform_vertex(ground_mesh.vertices[t.v1], model, view, proj);
                ShadedVertex v2 = transform_vertex(ground_mesh.vertices[t.v2], model, view, proj);
                rasterize_triangle(v0, v1, v2, &tex_mil, fb, zb, W, H, vx, vy, vw, vh, vec3(0.2f, 0.8f, 1.0f));
            }
        }

        // CARD 2: Industrial Hazard Ground Tile (Top Right)
        {
            int vx = 1200, vy = 60, vw = 680, vh = 460;
            draw_border_box(fb, vx - 4, vy - 4, vw + 8, vh + 8, (Pixel){30, 58, 88}, card_bg);

            Vec3 eye = {0.85f, 0.95f, 1.10f};
            Vec3 target = {0.0f, -0.02f, 0.0f};
            Vec3 up = {0.0f, 1.0f, 0.0f};
            Mat4 view = mat4_lookat(eye, target, up);
            Mat4 proj = mat4_perspective(35.0f * 3.14159f / 180.0f, (float)vw / vh, 0.1f, 20.0f);
            Mat4 model = mat4_ident();

            for (int i = 0; i < ground_mesh.num_triangles; i++) {
                Triangle t = ground_mesh.triangles[i];
                ShadedVertex v0 = transform_vertex(ground_mesh.vertices[t.v0], model, view, proj);
                ShadedVertex v1 = transform_vertex(ground_mesh.vertices[t.v1], model, view, proj);
                ShadedVertex v2 = transform_vertex(ground_mesh.vertices[t.v2], model, view, proj);
                rasterize_triangle(v0, v1, v2, &tex_haz, fb, zb, W, H, vx, vy, vw, vh, vec3(1.0f, 0.7f, 0.1f));
            }
        }

        // CARD 3: Quantum Tech Hex Ground Tile (Bottom Right)
        {
            int vx = 1200, vy = 560, vw = 680, vh = 460;
            draw_border_box(fb, vx - 4, vy - 4, vw + 8, vh + 8, (Pixel){30, 58, 88}, card_bg);

            Vec3 eye = {0.85f, 0.95f, 1.10f};
            Vec3 target = {0.0f, -0.02f, 0.0f};
            Vec3 up = {0.0f, 1.0f, 0.0f};
            Mat4 view = mat4_lookat(eye, target, up);
            Mat4 proj = mat4_perspective(35.0f * 3.14159f / 180.0f, (float)vw / vh, 0.1f, 20.0f);
            Mat4 model = mat4_ident();

            for (int i = 0; i < ground_mesh.num_triangles; i++) {
                Triangle t = ground_mesh.triangles[i];
                ShadedVertex v0 = transform_vertex(ground_mesh.vertices[t.v0], model, view, proj);
                ShadedVertex v1 = transform_vertex(ground_mesh.vertices[t.v1], model, view, proj);
                ShadedVertex v2 = transform_vertex(ground_mesh.vertices[t.v2], model, view, proj);
                rasterize_triangle(v0, v1, v2, &tex_tech, fb, zb, W, H, vx, vy, vw, vh, vec3(0.1f, 0.6f, 1.0f));
            }
        }

        FILE *out = fopen("data/models/ground/ground_render.ppm", "wb");
        fprintf(out, "P6\n%d %d\n255\n", W, H);
        fwrite(fb, 1, W * H * 3, out);
        fclose(out);
        system("convert data/models/ground/ground_render.ppm data/models/ground/ground_render.png");
        system("rm -f data/models/ground/ground_render.ppm tool/tex_gnd_*.ppm");

    } else if (mode == 2) {
        // MODE 2: ENVIRONMENT SHOWCASE (Modular Wall & Ground Environment Assembly)
        Mesh wall_mesh = load_json_mesh("wall.json");
        Mesh ground_mesh = load_json_mesh("ground.json");
        apply_ground_uv(&ground_mesh);

        system("convert data/models/wall/textures/Wall_albedo.png tool/tex_w_mil.ppm");
        system("convert data/models/wall_hazard/textures/Wall_Hazard_albedo.png tool/tex_w_haz.ppm");
        system("convert data/models/wall_tech/textures/Wall_Tech_albedo.png tool/tex_w_tech.ppm");
        system("convert data/models/wall_rusted/textures/Wall_Rusted_albedo.png tool/tex_w_rust.ppm");

        system("convert data/models/ground/textures/Ground_albedo.png tool/tex_g_mil.ppm");
        system("convert data/models/ground_hazard/textures/Ground_Hazard_albedo.png tool/tex_g_haz.ppm");
        system("convert data/models/ground_tech/textures/Ground_Tech_albedo.png tool/tex_g_tech.ppm");

        Texture w_mil = load_ppm("tool/tex_w_mil.ppm");
        Texture w_haz = load_ppm("tool/tex_w_haz.ppm");
        Texture w_tech = load_ppm("tool/tex_w_tech.ppm");
        Texture w_rust = load_ppm("tool/tex_w_rust.ppm");

        Texture g_mil = load_ppm("tool/tex_g_mil.ppm");
        Texture g_haz = load_ppm("tool/tex_g_haz.ppm");
        Texture g_tech = load_ppm("tool/tex_g_tech.ppm");

        struct {
            int vx, vy, vw, vh;
            int wall_type;
            Texture *w_tex, *g_tex;
            Vec3 em_tint;
        } envs[4] = {
            { 40,   60, 890, 460, 0, &w_mil,  &g_mil,  {0.2f, 0.8f, 1.0f} },
            { 990,  60, 890, 460, 1, &w_haz,  &g_haz,  {1.0f, 0.7f, 0.1f} },
            { 40,  560, 890, 460, 2, &w_tech, &g_tech, {0.1f, 0.6f, 1.0f} },
            { 990, 560, 890, 460, 3, &w_rust, &g_mil,  {1.0f, 0.2f, 0.1f} },
        };

        for (int e = 0; e < 4; e++) {
            int vx = envs[e].vx, vy = envs[e].vy, vw = envs[e].vw, vh = envs[e].vh;
            draw_border_box(fb, vx - 4, vy - 4, vw + 8, vh + 8, (Pixel){30, 58, 88}, card_bg);

            apply_wall_uv(&wall_mesh, envs[e].wall_type);

            Vec3 eye = {1.35f, 0.85f, 1.65f};
            Vec3 target = {0.0f, 0.10f, 0.0f};
            Vec3 up = {0.0f, 1.0f, 0.0f};
            Mat4 view = mat4_lookat(eye, target, up);
            Mat4 proj = mat4_perspective(35.0f * 3.14159f / 180.0f, (float)vw / vh, 0.1f, 20.0f);

            // Render Ground 2x2 Grid
            for (int gz = -1; gz <= 0; gz++) {
                for (int gx = -1; gx <= 0; gx++) {
                    Mat4 model = mat4_translate((float)gx * 1.0f + 0.5f, 0.0f, (float)gz * 1.0f + 0.5f);
                    for (int i = 0; i < ground_mesh.num_triangles; i++) {
                        Triangle t = ground_mesh.triangles[i];
                        ShadedVertex v0 = transform_vertex(ground_mesh.vertices[t.v0], model, view, proj);
                        ShadedVertex v1 = transform_vertex(ground_mesh.vertices[t.v1], model, view, proj);
                        ShadedVertex v2 = transform_vertex(ground_mesh.vertices[t.v2], model, view, proj);
                        rasterize_triangle(v0, v1, v2, envs[e].g_tex, fb, zb, W, H, vx, vy, vw, vh, envs[e].em_tint);
                    }
                }
            }

            // Render Back Wall Span (2 bays along -Z edge)
            for (int bx = -1; bx <= 0; bx++) {
                Mat4 model = mat4_translate((float)bx * 1.00087f + 0.5f, 0.134f, -0.0f);
                for (int i = 0; i < wall_mesh.num_triangles; i++) {
                    Triangle t = wall_mesh.triangles[i];
                    ShadedVertex v0 = transform_vertex(wall_mesh.vertices[t.v0], model, view, proj);
                    ShadedVertex v1 = transform_vertex(wall_mesh.vertices[t.v1], model, view, proj);
                    ShadedVertex v2 = transform_vertex(wall_mesh.vertices[t.v2], model, view, proj);
                    rasterize_triangle(v0, v1, v2, envs[e].w_tex, fb, zb, W, H, vx, vy, vw, vh, envs[e].em_tint);
                }
            }
        }

        FILE *out = fopen("data/models/environment_showcase.ppm", "wb");
        fprintf(out, "P6\n%d %d\n255\n", W, H);
        fwrite(fb, 1, W * H * 3, out);
        fclose(out);
        system("convert data/models/environment_showcase.ppm data/models/environment_showcase.png");
        system("rm -f data/models/environment_showcase.ppm tool/tex_*.ppm");
    }

    return 0;
}
