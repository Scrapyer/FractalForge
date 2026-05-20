#include <metal_stdlib>
using namespace metal;

struct FrameUniforms {
    float2 resolution;
    float2 centerHi;
    float2 centerLo;
    float2 juliaConstant;
    float4 backgroundColor;
    float scaleHi;
    float scaleLo;
    float time;
    float bailoutRadius;
    float rotation;
    float multibrotPower;
    float mandelbulbPower;
    float cameraPitch;
    float cameraDistance;
    float surfaceDetail;
    float contrast;
    float exposure;
    int maxIter;
    int fractalType;
    int precisionMode;
    int colorPalette;
    int antialiasingMode;
    int smoothColoring;
    int rayMarchSteps;
    float2 quaternionConstantZW;
    float fourDSlice;
    float timeDelta;
    int frameIndex;
    float4 shadertoyMouse;
    int shadertoyKeyMask;
};

struct DS {
    float hi;
    float lo;
};

struct DS2 {
    DS x;
    DS y;
};

inline DS dsAdd(DS a, DS b) {
    const float s = a.hi + b.hi;
    const float bb = s - a.hi;
    const float e = (a.hi - (s - bb)) + (b.hi - bb);
    return DS { s, e + a.lo + b.lo };
}

inline DS dsSub(DS a, DS b) {
    return dsAdd(a, DS { -b.hi, -b.lo });
}

inline DS dsMul(DS a, DS b) {
    const float p = a.hi * b.hi;
    const float e = fma(a.hi, b.hi, -p);
    return DS { p, fma(a.hi, b.lo, fma(a.lo, b.hi, e)) };
}

inline DS dsSqr(DS a) {
    return dsMul(a, a);
}

inline float dsToFloat(DS v) {
    return v.hi + v.lo;
}

inline DS2 complexFromUV(float u, float v, constant FrameUniforms &uniforms) {
    const DS scale = DS { uniforms.scaleHi, uniforms.scaleLo };
    return DS2 {
        dsAdd(DS { uniforms.centerHi.x, uniforms.centerLo.x }, dsMul(DS { u, 0.0f }, scale)),
        dsAdd(DS { uniforms.centerHi.y, uniforms.centerLo.y }, dsMul(DS { v, 0.0f }, scale))
    };
}

// Ported from Inigo Quilez's Shadertoy "Mandelbrot - smooth" (4df3Rn).
inline bool shouldUseFastPath(int precisionMode, float scale) {
    if (precisionMode == 1) {
        return true;
    }
    if (precisionMode == 2) {
        return false;
    }
    return scale > 1e-5f;
}

inline float shadertoyMandelbrotFast(float2 c, int maxIter, float bailout) {
    const float c2 = dot(c, c);

    if (256.0f * c2 * c2 - 96.0f * c2 + 32.0f * c.x - 3.0f < 0.0f) {
        return 0.0f;
    }
    if (16.0f * (c2 + 2.0f * c.x + 1.0f) - 1.0f < 0.0f) {
        return 0.0f;
    }

    float2 z = float2(0.0f);
    float n = 0.0f;
    float len2 = 0.0f;
    bool escaped = false;

    for (int i = 0; i < 4096; i++) {
        if (i >= maxIter) {
            break;
        }

        z = float2(z.x * z.x - z.y * z.y, 2.0f * z.x * z.y) + c;
        len2 = dot(z, z);
        if (len2 > bailout * bailout) {
            escaped = true;
            break;
        }
        n += 1.0f;
    }

    if (!escaped) {
        return 0.0f;
    }

    return n - log2(log2(max(len2, 1.000001f))) + 4.0f;
}

inline float shadertoyJuliaFast(float2 z, float2 c, int maxIter, float bailout) {
    float n = 0.0f;
    float len2 = dot(z, z);
    bool escaped = false;

    for (int i = 0; i < 4096; i++) {
        if (i >= maxIter) {
            break;
        }

        z = float2(z.x * z.x - z.y * z.y, 2.0f * z.x * z.y) + c;
        len2 = dot(z, z);
        if (len2 > bailout * bailout) {
            escaped = true;
            break;
        }
        n += 1.0f;
    }

    if (!escaped) {
        return 0.0f;
    }

    return n - log2(log2(max(len2, 1.000001f))) + 4.0f;
}

inline float burningShip(float2 c, int maxIter, float bailout) {
    float2 z = float2(0.0f);
    float n = 0.0f;
    float len2 = 0.0f;
    bool escaped = false;

    for (int i = 0; i < 4096; i++) {
        if (i >= maxIter) {
            break;
        }

        z = abs(z);
        z = float2(z.x * z.x - z.y * z.y, 2.0f * z.x * z.y) + c;
        len2 = dot(z, z);
        if (len2 > bailout * bailout) {
            escaped = true;
            break;
        }
        n += 1.0f;
    }

    if (!escaped) {
        return 0.0f;
    }

    return n - log2(log2(max(len2, 1.000001f))) + 4.0f;
}

inline float multibrot(float2 c, int maxIter, float bailout, float power) {
    float2 z = float2(0.0f);
    float n = 0.0f;
    float len2 = 0.0f;
    bool escaped = false;

    for (int i = 0; i < 4096; i++) {
        if (i >= maxIter) {
            break;
        }

        const float r = max(length(z), 1e-8f);
        const float theta = atan2(z.y, z.x);
        const float rp = pow(r, max(power, 1.01f));
        z = rp * float2(cos(power * theta), sin(power * theta)) + c;
        len2 = dot(z, z);
        if (len2 > bailout * bailout) {
            escaped = true;
            break;
        }
        n += 1.0f;
    }

    if (!escaped) {
        return 0.0f;
    }

    return n - log2(log2(max(len2, 1.000001f))) + 4.0f;
}

inline float newtonFractal(float2 z, int maxIter) {
    float n = 0.0f;
    float rootBias = 0.0f;

    for (int i = 0; i < 192; i++) {
        if (i >= maxIter) {
            break;
        }

        const float2 z2 = float2(z.x * z.x - z.y * z.y, 2.0f * z.x * z.y);
        const float2 z3 = float2(z2.x * z.x - z2.y * z.y, z2.x * z.y + z2.y * z.x);
        const float2 f = z3 - float2(1.0f, 0.0f);
        const float2 df = 3.0f * z2;
        const float denom = max(dot(df, df), 1e-8f);
        const float2 step = float2(
            (f.x * df.x + f.y * df.y) / denom,
            (f.y * df.x - f.x * df.y) / denom
        );
        z -= step;
        n += 1.0f;

        if (dot(f, f) < 1e-8f) {
            const float angle = atan2(z.y, z.x);
            rootBias = floor((angle + 3.14159265f) / 2.0943951f);
            break;
        }
    }

    return n + rootBias * 18.0f;
}

inline float mandelbox2D(float2 c, int maxIter, float bailout) {
    float2 z = c;
    float n = 0.0f;
    float len2 = dot(z, z);
    bool escaped = false;
    float trap = 12.0f;
    float foldGlow = 0.0f;

    for (int i = 0; i < 4096; i++) {
        if (i >= maxIter) {
            break;
        }

        const float2 beforeFold = z;
        z = clamp(z, float2(-1.0f), float2(1.0f)) * 2.0f - z;
        foldGlow += exp(-8.0f * length(z - beforeFold));
        len2 = dot(z, z);
        if (len2 < 0.25f) {
            z *= 4.0f;
        } else if (len2 < 1.0f) {
            z /= len2;
        }
        z = z * 1.8f + c;
        len2 = dot(z, z);
        trap = min(trap, min(length(z), fabs(abs(z.x) - abs(z.y)) + 0.12f * length(z)));
        if (len2 > bailout * bailout) {
            escaped = true;
            break;
        }
        n += 1.0f;
    }

    if (!escaped) {
        const float trapGlow = exp(-3.6f * trap);
        const float foldTone = clamp(foldGlow / max(n, 1.0f), 0.0f, 1.0f);
        return 6.0f + 96.0f * trapGlow + 42.0f * foldTone + 10.0f * sin(18.0f * trap);
    }

    return n - log2(log2(max(len2, 1.000001f))) + 4.0f;
}

inline float shadertoyMandelbrot(DS2 c, int maxIter, float scale, float bailout, int precisionMode) {
    const float2 cApprox = float2(dsToFloat(c.x), dsToFloat(c.y));

    if (shouldUseFastPath(precisionMode, scale)) {
        return shadertoyMandelbrotFast(cApprox, maxIter, bailout);
    }

    DS2 z = DS2 { DS { 0.0f, 0.0f }, DS { 0.0f, 0.0f } };
    float n = 0.0f;
    float len2 = 0.0f;
    bool escaped = false;

    for (int i = 0; i < 4096; i++) {
        if (i >= maxIter) {
            break;
        }

        const DS xx = dsSqr(z.x);
        const DS yy = dsSqr(z.y);
        const DS xy = dsMul(z.x, z.y);
        z = DS2 {
            dsAdd(dsSub(xx, yy), c.x),
            dsAdd(dsAdd(xy, xy), c.y)
        };

        len2 = dsToFloat(dsAdd(dsSqr(z.x), dsSqr(z.y)));
        if (len2 > bailout * bailout) {
            escaped = true;
            break;
        }
        n += 1.0f;
    }

    if (!escaped) {
        return 0.0f;
    }

    return n - log2(log2(max(len2, 1.000001f))) + 4.0f;
}

inline float shadertoyJulia(DS2 z, float2 c, int maxIter, float scale, float bailout, int precisionMode) {
    if (shouldUseFastPath(precisionMode, scale)) {
        return shadertoyJuliaFast(float2(dsToFloat(z.x), dsToFloat(z.y)), c, maxIter, bailout);
    }

    const DS2 juliaC = DS2 { DS { c.x, 0.0f }, DS { c.y, 0.0f } };
    float n = 0.0f;
    float len2 = 0.0f;
    bool escaped = false;

    for (int i = 0; i < 4096; i++) {
        if (i >= maxIter) {
            break;
        }

        const DS xx = dsSqr(z.x);
        const DS yy = dsSqr(z.y);
        const DS xy = dsMul(z.x, z.y);
        z = DS2 {
            dsAdd(dsSub(xx, yy), juliaC.x),
            dsAdd(dsAdd(xy, xy), juliaC.y)
        };

        len2 = dsToFloat(dsAdd(dsSqr(z.x), dsSqr(z.y)));
        if (len2 > bailout * bailout) {
            escaped = true;
            break;
        }
        n += 1.0f;
    }

    if (!escaped) {
        return 0.0f;
    }

    return n - log2(log2(max(len2, 1.000001f))) + 4.0f;
}

inline float3 shadertoyColor(float l) {
    if (l < 0.5f) {
        return float3(0.0f);
    }

    float3 col = 0.5f + 0.5f * cos(3.0f + 0.15f * l + float3(0.0f, 0.6f, 1.0f));
    return pow(saturate(col), float3(0.85f));
}

inline float3 paletteColor(float l, int palette) {
    if (l < 0.5f) {
        return float3(0.0f);
    }

    const float t = max(l, 0.0f);

    if (palette == 1) {
        const float3 ember = 0.5f + 0.5f * cos(2.4f + 0.18f * t + float3(1.1f, 0.35f, -0.25f));
        return pow(saturate(ember * float3(1.25f, 0.78f, 0.42f)), float3(0.82f));
    }

    if (palette == 2) {
        const float3 aurora = 0.5f + 0.5f * cos(3.7f + 0.12f * t + float3(0.15f, 1.55f, 3.2f));
        return pow(saturate(aurora * float3(0.7f, 1.15f, 1.05f)), float3(0.9f));
    }

    if (palette == 3) {
        const float3 electric = 0.5f + 0.5f * cos(4.2f + 0.22f * t + float3(3.0f, 1.4f, 0.0f));
        return pow(saturate(electric * float3(0.55f, 0.9f, 1.35f)), float3(0.72f));
    }

    if (palette == 4) {
        const float value = pow(saturate(0.18f + 0.82f * sin(0.12f * t)), 0.85f);
        return float3(value);
    }

    return shadertoyColor(t);
}

inline int antialiasingSamples(int mode, int maxIter) {
    if (mode == 1) {
        return 1;
    }
    if (mode == 2) {
        return 2;
    }
    if (mode == 4) {
        return 4;
    }
    return maxIter > 1400 ? 1 : 2;
}

inline float2 animatedShadertoyUV(float2 uv, float time) {
    float zoom = 0.94f + 0.06f * cos(0.18f * time);
    const float theta = 0.05f * (1.0f - zoom) * time;
    const float co = cos(theta);
    const float si = sin(theta);
    zoom = pow(zoom, 4.0f);

    const float2 rotated = float2(uv.x * co - uv.y * si, uv.x * si + uv.y * co);
    return rotated * zoom;
}

inline float hash21(float2 p) {
    p = fract(p * float2(123.34f, 345.45f));
    p += dot(p, p + 34.345f);
    return fract(p.x * p.y);
}

inline float valueNoise2D(float2 p) {
    const float2 i = floor(p);
    const float2 f = fract(p);
    const float2 u = f * f * (3.0f - 2.0f * f);
    const float a = hash21(i);
    const float b = hash21(i + float2(1.0f, 0.0f));
    const float c = hash21(i + float2(0.0f, 1.0f));
    const float d = hash21(i + float2(1.0f, 1.0f));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

inline float fbm2D(float2 p) {
    float value = 0.0f;
    float amplitude = 0.5f;

    for (int i = 0; i < 6; i++) {
        value += amplitude * valueNoise2D(p);
        p = float2(p.x * 1.62f - p.y * 1.18f, p.x * 1.18f + p.y * 1.62f) + 13.7f;
        amplitude *= 0.5f;
    }

    return value;
}

inline float ridgeNoise(float2 p) {
    float value = 0.0f;
    float amplitude = 0.55f;

    for (int i = 0; i < 6; i++) {
        value += amplitude * pow(1.0f - fabs(2.0f * valueNoise2D(p) - 1.0f), 2.0f);
        p = p * 2.04f + float2(9.1f, 2.7f);
        amplitude *= 0.52f;
    }

    return value;
}

inline float3 shadeShadertoyTone(float tone, float mask, constant FrameUniforms &uniforms) {
    const float3 base = paletteColor(max(tone, 0.6f), uniforms.colorPalette);
    const float glow = saturate(mask);
    return mix(uniforms.backgroundColor.rgb, base, glow);
}

inline float monsterTone(float2 p, float time) {
    float2 z = p * (1.18f + 0.04f * sin(time * 0.25f));
    float trap = 10.0f;
    float folds = 0.0f;

    for (int i = 0; i < 34; i++) {
        z = abs(z);
        if (z.x < z.y) {
            z = z.yx;
        }
        z = z * 1.52f - float2(0.72f, 0.42f);
        trap = min(trap, length(z - float2(0.18f, 0.0f)));
        folds += 1.0f;
    }

    return 12.0f + folds * 0.38f + 42.0f * exp(-5.0f * trap);
}

inline float remnantTone(float2 p, float time) {
    const float r = length(p) + 0.06f;
    const float a = atan2(p.y, p.x);
    const float tunnel = sin(8.0f * a + 4.8f * log(r) - 0.25f * time);
    const float debris = fbm2D(float2(a * 2.5f, log(r) * 4.0f) + time * 0.02f);
    return 8.0f + 70.0f * pow(1.0f - fabs(tunnel), 3.0f) + debris * 34.0f;
}

inline float oceanicTone(float2 p, float time) {
    const float n = fbm2D(p * 2.2f + float2(0.05f * time, -0.025f * time));
    const float waves = 0.5f + 0.5f * sin(22.0f * (p.y + 0.22f * n) + 2.0f * time);
    const float foam = smoothstep(0.74f, 1.0f, waves + 0.35f * n);
    return 16.0f + 82.0f * (0.3f * n + 0.7f * foam);
}

inline float galaxyTone(float2 p, float time, float arms) {
    const float r = length(p) + 0.035f;
    const float a = atan2(p.y, p.x);
    const float spiral = sin(arms * a - 4.8f * log(r) + 0.08f * time);
    const float dust = fbm2D(p * 3.0f + 11.0f);
    const float core = exp(-3.2f * r);
    const float lanes = pow(saturate(1.0f - fabs(spiral)), 4.0f);
    return 10.0f + 96.0f * (core + lanes * exp(-0.9f * r) + 0.18f * dust);
}

inline float universesTone(float2 p, float time) {
    float2 q = p * 1.25f;
    float2 cell = floor(q);
    float2 local = fract(q) - 0.5f;
    float best = 0.0f;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            const float2 neighbor = float2(float(x), float(y));
            const float h = hash21(cell + neighbor);
            const float2 offset = float2(hash21(cell + neighbor + 2.3f), hash21(cell + neighbor + 7.1f)) - 0.5f;
            const float2 gp = local - neighbor - 0.48f * offset;
            best = max(best, exp(-7.0f * length(gp)) * (0.55f + h));
        }
    }

    return 14.0f + 110.0f * best + 18.0f * fbm2D(p * 7.0f + time * 0.02f);
}

inline float explorerTone(float2 p, float time) {
    float2 z = p * 0.78f;
    float trap = 6.0f;
    float scale = 1.0f;
    float edge = 0.0f;
    float depth = 0.0f;

    for (int i = 0; i < 34; i++) {
        z = abs(z);
        if (z.x < z.y) {
            z = z.yx;
        }

        z = float2(z.x - z.y, z.x + z.y) * 1.31f - float2(0.58f, 0.34f);
        z += 0.045f * sin(float(i) * 1.7f + time * 0.18f);
        scale *= 1.31f;

        const float r = length(z);
        const float lane = min(abs(z.x), abs(z.y));
        trap = min(trap, abs(r - 0.62f) / scale);
        edge += exp(-18.0f * lane) / scale;
        depth += exp(-4.0f * abs(r - 0.95f)) / scale;
    }

    const float focus = exp(-70.0f * trap);
    const float dof = smoothstep(0.08f, 0.55f, depth);
    return 8.0f + 72.0f * focus + 54.0f * edge + 24.0f * dof;
}

inline float monteCarloTone(float2 p, float2 uv, float time) {
    float hits = 0.0f;

    for (int i = 0; i < 8; i++) {
        const float fi = float(i);
        const float2 jitter = float2(hash21(uv * 317.0f + fi), hash21(uv * 191.0f + fi + 4.0f)) - 0.5f;
        const float2 samplePoint = p + 0.035f * jitter;
        const float m = shadertoyMandelbrotFast(samplePoint * 1.15f - float2(0.35f, 0.0f), 96, 16.0f);
        hits += m < 0.5f ? 1.0f : 0.0f;
    }

    const float grain = hash21(uv * 900.0f + time);
    return 6.0f + 92.0f * hits / 8.0f + grain * 18.0f;
}

inline float mountainsTone(float2 p, float time) {
    const float h1 = ridgeNoise(float2(p.x * 1.3f + 0.02f * time, 0.7f));
    const float h2 = ridgeNoise(float2(p.x * 2.4f - 0.015f * time, 3.9f));
    const float terrain = -0.52f + 0.72f * h1 + 0.23f * h2;
    const float ridge = smoothstep(0.09f, 0.0f, fabs(p.y - terrain));
    const float fill = smoothstep(p.y, terrain, terrain - 0.6f);
    return 8.0f + 80.0f * max(ridge, fill * (0.25f + 0.75f * h1));
}

inline float valueNoiseTone(float2 p, float time) {
    const float n = fbm2D(p * 3.0f + time * 0.03f);
    const float cells = valueNoise2D(p * 12.0f);
    const float edge = smoothstep(0.02f, 0.0f, fabs(cells - 0.5f));
    return 5.0f + 105.0f * (0.7f * n + 0.3f * edge);
}

inline float fluxCoreTone(float2 p, float time) {
    const float r = length(p) + 0.03f;
    const float a = atan2(p.y, p.x);
    const float rings = pow(1.0f - fabs(sin(18.0f * r - 5.0f * log(r) + time)), 3.0f);
    const float spokes = pow(1.0f - fabs(sin(10.0f * a + 3.0f * r - time * 0.7f)), 5.0f);
    const float core = exp(-3.8f * r);
    return 12.0f + 88.0f * (core + 0.55f * rings + 0.5f * spokes);
}

inline float lightAndMotionTone(float2 p, float time) {
    const float r = length(p) + 0.02f;
    const float a = atan2(p.y, p.x);
    const float beams = pow(1.0f - fabs(sin(9.0f * a + 2.0f * sin(3.0f * r - time))), 8.0f);
    const float rings = pow(1.0f - fabs(sin(26.0f * r - 1.6f * time)), 3.0f);
    const float pulse = exp(-2.4f * r) * (0.65f + 0.35f * sin(time * 1.2f));
    return 8.0f + 112.0f * (0.45f * beams + 0.35f * rings + pulse);
}

inline float shaderF3BGzWTone(float2 p, float time) {
    float2 z = p;
    float trap = 6.0f;
    float glow = 0.0f;

    for (int i = 0; i < 24; i++) {
        z = abs(z) / max(dot(z, z), 0.18f) - float2(0.72f + 0.08f * sin(time * 0.23f), 0.42f);
        const float d = abs(length(z) - 0.72f);
        trap = min(trap, d);
        glow += exp(-8.0f * d);
    }

    return 10.0f + 36.0f * glow / 24.0f + 95.0f * exp(-18.0f * trap);
}

inline float apollonianTone(float2 p) {
    float2 z = p * 1.05f;
    float scale = 1.0f;
    float trap = 8.0f;

    for (int i = 0; i < 42; i++) {
        z = -1.0f + 2.0f * fract(0.5f * z + 0.5f);
        const float r2 = max(dot(z, z), 0.045f);
        const float k = 1.18f / r2;
        z *= k;
        scale *= k;
        trap = min(trap, fabs(length(z) - 0.55f) / max(scale, 1e-4f));
    }

    return 12.0f + 120.0f * exp(-120.0f * trap);
}

inline float3 renderShadertoyResult(float2 p, float2 uv, constant FrameUniforms &uniforms) {
    float tone = 0.0f;

    if (uniforms.fractalType == 7) {
        tone = monsterTone(p, uniforms.time);
    } else if (uniforms.fractalType == 8) {
        tone = remnantTone(p, uniforms.time);
    } else if (uniforms.fractalType == 9) {
        tone = oceanicTone(p, uniforms.time);
    } else if (uniforms.fractalType == 10) {
        tone = galaxyTone(p, uniforms.time, 4.0f);
    } else if (uniforms.fractalType == 11) {
        tone = universesTone(p, uniforms.time);
    } else if (uniforms.fractalType == 12) {
        tone = explorerTone(p, uniforms.time);
    } else if (uniforms.fractalType == 13) {
        tone = monteCarloTone(p, uv, uniforms.time);
    } else if (uniforms.fractalType == 14) {
        tone = mountainsTone(p, uniforms.time);
    } else if (uniforms.fractalType == 15) {
        tone = valueNoiseTone(p, uniforms.time);
    } else if (uniforms.fractalType == 16) {
        tone = fluxCoreTone(p, uniforms.time);
    } else if (uniforms.fractalType == 21) {
        tone = lightAndMotionTone(p, uniforms.time);
    } else if (uniforms.fractalType == 23) {
        tone = shaderF3BGzWTone(p, uniforms.time);
    } else {
        tone = apollonianTone(p);
    }

    const float mask = saturate(0.18f + tone / 96.0f);
    return shadeShadertoyTone(tone, mask, uniforms);
}

inline float3 rotateX(float3 p, float angle) {
    const float c = cos(angle);
    const float s = sin(angle);
    return float3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

inline float3 rotateY(float3 p, float angle) {
    const float c = cos(angle);
    const float s = sin(angle);
    return float3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

inline float mandelbulbDistance(float3 p, float power, int iterations, float bailout) {
    float3 z = p;
    float dr = 1.0f;
    float r = 0.0f;
    const float safePower = clamp(power, 2.0f, 12.0f);

    for (int i = 0; i < 32; i++) {
        if (i >= iterations) {
            break;
        }

        r = length(z);
        if (r > bailout) {
            break;
        }

        const float safeR = max(r, 1e-6f);
        float theta = acos(clamp(z.z / safeR, -1.0f, 1.0f));
        float phi = atan2(z.y, z.x);
        const float zr = pow(safeR, safePower);
        dr = pow(safeR, safePower - 1.0f) * safePower * dr + 1.0f;

        theta *= safePower;
        phi *= safePower;

        z = zr * float3(
            sin(theta) * cos(phi),
            sin(theta) * sin(phi),
            cos(theta)
        ) + p;
    }

    return 0.5f * log(max(r, 1.000001f)) * r / max(dr, 1e-6f);
}

inline float3 mandelbulbNormal(float3 p, float power, int iterations, float bailout, float epsilon) {
    const float2 e = float2(max(epsilon, 0.0004f), 0.0f);
    return normalize(float3(
        mandelbulbDistance(p + e.xyy, power, iterations, bailout) - mandelbulbDistance(p - e.xyy, power, iterations, bailout),
        mandelbulbDistance(p + e.yxy, power, iterations, bailout) - mandelbulbDistance(p - e.yxy, power, iterations, bailout),
        mandelbulbDistance(p + e.yyx, power, iterations, bailout) - mandelbulbDistance(p - e.yyx, power, iterations, bailout)
    ));
}

inline float mandelbulbAmbientOcclusion(float3 p, float3 normal, float power, int iterations, float bailout) {
    float occlusion = 0.0f;
    float weight = 1.0f;

    for (int i = 1; i <= 5; i++) {
        const float h = 0.06f * float(i);
        const float d = mandelbulbDistance(p + normal * h, power, iterations, bailout);
        occlusion += (h - d) * weight;
        weight *= 0.55f;
    }

    return saturate(1.0f - 2.2f * occlusion);
}

inline float monsterDistance(float3 p) {
    float3 z = p;
    float scale = 1.0f;

    for (int i = 0; i < 12; i++) {
        z = abs(z);
        if (z.x < z.y) {
            z.xy = z.yx;
        }
        if (z.x < z.z) {
            z.xz = z.zx;
        }
        if (z.y < z.z) {
            z.yz = z.zy;
        }

        const float r2 = dot(z, z);
        if (r2 < 0.38f) {
            const float k = 0.38f / max(r2, 0.0001f);
            z *= k;
            scale *= k;
        }

        z = z * 1.48f - float3(0.92f, 0.42f, 0.62f);
        scale *= 1.48f;
    }

    return (length(z) - 0.78f) / max(scale, 1e-4f);
}

inline float remnantXDistance(float3 pos) {
    const float baseScale = -2.8f;
    const float minRad2 = 0.25f;
    const float4 foldScale = float4(baseScale, baseScale, baseScale, abs(baseScale)) / minRad2;
    const float absScaleMinusOne = abs(baseScale - 1.0f);
    const float shrink = pow(abs(baseScale), -9.0f);
    float4 p = float4(pos, 1.0f);
    const float4 p0 = p;

    for (int i = 0; i < 9; i++) {
        p.xyz = clamp(p.xyz, float3(-1.0f), float3(1.0f)) * 2.0f - p.xyz;
        const float r2 = dot(p.xyz, p.xyz);
        p *= clamp(max(minRad2 / max(r2, 1e-6f), minRad2), 0.0f, 1.0f);
        p = p * foldScale + p0;
    }

    return (length(p.xyz) - absScaleMinusOne) / max(p.w, 1e-4f) - shrink;
}

inline float syntopiaIFSDistance(float3 p) {
    float3 z = p;
    float scale = 1.0f;

    for (int i = 0; i < 13; i++) {
        z = abs(z);
        if (z.x - z.y < 0.0f) {
            z.xy = z.yx;
        }
        if (z.x - z.z < 0.0f) {
            z.xz = z.zx;
        }
        if (z.y - z.z < 0.0f) {
            z.yz = z.zy;
        }

        z = z * 1.58f - float3(0.86f, 0.52f, 0.32f);
        scale *= 1.58f;
    }

    return (length(z) - 0.74f) / max(scale, 1e-4f);
}

inline float mengerFoldDistance(float3 p) {
    float3 z = p;
    float scale = 1.0f;
    float d = max(max(abs(z.x), abs(z.y)), abs(z.z)) - 1.0f;

    for (int i = 0; i < 6; i++) {
        z = abs(z);
        if (z.x < z.y) {
            z.xy = z.yx;
        }
        if (z.x < z.z) {
            z.xz = z.zx;
        }
        if (z.y < z.z) {
            z.yz = z.zy;
        }

        z = z * 3.0f - float3(2.0f, 1.15f, 0.65f);
        scale *= 3.0f;
        const float crossBar = max(abs(z.y), abs(z.z)) - 0.34f;
        d = max(d, -crossBar / scale);
    }

    return d;
}

inline float mandelboxSweeperDistance(float3 p) {
    const float sweep = 0.32f * sin(p.z * 1.7f);
    p.xy += float2(sweep, -sweep * 0.55f);
    return remnantXDistance(p * 0.92f) * 1.08f;
}

inline float cosmicPearlDistance(float3 p) {
    float3 q = p;
    float scale = 1.0f;
    float d = 5.0f;

    for (int i = 0; i < 8; i++) {
        q = abs(q);
        if (q.x < q.y) {
            q.xy = q.yx;
        }
        if (q.x < q.z) {
            q.xz = q.zx;
        }
        if (q.y < q.z) {
            q.yz = q.zy;
        }

        q = q * 2.08f - float3(1.18f, 0.92f, 0.72f);
        scale *= 2.08f;

        const float pearl = length(q + 0.18f * sin(float3(1.7f, 2.1f, 2.6f) * float(i + 1))) - 0.34f;
        const float strand = max(length(q.xy) - 0.17f, abs(q.z) - 0.72f);
        d = min(d, min(pearl, strand) / scale);
    }

    return d - 0.004f;
}

inline float4 quaternionSquare(float4 q) {
    return float4(
        q.x * q.x - dot(q.yzw, q.yzw),
        2.0f * q.x * q.y,
        2.0f * q.x * q.z,
        2.0f * q.x * q.w
    );
}

inline float quaternionJuliaDistance(float3 p, constant FrameUniforms &uniforms, int maxIter) {
    float4 z = float4(p, uniforms.fourDSlice);
    const float4 c = float4(uniforms.juliaConstant, uniforms.quaternionConstantZW);
    const float bailout = clamp(uniforms.bailoutRadius, 4.0f, 32.0f);
    const int iterations = clamp(maxIter / 170, 8, 28);
    float dr = 1.0f;
    float r = length(z);

    for (int i = 0; i < 32; i++) {
        if (i >= iterations) {
            break;
        }

        dr = max(2.0f * r * dr, 1e-5f);
        z = quaternionSquare(z) + c;
        r = length(z);

        if (r > bailout) {
            break;
        }
    }

    if (r <= 1.0f) {
        return 0.0008f;
    }

    return 0.5f * log(r) * r / max(dr, 1e-5f);
}

inline float quaternionMandelbrotDistance(float3 p, constant FrameUniforms &uniforms, int maxIter) {
    float4 z = float4(0.0f);
    const float4 c = float4(p, uniforms.fourDSlice);
    const float bailout = clamp(uniforms.bailoutRadius, 4.0f, 32.0f);
    const int iterations = clamp(maxIter / 180, 8, 26);
    float dr = 1.0f;
    float r = 0.0f;

    for (int i = 0; i < 32; i++) {
        if (i >= iterations) {
            break;
        }

        dr = max(2.0f * max(r, 1e-4f) * dr, 1e-5f);
        z = quaternionSquare(z) + c;
        r = length(z);

        if (r > bailout) {
            break;
        }
    }

    if (r <= 1.0f) {
        return 0.0008f;
    }

    return 0.5f * log(r) * r / max(dr, 1e-5f);
}

inline float mandelbox4DDistance(float3 p, constant FrameUniforms &uniforms) {
    float4 z = float4(p, uniforms.fourDSlice);
    const float4 offset = z;
    float scale = 1.0f;

    for (int i = 0; i < 10; i++) {
        z = clamp(z, float4(-1.0f), float4(1.0f)) * 2.0f - z;
        const float r2 = dot(z, z);
        if (r2 < 0.22f) {
            const float k = 0.22f / max(r2, 1e-5f);
            z *= k;
            scale *= k;
        } else if (r2 < 1.0f) {
            z /= r2;
            scale /= r2;
        }

        z = z * 1.74f + offset;
        scale *= 1.74f;
    }

    const float box = max(max(abs(z.x), abs(z.y)), max(abs(z.z), abs(z.w))) - 1.1f;
    return box / max(abs(scale), 1e-4f);
}

inline float lifted4DTone(float4 q, constant FrameUniforms &uniforms, int maxIter) {
    const float2 a = q.xy + 0.42f * q.zw + 0.05f * sin(uniforms.time * 0.16f);
    const float2 b = q.xz - 0.35f * q.yw;
    const int type = uniforms.fractalType;

    if (type == 27) {
        return burningShip(a, min(maxIter, 96), 18.0f) + 0.35f * burningShip(b, 64, 18.0f);
    }
    if (type == 28) {
        return newtonFractal(a * 1.15f, 80) + 0.45f * newtonFractal(b, 48);
    }
    if (type == 29) {
        return multibrot(a, min(maxIter, 96), 18.0f, uniforms.multibrotPower) + 0.3f * multibrot(b, 64, 18.0f, uniforms.multibrotPower);
    }
    if (type == 31) {
        return oceanicTone(a + 0.22f * b, uniforms.time);
    }
    if (type == 32) {
        return galaxyTone(a + 0.18f * b, uniforms.time, 4.0f);
    }
    if (type == 33) {
        return universesTone(a + 0.15f * b, uniforms.time);
    }
    if (type == 34) {
        return explorerTone(a + 0.2f * b, uniforms.time);
    }
    if (type == 35) {
        return monteCarloTone(a, b, uniforms.time);
    }
    if (type == 36) {
        return mountainsTone(a + 0.2f * b, uniforms.time);
    }
    if (type == 37) {
        return valueNoiseTone(a + 0.3f * b, uniforms.time);
    }
    if (type == 38) {
        return fluxCoreTone(a + 0.2f * b, uniforms.time);
    }
    if (type == 39) {
        return apollonianTone(a + 0.18f * b);
    }
    if (type == 40) {
        return lightAndMotionTone(a + 0.2f * b, uniforms.time);
    }
    if (type == 41) {
        return shaderF3BGzWTone(a + 0.16f * b, uniforms.time);
    }

    return shadertoyMandelbrotFast(a, 96, 18.0f) * 1.6f + 16.0f * fbm2D(b * 2.0f);
}

inline float lifted4DDistance(float3 p, constant FrameUniforms &uniforms, int maxIter) {
    const float4 q = float4(p, uniforms.fourDSlice);
    const float tone = lifted4DTone(q, uniforms, maxIter);
    const float normalizedTone = saturate(tone / 132.0f);
    const float warp = 0.06f * sin(5.5f * q.w + 0.08f * tone + 2.0f * atan2(p.y, p.x));
    const float radius = 0.62f + 0.58f * normalizedTone + warp;
    const float shell = abs(length(p) - radius) - (0.034f + 0.038f * normalizedTone);
    const float fold = max(abs(p.z) - 1.55f, length(p.xy) - 1.9f);
    return max(shell, fold) * 0.82f;
}

inline float fractal4DDistance(float3 p, constant FrameUniforms &uniforms, int maxIter) {
    if (uniforms.fractalType == 25) {
        return quaternionJuliaDistance(p, uniforms, maxIter);
    }
    if (uniforms.fractalType == 26) {
        return quaternionMandelbrotDistance(p, uniforms, maxIter);
    }
    if (uniforms.fractalType == 30) {
        return mandelbox4DDistance(p, uniforms);
    }
    return lifted4DDistance(p, uniforms, maxIter);
}

inline float3 fractal4DNormal(float3 p, constant FrameUniforms &uniforms, int maxIter, float epsilon) {
    const float2 e = float2(max(epsilon, 0.00018f), 0.0f);
    return normalize(float3(
        fractal4DDistance(p + e.xyy, uniforms, maxIter) - fractal4DDistance(p - e.xyy, uniforms, maxIter),
        fractal4DDistance(p + e.yxy, uniforms, maxIter) - fractal4DDistance(p - e.yxy, uniforms, maxIter),
        fractal4DDistance(p + e.yyx, uniforms, maxIter) - fractal4DDistance(p - e.yyx, uniforms, maxIter)
    ));
}

inline float fractal4DAmbientOcclusion(float3 p, float3 normal, constant FrameUniforms &uniforms, int maxIter) {
    float occlusion = 0.0f;
    float weight = 1.0f;

    for (int i = 1; i <= 5; i++) {
        const float h = 0.045f * float(i);
        const float d = fractal4DDistance(p + normal * h, uniforms, maxIter);
        occlusion += (h - d) * weight;
        weight *= 0.55f;
    }

    return saturate(1.0f - 1.65f * occlusion);
}

inline float shadertoy3DDistance(float3 p, int fractalType) {
    if (fractalType == 8) {
        return remnantXDistance(p);
    }
    if (fractalType == 19) {
        return syntopiaIFSDistance(p);
    }
    if (fractalType == 20) {
        return mengerFoldDistance(p);
    }
    if (fractalType == 22) {
        return mandelboxSweeperDistance(p);
    }
    if (fractalType == 24) {
        return cosmicPearlDistance(p);
    }
    return monsterDistance(p);
}

inline float3 shadertoy3DNormal(float3 p, int fractalType, float epsilon) {
    const float2 e = float2(max(epsilon, 0.00025f), 0.0f);
    return normalize(float3(
        shadertoy3DDistance(p + e.xyy, fractalType) - shadertoy3DDistance(p - e.xyy, fractalType),
        shadertoy3DDistance(p + e.yxy, fractalType) - shadertoy3DDistance(p - e.yxy, fractalType),
        shadertoy3DDistance(p + e.yyx, fractalType) - shadertoy3DDistance(p - e.yyx, fractalType)
    ));
}

inline float shadertoy3DAmbientOcclusion(float3 p, float3 normal, int fractalType) {
    float occlusion = 0.0f;
    float weight = 1.0f;

    for (int i = 1; i <= 5; i++) {
        const float h = 0.055f * float(i);
        const float d = shadertoy3DDistance(p + normal * h, fractalType);
        occlusion += (h - d) * weight;
        weight *= 0.55f;
    }

    return saturate(1.0f - 1.8f * occlusion);
}

inline float3 renderShadertoy3D(float2 uv, constant FrameUniforms &uniforms, int maxIter) {
    const float scale = max(fabs(uniforms.scaleHi + uniforms.scaleLo), 0.08f);
    const float3 target = float3(
        uniforms.centerHi.x + uniforms.centerLo.x,
        uniforms.centerHi.y + uniforms.centerLo.y,
        0.0f
    );
    const float distanceBias = uniforms.fractalType == 8 || uniforms.fractalType == 22 ? 1.15f : 0.92f;
    const float cameraDistance = clamp(uniforms.cameraDistance, 1.2f, 12.0f) * scale * distanceBias;
    const float3 orbit = rotateY(rotateX(float3(0.0f, 0.0f, cameraDistance), uniforms.cameraPitch), uniforms.rotation + 0.08f * uniforms.time);
    const float3 ro = target + orbit;
    const float3 forward = normalize(target - ro);
    const float3 right = normalize(cross(float3(0.0f, 1.0f, 0.0f), forward));
    const float3 up = cross(forward, right);
    const float3 rd = normalize(uv.x * right + uv.y * up + 1.45f * forward);

    const int raySteps = clamp(uniforms.rayMarchSteps, 32, 160);
    const float epsilon = clamp(uniforms.surfaceDetail * scale, 0.0001f, 0.018f);
    const float maxDistance = max(7.5f * scale, 5.5f);
    float t = 0.0f;
    float steps = 0.0f;
    bool hit = false;

    for (int i = 0; i < 160; i++) {
        if (i >= raySteps) {
            break;
        }

        const float3 p = ro + rd * t;
        const float d = shadertoy3DDistance(p, uniforms.fractalType);
        if (d < epsilon) {
            hit = true;
            break;
        }

        t += clamp(d, 0.0008f * scale, 0.22f * scale);
        steps += 1.0f;

        if (t > maxDistance) {
            break;
        }
    }

    if (!hit) {
        const float sky = pow(saturate(0.58f + 0.42f * rd.y), 1.6f);
        return mix(uniforms.backgroundColor.rgb * 0.65f, saturate(uniforms.backgroundColor.rgb + float3(0.08f, 0.10f, 0.16f)), sky);
    }

    const float3 p = ro + rd * t;
    const float3 normal = shadertoy3DNormal(p, uniforms.fractalType, epsilon * 2.0f);
    const float3 lightDirection = normalize(uniforms.fractalType == 8 || uniforms.fractalType == 22 ? float3(0.36f, 0.12f, 0.31f) : float3(-0.55f, 0.74f, 0.40f));
    const float diffuse = saturate(dot(normal, lightDirection));
    const float rim = pow(saturate(1.0f - dot(normal, -rd)), 2.4f);
    const float ao = shadertoy3DAmbientOcclusion(p, normal, uniforms.fractalType);
    const float orbitTone = uniforms.fractalType == 8 || uniforms.fractalType == 22 ? 24.0f + steps * 0.8f + length(p) * 10.0f : 18.0f + steps * 1.05f + length(abs(p)) * 7.0f;
    const float3 baseColor = paletteColor(orbitTone, uniforms.colorPalette);
    const float3 shaded = baseColor * (0.34f + 1.18f * diffuse) * ao + rim * (uniforms.fractalType == 8 || uniforms.fractalType == 22 ? 0.32f : 0.48f);
    const float fog = exp(-0.045f * t * t / max(scale, 0.2f));

    return mix(uniforms.backgroundColor.rgb * 0.72f, shaded, fog);
}

inline float3 renderMandelbulb3D(float2 uv, constant FrameUniforms &uniforms, int maxIter) {
    const float scale = max(fabs(uniforms.scaleHi + uniforms.scaleLo), 0.08f);
    const float3 target = float3(
        uniforms.centerHi.x + uniforms.centerLo.x,
        uniforms.centerHi.y + uniforms.centerLo.y,
        0.0f
    );
    const float cameraDistance = clamp(uniforms.cameraDistance, 1.2f, 12.0f) * scale;
    const float3 orbit = rotateY(rotateX(float3(0.0f, 0.0f, cameraDistance), uniforms.cameraPitch), uniforms.rotation);
    const float3 ro = target + orbit;
    const float3 forward = normalize(target - ro);
    const float3 right = normalize(cross(float3(0.0f, 1.0f, 0.0f), forward));
    const float3 up = cross(forward, right);
    const float3 rd = normalize(uv.x * right + uv.y * up + 1.55f * forward);

    const int raySteps = clamp(uniforms.rayMarchSteps, 32, 192);
    const int bulbIterations = clamp(maxIter / 180, 7, 22);
    const float epsilon = clamp(uniforms.surfaceDetail * scale, 0.00008f, 0.02f);
    const float maxDistance = max(8.0f * scale, 6.0f);
    const float bailout = clamp(uniforms.bailoutRadius, 2.0f, 64.0f);

    float t = 0.0f;
    float steps = 0.0f;
    bool hit = false;

    for (int i = 0; i < 192; i++) {
        if (i >= raySteps) {
            break;
        }

        const float3 p = ro + rd * t;
        const float d = mandelbulbDistance(p, uniforms.mandelbulbPower, bulbIterations, bailout);
        if (d < epsilon) {
            hit = true;
            break;
        }

        t += clamp(d, 0.001f * scale, 0.25f * scale);
        steps += 1.0f;

        if (t > maxDistance) {
            break;
        }
    }

    if (!hit) {
        const float sky = pow(saturate(0.65f + 0.35f * rd.y), 1.4f);
        const float3 background = uniforms.backgroundColor.rgb;
        return mix(background * 0.72f, saturate(background + float3(0.09f, 0.13f, 0.20f)), sky);
    }

    const float3 p = ro + rd * t;
    const float3 normal = mandelbulbNormal(p, uniforms.mandelbulbPower, bulbIterations, bailout, epsilon * 2.0f);
    const float3 lightDirection = normalize(float3(-0.45f, 0.72f, 0.52f));
    const float diffuse = saturate(dot(normal, lightDirection));
    const float rim = pow(saturate(1.0f - dot(normal, -rd)), 2.2f);
    const float ao = mandelbulbAmbientOcclusion(p, normal, uniforms.mandelbulbPower, bulbIterations, bailout);
    const float escapeTone = 18.0f + steps * 0.9f + t * 5.0f;
    const float3 baseColor = paletteColor(escapeTone, uniforms.colorPalette);
    const float3 shaded = baseColor * (0.38f + 1.1f * diffuse) * ao + rim * 0.45f;
    const float fog = exp(-0.035f * t * t / max(scale, 0.2f));

    return mix(uniforms.backgroundColor.rgb * 0.78f, shaded, fog);
}

inline float blackHoleHash(float2 p) {
    p = fract(p * float2(123.34f, 456.21f));
    p += dot(p, p + 45.32f);
    return fract(p.x * p.y);
}

inline float blackHoleSphereHit(float3 ro, float3 rd, float radius) {
    const float b = dot(ro, rd);
    const float c = dot(ro, ro) - radius * radius;
    const float h = b * b - c;
    if (h < 0.0f) {
        return -1.0f;
    }

    const float t = -b - sqrt(h);
    return t > 0.0f ? t : -1.0f;
}

inline float3 blackHoleStarField(float3 rd, float3 background) {
    const float2 cell = floor(rd.xy / max(0.0001f, 1.0f + rd.z) * 420.0f);
    const float seed = blackHoleHash(cell);
    const float star = smoothstep(0.996f, 1.0f, seed);
    const float sky = pow(saturate(0.55f + 0.45f * rd.y), 1.6f);
    return mix(background * 0.36f, background * 0.72f + float3(0.035f, 0.055f, 0.095f), sky) + star * float3(0.7f, 0.82f, 1.0f);
}

inline float3 shadertoySourceStarField(float2 uv, float time, float3 tint) {
    const float2 p = uv * float2(1.0f, 0.72f);
    const float2 cell = floor(p * 360.0f);
    const float seed = blackHoleHash(cell);
    const float star = smoothstep(0.992f, 1.0f, seed);
    const float twinkle = 0.68f + 0.32f * sin(time * 1.7f + seed * 37.0f);
    const float dust = fbm2D(uv * 2.4f + float2(0.03f * time, -0.02f * time));
    return float3(0.004f, 0.007f, 0.015f) + tint * (0.025f * dust + star * twinkle);
}

inline float galaxySceneNoise(float3 p) {
    const float3 cell = floor(p);
    const float3 local = fract(p);
    const float3 u = local * local * (3.0f - 2.0f * local);
    const float n000 = blackHoleHash(cell.xy + cell.z * 17.0f);
    const float n100 = blackHoleHash(cell.xy + float2(1.0f, 0.0f) + cell.z * 17.0f);
    const float n010 = blackHoleHash(cell.xy + float2(0.0f, 1.0f) + cell.z * 17.0f);
    const float n110 = blackHoleHash(cell.xy + float2(1.0f, 1.0f) + cell.z * 17.0f);
    const float n001 = blackHoleHash(cell.xy + (cell.z + 1.0f) * 17.0f);
    const float n101 = blackHoleHash(cell.xy + float2(1.0f, 0.0f) + (cell.z + 1.0f) * 17.0f);
    const float n011 = blackHoleHash(cell.xy + float2(0.0f, 1.0f) + (cell.z + 1.0f) * 17.0f);
    const float n111 = blackHoleHash(cell.xy + float2(1.0f, 1.0f) + (cell.z + 1.0f) * 17.0f);
    const float nx00 = mix(n000, n100, u.x);
    const float nx10 = mix(n010, n110, u.x);
    const float nx01 = mix(n001, n101, u.x);
    const float nx11 = mix(n011, n111, u.x);
    return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

inline float3 renderGalaxyUniverses3DScene(float2 uv, constant FrameUniforms &uniforms) {
    float2 st = float2(
        uv.x * uniforms.resolution.y / max(uniforms.resolution.x, 1.0f),
        uv.y
    ) * 0.5f;
    st += float2(
        uniforms.centerHi.x + uniforms.centerLo.x,
        uniforms.centerHi.y + uniforms.centerLo.y
    ) * 0.08f;

    const float t = uniforms.time * 0.1f + ((0.25f + 0.05f * sin(uniforms.time * 0.1f)) / (length(st) + 0.07f)) * 2.2f + uniforms.rotation;
    const float si = sin(t);
    const float co = cos(t);
    float v1 = 0.0f;
    float v2 = 0.0f;
    float v3 = 0.0f;
    float s = 0.0f;

    for (int i = 0; i < 90; i++) {
        float3 p = s * float3(st, 0.0f);
        p.xy = float2(p.x * co + p.y * si, -p.x * si + p.y * co);
        p += float3(0.22f, 0.3f, s - 1.5f - sin(uniforms.time * 0.13f) * 0.1f);

        for (int j = 0; j < 8; j++) {
            p = abs(p) / max(dot(p, p), 0.0001f) - 0.659f;
        }

        const float stLen = length(st);
        const float p2 = dot(p, p);
        v1 += p2 * 0.0015f * (1.8f + sin(stLen * 13.0f + 0.5f - uniforms.time * 0.2f));
        v2 += p2 * 0.0013f * (1.5f + sin(stLen * 14.5f + 1.2f - uniforms.time * 0.3f));
        v3 += length(p.xy * 10.0f) * 0.0003f;
        s += 0.035f;
    }

    const float len = length(st);
    v1 *= smoothstep(0.7f, 0.0f, len);
    v2 *= smoothstep(0.5f, 0.0f, len);
    v3 *= smoothstep(0.9f, 0.0f, len);

    const float3 col = float3(
        v3 * (1.5f + sin(uniforms.time * 0.2f) * 0.4f),
        (v1 + v3) * 0.3f,
        v2
    ) + smoothstep(0.2f, 0.0f, len) * 0.85f + smoothstep(0.0f, 0.6f, v3) * 0.3f;

    return min(pow(abs(col), float3(1.2f)), float3(1.0f));
}

inline float blackHoleKerrSchildRadius(float3 p, float spinRs) {
    const float a2 = spinRs * spinRs;
    const float r2 = dot(p, p);
    const float y2 = p.y * p.y;
    const float term = sqrt(max((r2 - a2) * (r2 - a2) + 4.0f * a2 * y2, 0.0f));
    return sqrt(max(0.5f * (r2 - a2 + term), 0.0001f));
}

inline float4 blackHoleDiskSample(float3 p, float diskInner, float diskOuter, float time, float scale, int fractalType) {
    const float diskRadius = length(p.xz);
    if (diskRadius <= diskInner || diskRadius >= diskOuter) {
        return float4(0.0f);
    }

    const float angle = atan2(p.z, p.x);
    const float radial = (diskRadius - diskInner) / max(diskOuter - diskInner, 0.0001f);
    const float innerGlow = pow(saturate(1.0f - radial), 1.8f);
    const float outerFade = 1.0f - smoothstep(0.72f, 1.0f, radial);
    const float innerEdge = smoothstep(0.0f, 0.08f, radial);
    const float fineRings = 0.72f + 0.28f * sin(36.0f * log(max(diskRadius / scale, 1.001f)) - time * 2.2f);
    const float turbulence = 0.74f + 0.26f * blackHoleHash(floor(float2(angle * 18.0f, diskRadius / scale * 7.0f)));
    const float lane = fineRings * turbulence;
    const float2 flowDirection = normalize(float2(-p.z, p.x));
    const float2 viewFlow = normalize(float2(0.72f, -0.28f));
    const float doppler = 0.62f + 0.72f * saturate(dot(flowDirection, viewFlow));
    const float3 ember = float3(1.0f, 0.28f, 0.035f);
    const float3 gold = fractalType == 46 ? float3(0.92f, 0.64f, 0.36f) : float3(1.0f, 0.74f, 0.28f);
    const float3 whiteHot = float3(1.0f, 0.96f, 0.78f);
    const float3 diskColor = mix(mix(ember, gold, innerGlow), whiteHot, innerGlow * innerGlow) * (0.58f + 2.5f * innerGlow) * doppler * lane;
    const float alpha = saturate(innerEdge * outerFade * (0.34f + 0.58f * innerGlow) * lane);
    return float4(diskColor, alpha);
}

inline float3 blackHoleScreenSignature(float2 uv, float time, int fractalType) {
    const bool relativisticLike = fractalType == 46;

    const float spin = relativisticLike ? 0.56f : 0.0f;
    const float2 p = uv * float2(1.0f, 0.82f);
    const float r = length(p);
    const float angle = atan2(p.y, p.x);
    const float horizon = 0.225f;
    const float photon = relativisticLike ? 0.33f : 0.35f;
    const float frameTwist = spin * 0.11f * exp(-r * 3.8f);
    const float diskCurve = 0.12f * sin(p.x * 3.1f + frameTwist * 4.0f) * exp(-abs(p.x) * 2.0f);
    const float diskY = p.y + diskCurve;
    const float diskRadial = abs(p.x);
    const float diskMask = smoothstep(0.18f, 0.46f, diskRadial) * (1.0f - smoothstep(1.3f, 1.85f, diskRadial));
    const float diskThickness = relativisticLike ? 0.055f : 0.050f;
    const float diskLane = exp(-pow(diskY / diskThickness, 2.0f)) * diskMask;
    const float laneNoise = 0.76f + 0.24f * sin(30.0f * log(max(diskRadial, 0.08f)) - time * 2.3f + angle * 2.0f);
    const float doppler = 0.65f + 0.58f * saturate(dot(normalize(float2(-p.y, p.x) + 0.001f), normalize(float2(0.82f, -0.22f))));
    const float3 inner = float3(1.0f, 0.83f, 0.48f);
    const float3 outer = relativisticLike ? float3(0.84f, 0.50f, 0.26f) : float3(1.0f, 0.36f, 0.06f);
    float3 color = mix(outer, inner, exp(-diskRadial * 1.8f)) * diskLane * laneNoise * doppler * 2.2f;

    const float primaryRing = exp(-pow((r - photon) / 0.014f, 2.0f));
    const float glowRing = exp(-pow((r - photon * 1.08f) / 0.055f, 2.0f));
    const float secondary = relativisticLike ? exp(-pow((r - photon * 1.35f) / 0.026f, 2.0f)) : 0.0f;
    const float asymmetric = 0.78f + 0.42f * saturate(cos(angle - 0.3f) * spin);
    color += primaryRing * asymmetric * float3(5.0f, 2.7f, 0.86f);
    color += glowRing * float3(0.68f, 0.34f, 0.13f);
    color += secondary * float3(2.0f, 1.1f, 0.5f);

    const float shadow = 1.0f - smoothstep(horizon, horizon + 0.025f, r);
    color = mix(color, float3(0.0f), shadow);
    const float lensDark = 1.0f - 0.55f * exp(-pow((r - horizon * 1.25f) / 0.08f, 2.0f));
    return color * lensDark;
}

inline float3 blackHoleJetEmission(float3 p, float scale, float time, int fractalType) {
    return float3(0.0f);
}

inline float2 shadertoy3dSyzDRotate2D(float2 p, float angle) {
    const float c = cos(angle);
    const float s = sin(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

inline float3 shadertoy3dSyzDRotateAroundAxis(float3 v, float3 axis, float angle) {
    const float c = cos(angle);
    const float s = sin(angle);
    return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0f - c);
}

inline float shadertoy3dSyzDHash(float p) {
    p = fract(p * 0.011f);
    p *= p + 7.5f;
    p *= p + p;
    return fract(p);
}

inline float shadertoy3dSyzDNoise(float3 x) {
    const float3 st = float3(110.0f, 241.0f, 171.0f);
    const float3 i = floor(x);
    const float3 f = fract(x);
    const float n = dot(i, st);
    const float3 u = f * f * (3.0f - 2.0f * f);

    const float x00 = mix(shadertoy3dSyzDHash(n), shadertoy3dSyzDHash(n + 110.0f), u.x);
    const float x10 = mix(shadertoy3dSyzDHash(n + 241.0f), shadertoy3dSyzDHash(n + 351.0f), u.x);
    const float x01 = mix(shadertoy3dSyzDHash(n + 171.0f), shadertoy3dSyzDHash(n + 281.0f), u.x);
    const float x11 = mix(shadertoy3dSyzDHash(n + 412.0f), shadertoy3dSyzDHash(n + 522.0f), u.x);
    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

inline float shadertoy3dSyzDFbm(float3 x) {
    float v = 0.0f;
    float a = 0.5f;
    const float3 shift = float3(100.0f);

    for (int i = 0; i < 4; i++) {
        v += a * shadertoy3dSyzDNoise(x);
        x = x * 2.5f + shift;
        a *= 0.5f;
    }

    return v;
}

inline float3 shadertoy3dSyzDBackground(float3 rd) {
    const float3 galaxyCenter = float3(0.0f, 0.0f, 1.0f);
    const float band = 1.0f - abs(rd.y - galaxyCenter.y);
    float3 color = float3(pow(max(band, 0.0f), 8.0f))
        * shadertoy3dSyzDFbm((rd + float3(2.0f, 1.0f, -4.0f)) * 10.0f)
        * 0.5f;

    color *= clamp(dot(rd.xz, galaxyCenter.xz), 0.0f, 1.0f);
    color *= 0.5f / max(distance(float3(rd.x / 2.5f, rd.y * 6.0f, rd.z), galaxyCenter), 0.001f);

    const float centerDistance = max(distance(rd, galaxyCenter), 0.001f);
    color.r *= 1.0f / centerDistance;
    color.b *= centerDistance;
    color.g = (color.r + color.b) * 0.25f;
    color /= max(shadertoy3dSyzDFbm(-rd), 0.05f);

    color = clamp(color, float3(0.0f), float3(1.0f));
    if (abs(galaxyCenter.y - rd.y) <= 0.1f) {
        color -= shadertoy3dSyzDFbm(rd * 30.0f)
            * float3(1.0f - abs(galaxyCenter.y - rd.y) * 10.0f)
            * float3(0.2f, 0.8f, 0.9f)
            * pow(clamp(dot(rd, galaxyCenter), 0.0f, 1.0f), 1.5f);
    }

    float stars = shadertoy3dSyzDFbm(rd * 100.0f);
    stars = pow(stars * 1.18f, 15.0f);
    color += float3(stars);
    color.b += 0.05f * length(color) + 0.2f;

    return saturate(color);
}

inline float3 renderRelativisticBlackHole3dSyzD(float2 uv, constant FrameUniforms &uniforms) {
    float2 shaderUV = uv * 0.5f;
    float3 ro = float3(5.0f, 0.0f, -10.0f);
    float3 rd = normalize(float3(shaderUV, 1.0f));
    const float time = uniforms.time;
    float3 color = float3(0.0f);

    float4 blackHole = float4(3.0f, 0.0f, 0.0f, 100000.0f);
    const float orbitRadius = 4.0f;
    blackHole.x += cos(time) * orbitRadius;
    blackHole.y += sin(time) * orbitRadius;

    rd.xy = shadertoy3dSyzDRotate2D(rd.xy, 0.7f * sin(time * 0.25f) + uniforms.rotation * 0.12f);
    rd.xz = shadertoy3dSyzDRotate2D(rd.xz, 0.2f * sin(time * 0.25f) + uniforms.cameraPitch * 0.08f);

    const float3 cameraForward = float3(0.0f, 0.0f, 1.0f);
    const float3 blackHoleVector = blackHole.xyz - ro;
    const float blackHoleDistance = max(length(blackHoleVector), 0.001f);
    const float angleToBlackHole = acos(clamp(dot(blackHoleVector, cameraForward) / blackHoleDistance, -1.0f, 1.0f));
    const float3 rawAxis = cross(blackHoleVector, cameraForward);
    const float axisLength = length(rawAxis);
    const float3 rotationAxis = axisLength > 0.0001f ? rawAxis / axisLength : float3(0.0f, 1.0f, 0.0f);

    rd = shadertoy3dSyzDRotateAroundAxis(rd, rotationAxis, -angleToBlackHole * 0.8f + sin(time) * 0.1f);

    const float closestT = dot(rd, blackHole.xyz - ro);
    const float3 closestVector = ro + rd * closestT - blackHole.xyz;
    const float closestDistance = length(closestVector);

    const float gravitationalConstant = 0.01f;
    const float lightSpeed = 100.0f;
    const float schwarzschildRadius = 2.0f * gravitationalConstant * blackHole.w / (lightSpeed * lightSpeed);

    if (closestDistance >= schwarzschildRadius) {
        const float3 axis = normalize(cross(closestVector, rd) + float3(0.00001f));
        const float deflection = 4.0f * blackHole.w * gravitationalConstant / (closestDistance * lightSpeed * lightSpeed);
        rd = shadertoy3dSyzDRotateAroundAxis(rd, axis, deflection);
        color = shadertoy3dSyzDBackground(rd);
    }

    return color;
}

inline float3 renderBlackHole3D(float2 uv, constant FrameUniforms &uniforms) {
    const float scale = max(fabs(uniforms.scaleHi + uniforms.scaleLo), 0.35f);
    const float3 target = float3(
        uniforms.centerHi.x + uniforms.centerLo.x,
        uniforms.centerHi.y + uniforms.centerLo.y,
        0.0f
    );

    const bool relativisticLike = uniforms.fractalType == 46;
    const float spinStar = relativisticLike ? 0.56f : 0.0f;
    const float chargeStar = 0.0f;
    const float spinRs = 0.5f * spinStar * scale;
    const float horizonRs = 0.5f * (1.0f + sqrt(max(0.0f, 1.0f - spinStar * spinStar - chargeStar * chargeStar)));
    const float eventRadius = horizonRs * scale;
    const float photonRadius = (relativisticLike ? 1.36f : 1.5f) * scale;
    const float diskInner = 3.0f * scale;
    const float diskOuter = (relativisticLike ? 22.0f : 14.0f) * scale;
    const float cameraDistance = clamp(uniforms.cameraDistance, 6.0f, 160.0f) * scale;
    const float3 orbit = rotateY(rotateX(float3(0.0f, 0.0f, cameraDistance), uniforms.cameraPitch), uniforms.rotation);
    const float3 ro = target + orbit;
    const float3 forward = normalize(target - ro);
    const float3 right = normalize(cross(float3(0.0f, 1.0f, 0.0f), forward));
    const float3 up = cross(forward, right);
    const float focalLength = relativisticLike ? 1.34f : 1.42f;
    const float3 rd = normalize(uv.x * right + uv.y * up + focalLength * forward);

    float3 p = ro - target;
    float3 dir = rd;
    float3 diskAccum = float3(0.0f);
    float3 jetAccum = float3(0.0f);
    float diskAlpha = 0.0f;
    float minRadius = 1e6f;
    float minTangent = 1.0f;
    bool absorbed = false;

    const int raySteps = clamp(uniforms.rayMarchSteps, 72, 192);
    for (int i = 0; i < 192; i++) {
        if (i >= raySteps) {
            break;
        }

        const float radius = max(blackHoleKerrSchildRadius(p, spinRs), 0.0001f);
        minRadius = min(minRadius, radius);
        minTangent = min(minTangent, abs(dot(normalize(p), dir)));

        if (radius < eventRadius) {
            absorbed = true;
            break;
        }

        const float stepSize = clamp(radius * 0.034f, 0.028f * scale, 1.2f * scale);
        jetAccum += blackHoleJetEmission(p, scale, uniforms.time, uniforms.fractalType) * (stepSize / scale) * (1.0f - min(diskAlpha, 0.85f));
        const float bendScale = relativisticLike ? 0.128f : 0.11f;
        const float massTerm = 1.0f - chargeStar * chargeStar * 0.18f / max(radius / scale, 0.35f);
        const float bend = bendScale * massTerm * (scale * scale) / (radius * radius + eventRadius * eventRadius * 0.08f) * (stepSize / scale);
        const float3 radialDirection = normalize(float3(p.x, p.y * (1.0f + spinStar * spinStar * 0.35f), p.z));
        const float3 frameDragging = normalize(cross(float3(0.0f, 1.0f, 0.0f), radialDirection) + 0.001f) * (spinStar * 0.030f) * pow(saturate(scale / radius), 1.25f);
        dir = normalize(dir - radialDirection * bend + frameDragging);

        const float3 nextP = p + dir * stepSize;
        if ((p.y <= 0.0f && nextP.y > 0.0f) || (p.y >= 0.0f && nextP.y < 0.0f)) {
            const float crossing = saturate(p.y / (p.y - nextP.y));
            const float3 diskPoint = mix(p, nextP, crossing);
            const float4 diskSample = blackHoleDiskSample(diskPoint, diskInner, diskOuter, uniforms.time, scale, uniforms.fractalType);
            const float nearShadow = 1.0f - smoothstep(eventRadius * 1.03f, eventRadius * 1.7f, length(diskPoint));
            const float sampleAlpha = diskSample.a * (1.0f - nearShadow) * (1.0f - diskAlpha);
            diskAccum += diskSample.rgb * sampleAlpha;
            diskAlpha += sampleAlpha;
        }

        p = nextP;
        if (length(p) > diskOuter * 3.2f && dot(p, dir) > 0.0f && i > 24) {
            break;
        }
    }

    float3 color = blackHoleStarField(dir, float3(0.006f, 0.009f, 0.016f));
    if (diskAlpha > 0.001f) {
        color = mix(color, diskAccum / max(diskAlpha, 0.001f), saturate(diskAlpha));
    }
    color += jetAccum * 0.16f;

    const float sharpRing = exp(-pow((minRadius - photonRadius) / (0.032f * scale), 2.0f)) * (1.0f - smoothstep(0.0f, 0.22f, minTangent));
    const float warmRing = exp(-pow((minRadius - photonRadius * 1.08f) / (0.13f * scale), 2.0f));
    const float secondaryRing = exp(-pow((minRadius - photonRadius * 1.34f) / (0.048f * scale), 2.0f)) * (relativisticLike ? 1.0f : 0.0f);
    const float tertiaryRing = 0.0f;
    const float lensGlow = exp(-pow((minRadius - eventRadius * 2.45f) / (0.72f * scale), 2.0f)) * (0.22f + 0.42f * diskAlpha);
    const float shadow = 1.0f - smoothstep(eventRadius * 1.02f, eventRadius * 2.7f, minRadius);
    color *= 1.0f - 0.96f * shadow;
    color += sharpRing * float3(8.0f, 4.6f, 1.65f);
    color += warmRing * float3(1.15f, 0.54f, 0.16f);
    color += secondaryRing * float3(2.4f, 1.34f, 0.62f);
    color += tertiaryRing * float3(0.9f, 0.46f, 0.2f);
    color += lensGlow * float3(0.38f, 0.22f, 0.11f);

    if (absorbed) {
        color *= 0.025f;
        color += sharpRing * float3(4.4f, 2.0f, 0.52f);
    }

    const float3 signature = blackHoleScreenSignature(uv, uniforms.time, uniforms.fractalType);
    return max(color * 0.62f, signature);
}

struct WxKerrGeometry {
    float r;
    float r2;
    float a2;
    float f;
    float3 gradR;
    float3 gradF;
    float4 lUp;
    float4 lDown;
    float invR2A2;
    float invDenF;
    float numF;
};

struct WxState {
    float4 x;
    float4 p;
};

struct WxCameraState {
    float3 position;
    float3 right;
    float3 up;
    float3 forward;
    float universeSign;
    bool valid;
};

inline float wxCubicInterpolate(float x) {
    return x * x * (3.0f - 2.0f * x);
}

inline float wxKerrSchildRadius(float3 p, float physicalSpinA, float rSign) {
    if (abs(physicalSpinA) < 1e-7f) {
        return rSign * length(p);
    }

    const float a2 = physicalSpinA * physicalSpinA;
    const float rho2 = dot(p.xz, p.xz);
    const float y2 = p.y * p.y;
    const float b = rho2 + y2 - a2;
    const float det = sqrt(max(b * b + 4.0f * a2 * y2, 0.0f));
    const float r2 = b >= 0.0f ? 0.5f * (b + det) : (2.0f * a2 * y2) / max(det - b, 1e-20f);
    return rSign * sqrt(max(r2, 0.0f));
}

inline float wxKeplerianAngularVelocity(float radius, float physicalSpinA, float physicalQ) {
    const float mass = 0.5f;
    const float mrMinusQ2 = mass * radius - physicalQ * physicalQ;
    if (mrMinusQ2 < 0.0f) {
        return 0.0f;
    }

    const float sqrtTerm = sqrt(mrMinusQ2);
    const float denominator = radius * radius + 0.5f * physicalSpinA * sqrtTerm;
    return sqrtTerm / max(denominator, 1e-6f);
}

inline WxKerrGeometry wxComputeGeometryScalars(float3 x, float physicalSpinA, float physicalQ, float fade, float rSign) {
    WxKerrGeometry geo;
    geo.a2 = physicalSpinA * physicalSpinA;

    if (abs(physicalSpinA) < 1e-7f) {
        geo.r = rSign * max(length(x), 1e-6f);
        geo.r2 = geo.r * geo.r;
        const float invR = 1.0f / max(abs(geo.r), 1e-6f);
        const float invR2 = invR * invR;
        geo.lUp = float4(x * invR, -1.0f);
        geo.lDown = float4(x * invR, 1.0f);
        geo.numF = geo.r - physicalQ * physicalQ;
        geo.f = (invR - physicalQ * physicalQ * invR2) * fade;
        geo.invR2A2 = invR2;
        geo.invDenF = 0.0f;
        geo.gradR = float3(0.0f);
        geo.gradF = float3(0.0f);
        return geo;
    }

    geo.r = wxKerrSchildRadius(x, physicalSpinA, rSign);
    geo.r2 = geo.r * geo.r;
    const float r3 = geo.r2 * geo.r;
    const float y2 = x.y * x.y;
    geo.invR2A2 = 1.0f / max(geo.r2 + geo.a2, 1e-9f);

    const float lx = (geo.r * x.x - physicalSpinA * x.z) * geo.invR2A2;
    const float ly = x.y / max(geo.r, 1e-6f);
    const float lz = (geo.r * x.z + physicalSpinA * x.x) * geo.invR2A2;
    geo.lUp = float4(lx, ly, lz, -1.0f);
    geo.lDown = float4(lx, ly, lz, 1.0f);

    geo.numF = r3 - physicalQ * physicalQ * geo.r2;
    const float denF = geo.r2 * geo.r2 + geo.a2 * y2;
    geo.invDenF = 1.0f / max(denF, 1e-20f);
    geo.f = geo.numF * geo.invDenF * fade;
    geo.gradR = float3(0.0f);
    geo.gradF = float3(0.0f);
    return geo;
}

inline void wxComputeGeometryGradients(float3 x, float physicalSpinA, float physicalQ, float fade, thread WxKerrGeometry &geo) {
    const float invR = 1.0f / max(abs(geo.r), 1e-6f);

    if (abs(physicalSpinA) < 1e-7f) {
        const float invR2 = invR * invR;
        geo.gradR = x * invR;
        const float dfDr = (-1.0f + 2.0f * physicalQ * physicalQ * invR) * invR2 * fade;
        geo.gradF = dfDr * geo.gradR;
        return;
    }

    const float d = 2.0f * geo.r2 - dot(x, x) + geo.a2;
    const float denom = abs(geo.r * d) < 1e-9f ? sign(geo.r * d + 1e-9f) * 1e-9f : geo.r * d;
    geo.gradR = float3(
        x.x * geo.r2,
        x.y * (geo.r2 + geo.a2),
        x.z * geo.r2
    ) / denom;

    const float y2 = x.y * x.y;
    const float termM = -geo.r2 * geo.r2 * geo.r;
    const float termQ = 2.0f * physicalQ * physicalQ * geo.r2 * geo.r2;
    const float termMa = 3.0f * geo.a2 * geo.r * y2;
    const float termQa = -2.0f * physicalQ * physicalQ * geo.a2 * y2;
    const float dfDr = geo.r * (termM + termQ + termMa + termQa) * geo.invDenF * geo.invDenF;
    const float dfDy = -(geo.numF * 2.0f * geo.a2 * x.y) * geo.invDenF * geo.invDenF;

    geo.gradF = dfDr * geo.gradR;
    geo.gradF.y += dfDy;
    geo.gradF *= fade;
}

inline float4 wxRaiseIndex(float4 pCov, WxKerrGeometry geo) {
    const float4 pFlat = float4(pCov.xyz, -pCov.w);
    const float lDotP = dot(geo.lUp, pCov);
    return pFlat - geo.f * lDotP * geo.lUp;
}

inline float4 wxLowerIndex(float4 pContra, WxKerrGeometry geo) {
    const float4 pFlat = float4(pContra.xyz, -pContra.w);
    const float lDotP = dot(geo.lDown, pContra);
    return pFlat + geo.f * lDotP * geo.lDown;
}

inline float4 wxInitialMomentum(float3 rayDir, float4 x, float physicalSpinA, float physicalQ, float fade, float universeSign) {
    const WxKerrGeometry geo = wxComputeGeometryScalars(x.xyz, physicalSpinA, physicalQ, fade, universeSign);
    const float gTT = -1.0f + geo.f;
    const float4 uUp = float4(0.0f, 0.0f, 0.0f, 1.0f / sqrt(max(-gTT, 1e-8f)));
    const float4 uDown = wxLowerIndex(uUp, geo);

    float3 radial = -normalize(x.xyz);
    float3 worldUp = abs(dot(radial, float3(0.0f, 1.0f, 0.0f))) > 0.999f ? float3(1.0f, 0.0f, 0.0f) : float3(0.0f, 1.0f, 0.0f);
    float3 phi = normalize(cross(worldUp, radial));
    float3 theta = normalize(cross(phi, radial));

    const float kr = dot(rayDir, radial);
    const float kt = dot(rayDir, theta);
    const float kp = dot(rayDir, phi);

    float4 e1 = float4(radial, 0.0f);
    e1 += dot(e1, uDown) * uUp;
    float4 e1Down = wxLowerIndex(e1, geo);
    e1 /= sqrt(max(dot(e1, e1Down), 1e-8f));
    e1Down = wxLowerIndex(e1, geo);

    float4 e2 = float4(theta, 0.0f);
    e2 += dot(e2, uDown) * uUp;
    e2 -= dot(e2, e1Down) * e1;
    float4 e2Down = wxLowerIndex(e2, geo);
    e2 /= sqrt(max(dot(e2, e2Down), 1e-8f));
    e2Down = wxLowerIndex(e2, geo);

    float4 e3 = float4(phi, 0.0f);
    e3 += dot(e3, uDown) * uUp;
    e3 -= dot(e3, e1Down) * e1;
    e3 -= dot(e3, e2Down) * e2;
    float4 e3Down = wxLowerIndex(e3, geo);
    e3 /= sqrt(max(dot(e3, e3Down), 1e-8f));

    const float4 pUp = uUp - (kr * e1 + kt * e2 + kp * e3);
    return wxLowerIndex(pUp, geo);
}

inline void wxApplyHamiltonianCorrection(thread float4 &p, float4 x, float energy, float physicalSpinA, float physicalQ, float fade, float rSign) {
    p.w = -energy;
    const WxKerrGeometry geo = wxComputeGeometryScalars(x.xyz, physicalSpinA, physicalQ, fade, rSign);
    const float lDotPS = dot(geo.lUp.xyz, p.xyz);
    const float coeffA = dot(p.xyz, p.xyz) - geo.f * lDotPS * lDotPS;
    const float coeffB = 2.0f * geo.f * lDotPS * p.w;
    const float coeffC = -p.w * p.w * (1.0f + geo.f);
    const float disc = coeffB * coeffB - 4.0f * coeffA * coeffC;

    if (disc >= 0.0f && abs(coeffA) > 1e-9f) {
        const float sqrtDisc = sqrt(disc);
        const float k1 = (-coeffB + sqrtDisc) / (2.0f * coeffA);
        const float k2 = (-coeffB - sqrtDisc) / (2.0f * coeffA);
        const float k = abs(k1 - 1.0f) < abs(k2 - 1.0f) ? k1 : k2;
        p.xyz *= mix(k, 1.0f, clamp(abs(k - 1.0f) / 0.1f - 1.0f, 0.0f, 1.0f));
    }
}

inline WxState wxDerivatives(WxState s, float physicalSpinA, float physicalQ, float fade, thread WxKerrGeometry &geo) {
    wxComputeGeometryGradients(s.x.xyz, physicalSpinA, physicalQ, fade, geo);

    WxState deriv;
    const float lDotP = dot(geo.lUp, s.p);
    deriv.x = float4(s.p.xyz, -s.p.w) - geo.f * lDotP * geo.lUp;

    const float3 gradA = (-2.0f * geo.r * geo.invR2A2) * geo.invR2A2 * geo.gradR;
    const float rxAz = geo.r * s.x.x - physicalSpinA * s.x.z;
    const float rzAx = geo.r * s.x.z + physicalSpinA * s.x.x;

    float3 dNumLx = s.x.x * geo.gradR;
    dNumLx.x += geo.r;
    dNumLx.z -= physicalSpinA;
    const float3 gradLx = geo.invR2A2 * dNumLx + rxAz * gradA;

    const float3 gradLy = (geo.r * float3(0.0f, 1.0f, 0.0f) - s.x.y * geo.gradR) / max(geo.r2, 1e-8f);

    float3 dNumLz = s.x.z * geo.gradR;
    dNumLz.z += geo.r;
    dNumLz.x += physicalSpinA;
    const float3 gradLz = geo.invR2A2 * dNumLz + rzAx * gradA;

    const float3 pDotGradL = s.p.x * gradLx + s.p.y * gradLy + s.p.z * gradLz;
    const float3 force = 0.5f * ((lDotP * lDotP) * geo.gradF + (2.0f * geo.f * lDotP) * pDotGradL);
    deriv.p = float4(force, 0.0f);
    return deriv;
}

inline float wxIntermediateSign(float4 startX, float4 currentX, float currentSign, float physicalSpinA) {
    if (startX.y * currentX.y < 0.0f) {
        const float t = startX.y / max(startX.y - currentX.y, 1e-8f);
        const float rho = length(mix(startX.xz, currentX.xz, t));
        if (rho < abs(physicalSpinA)) {
            return -currentSign;
        }
    }
    return currentSign;
}

inline void wxStepGeodesicRK4(thread float4 &x, thread float4 &p, float energy, float dt, float physicalSpinA, float physicalQ, float fade, float rSign, WxKerrGeometry geo0, WxState k1) {
    const WxState s0 = WxState { x, p };

    WxState s1 = WxState { s0.x + 0.5f * dt * k1.x, s0.p + 0.5f * dt * k1.p };
    float sign1 = wxIntermediateSign(s0.x, s1.x, rSign, physicalSpinA);
    WxKerrGeometry geo1 = wxComputeGeometryScalars(s1.x.xyz, physicalSpinA, physicalQ, fade, sign1);
    WxState k2 = wxDerivatives(s1, physicalSpinA, physicalQ, fade, geo1);

    WxState s2 = WxState { s0.x + 0.5f * dt * k2.x, s0.p + 0.5f * dt * k2.p };
    float sign2 = wxIntermediateSign(s0.x, s2.x, rSign, physicalSpinA);
    WxKerrGeometry geo2 = wxComputeGeometryScalars(s2.x.xyz, physicalSpinA, physicalQ, fade, sign2);
    WxState k3 = wxDerivatives(s2, physicalSpinA, physicalQ, fade, geo2);

    WxState s3 = WxState { s0.x + dt * k3.x, s0.p + dt * k3.p };
    float sign3 = wxIntermediateSign(s0.x, s3.x, rSign, physicalSpinA);
    WxKerrGeometry geo3 = wxComputeGeometryScalars(s3.x.xyz, physicalSpinA, physicalQ, fade, sign3);
    WxState k4 = wxDerivatives(s3, physicalSpinA, physicalQ, fade, geo3);

    float4 finalX = s0.x + (dt / 6.0f) * (k1.x + 2.0f * k2.x + 2.0f * k3.x + k4.x);
    float4 finalP = s0.p + (dt / 6.0f) * (k1.p + 2.0f * k2.p + 2.0f * k3.p + k4.p);
    const float finalSign = wxIntermediateSign(s0.x, finalX, rSign, physicalSpinA);
    if (finalSign > 0.0f) {
        wxApplyHamiltonianCorrection(finalP, finalX, energy, physicalSpinA, physicalQ, fade, finalSign);
    }
    x = finalX;
    p = finalP;
}

inline float3 wxKelvinToRgb(float kelvin) {
    if (kelvin < 400.01f) {
        return float3(0.0f);
    }

    const float t = (kelvin - 6500.0f) / (6500.0f * kelvin * 2.2f);
    float3 color = float3(exp(2.05539304e4f * t), exp(2.63463675e4f * t), exp(3.30145739e4f * t));
    float brightnessScale = 1.0f / max(max(1.5f * color.r, color.g), color.b);
    if (kelvin < 1000.0f) {
        brightnessScale *= (kelvin - 400.0f) / 600.0f;
    }
    return max(color * brightnessScale, float3(0.0f));
}

inline float4 wxAccumulate(float4 baseColor, float4 emission) {
    const float transmittance = max(1.0f - baseColor.a, 0.0f);
    baseColor.rgb += emission.rgb * transmittance;
    baseColor.a += emission.a * transmittance;
    return baseColor;
}

inline float4 wxDiskAndJetEmission(
    float4 baseColor,
    float stepLength,
    float4 rayPos,
    float4 lastRayPos,
    float3 rayDir,
    float4 pCov,
    float energy,
    float physicalSpinA,
    float physicalQ,
    float thetaInShell,
    float time
) {
    float3 samplePos = 0.5f * (rayPos.xyz + lastRayPos.xyz);
    if (lastRayPos.y * rayPos.y < 0.0f) {
        const float t = clamp(lastRayPos.y / max(lastRayPos.y - rayPos.y, 1e-8f), 0.0f, 1.0f);
        samplePos = mix(lastRayPos.xyz, rayPos.xyz, t);
    }

    const float interRadius = 1.5f;
    const float outerRadius = 25.0f;
    const float thin = 0.75f;
    const float hopper = 0.24f;
    const float posR = wxKerrSchildRadius(samplePos, physicalSpinA, 1.0f);
    const float rho = length(samplePos.xz);
    const float posY = samplePos.y;
    const float geometricThin = thin + max(0.0f, (rho - 3.0f) * hopper);

    float4 result = baseColor;
    if (posR > interRadius && posR < outerRadius) {
        const float x = clamp((posR - interRadius) / max(outerRadius - interRadius, 1e-6f), 0.0f, 1.0f);
        const float densityShape = pow(max(x, 1e-5f), 0.9f) * pow(max(1.0f - x, 1e-5f), 1.5f) * 4.35f;
        const float thickness = max(geometricThin * densityShape, 1e-4f);
        const float vertical = exp(-pow(posY / thickness, 2.0f));

        if (vertical > 0.001f) {
            const float angle = atan2(samplePos.z, samplePos.x);
            const float logTheta = angle + 2.0f * log(max(posR, 1e-5f));
            const float rotR = posR + 0.083333f * (2.0f * time);
            const float turbulent = 0.42f + 1.20f * fbm2D(float2(0.14f * rotR - 0.035f * outerRadius * logTheta, 1.6f * logTheta + 0.03f * time));
            const float granular = 0.78f + 0.28f * fbm2D(float2(0.35f * posR, 2.5f * angle + 0.12f * time));
            const float omega = wxKeplerianAngularVelocity(max(posR, interRadius), physicalSpinA, physicalQ);
            const float pPhi = -samplePos.x * pCov.z + samplePos.z * pCov.x;
            const float invR = 1.0f / max(posR, 1e-6f);
            const float vPotential = invR - physicalQ * physicalQ * invR * invR;
            const float gTT = -(1.0f - vPotential);
            const float gTPhi = -physicalSpinA * vPotential;
            const float gPhiPhi = posR * posR + physicalSpinA * physicalSpinA + physicalSpinA * physicalSpinA * vPotential;
            const float normMetric = gTT + 2.0f * omega * gTPhi + omega * omega * gPhiPhi;
            const float uT = rsqrt(max(-normMetric, 0.01f));
            const float freqRatio = clamp(1.0f / max(uT * (energy - omega * pPhi), 1e-5f), 0.05f, 3.0f);
            const float temperature = pow(7.8e19f * pow(invR, 3.0f) * max(1.0f - sqrt(interRadius * invR), 1e-6f), 0.25f);
            const float3 thermal = wxKelvinToRgb(temperature * pow(freqRatio, 3.0f));
            const float photonBoost = 1.0f + 4.2f * clamp(0.3f * thetaInShell - 0.1f, 0.0f, 1.0f);

            float4 emission;
            emission.rgb = thermal * vertical * densityShape * turbulent * granular;
            emission.rgb *= (0.055f + 0.55f * exp(-5.0f * x)) * pow(freqRatio, 4.0f) * photonBoost;
            emission.rgb *= min(1.0f, 1.3f * (outerRadius - posR) / max(outerRadius - interRadius, 1e-6f));
            emission.a = vertical * densityShape * densityShape * (0.05f + 0.16f * turbulent);
            emission *= clamp(stepLength * 0.11f, 0.0f, 0.9f);
            result = wxAccumulate(result, emission);
        }
    }

    const float jetR = length(samplePos.xz);
    const float jetAbsY = abs(samplePos.y);
    if (jetAbsY > interRadius * 0.45f && jetAbsY < outerRadius * 1.65f) {
        const float cone = interRadius + 0.18f * jetAbsY;
        const float shell = exp(-pow((jetR - cone) / max(0.22f + 0.05f * jetAbsY, 1e-4f), 2.0f));
        const float core = exp(-jetR * jetR / max(0.14f + 0.0015f * jetAbsY * jetAbsY, 1e-4f));
        const float flow = 0.65f + 0.35f * fbm2D(float2(jetAbsY * 0.55f - time * 2.2f, atan2(samplePos.z, samplePos.x) * 2.0f));
        const float fade = smoothstep(0.8f, 3.5f, jetAbsY) * (1.0f - smoothstep(34.0f, outerRadius * 1.65f, jetAbsY));
        float4 emission = float4(float3(0.16f, 0.48f, 2.2f) * (0.85f * shell + 0.22f * core) * flow * fade, 0.0f);
        emission.rgb *= clamp(stepLength * 0.08f, 0.0f, 0.55f);
        result = wxAccumulate(result, emission);
    }

    return result;
}

inline float3 wxToneMap(float4 result, float shift) {
    const float sum = max(result.r + result.g + result.b, 1e-6f);
    const float3 factor = 3.0f * result.rgb / sum;
    const float bloomMax = max(8.0f, shift);
    const float3 safeColor = clamp(result.rgb, float3(0.0f), float3(0.995f));
    return min(-4.0f * log(1.0f - pow(safeColor, float3(2.2f))), bloomMax * factor);
}

inline WxCameraState wxDefaultCameraState(constant FrameUniforms &uniforms) {
    const float cameraYaw = uniforms.rotation * 0.5f;
    const float cameraScale = clamp(uniforms.cameraDistance / 36.0f, 0.65f, 2.0f);
    float3 pos = float3(-2.0f, -3.6f - uniforms.cameraPitch * 2.0f, 22.0f) * cameraScale;
    const float cy = cos(cameraYaw);
    const float sy = sin(cameraYaw);
    pos = float3(pos.x * cy - pos.z * sy, pos.y, pos.x * sy + pos.z * cy);

    const float3 target = float3(0.0f, 0.12f, 0.0f);
    const float3 forward = normalize(target - pos);
    const float3 right = normalize(cross(forward, float3(-0.5f, 1.0f, 0.0f)));
    const float3 up = normalize(cross(right, forward));
    return WxCameraState { pos, right, up, forward, 1.0f, true };
}

inline float4 wxReadStatePixel(texture2d<float, access::read> stateTexture, float2 resolution, int offset) {
    const uint x = uint(clamp(resolution.x - float(offset), 0.0f, resolution.x - 1.0f));
    return stateTexture.read(uint2(x, 0));
}

inline bool wxInputKeyDown(int keyMask, int bit) {
    return (keyMask & (1 << bit)) != 0;
}

inline float3 wxRotateAroundAxis(float3 v, float3 axis, float angle) {
    const float s = sin(angle);
    const float c = cos(angle);
    return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0f - c);
}

inline WxCameraState wxCameraStateFromBuffer(
    texture2d<float, access::read> stateTexture,
    constant FrameUniforms &uniforms
) {
    WxCameraState fallback = wxDefaultCameraState(uniforms);
    const float2 resolution = max(uniforms.resolution, float2(1.0f));

    const float4 upPixel = wxReadStatePixel(stateTexture, resolution, 1);
    const float4 rightPixel = wxReadStatePixel(stateTexture, resolution, 2);
    const float4 posPixel = wxReadStatePixel(stateTexture, resolution, 3);
    const float4 fwdPixel = wxReadStatePixel(stateTexture, resolution, 4);
    const float4 timePixel = wxReadStatePixel(stateTexture, resolution, 6);

    const bool valid = length(upPixel.xyz) > 0.1f
        && length(rightPixel.xyz) > 0.1f
        && length(fwdPixel.xyz) > 0.1f
        && length(posPixel.xyz) > 0.1f
        && timePixel.w > 0.5f;

    if (!valid) {
        return fallback;
    }

    float3 forward = normalize(fwdPixel.xyz);
    float3 right = normalize(rightPixel.xyz - dot(rightPixel.xyz, forward) * forward);
    float3 up = normalize(cross(right, forward));
    right = normalize(cross(forward, up));
    return WxCameraState {
        posPixel.xyz,
        right,
        up,
        forward,
        timePixel.y == 0.0f ? 1.0f : timePixel.y,
        true
    };
}

inline float3 renderShadertoyWxdfzjBase(float2 uv, constant FrameUniforms &uniforms, WxCameraState camera) {
    const float time = uniforms.time;
    const float physicalSpinA = 0.99f * 0.5f;
    const float physicalQ = 0.0f;
    const float horizonDiscrim = 0.25f - physicalSpinA * physicalSpinA - physicalQ * physicalQ;
    const float eventHorizonR = 0.5f + sqrt(max(horizonDiscrim, 0.0f));
    const float boundary = 501.0f;

    const float3 ro = camera.position;
    const float3 forward = normalize(camera.forward);
    const float3 right = normalize(camera.right);
    const float3 up = normalize(camera.up);
    const float fov = tan(60.0f * 0.0174532925199f * 0.5f);
    float3 rayDir = normalize(forward + fov * uv.x * right + fov * uv.y * up);

    float currentSign = camera.universeSign == 0.0f ? 1.0f : camera.universeSign;
    float4 x = float4(ro, 0.0f);
    float4 pCov = wxInitialMomentum(rayDir, x, physicalSpinA, physicalQ, 1.0f, currentSign);
    const float energy = max(-pCov.w, 1e-5f);
    float4 result = float4(0.0f);
    float minR = 1e6f;
    float lastR = wxKerrSchildRadius(x.xyz, physicalSpinA, currentSign);
    float thetaInShell = 0.0f;
    bool escaped = false;
    bool absorbed = false;
    const int raySteps = clamp(uniforms.rayMarchSteps, 96, 192);

    for (int i = 0; i < 192; i++) {
        if (i >= raySteps || result.a > 0.99f) {
            break;
        }

        float distanceToBlackHole = length(x.xyz);
        if (distanceToBlackHole > boundary && i > 2) {
            escaped = true;
            break;
        }

        WxKerrGeometry geo = wxComputeGeometryScalars(x.xyz, physicalSpinA, physicalQ, 1.0f, currentSign);
        minR = min(minR, abs(geo.r));
        if (currentSign > 0.0f && geo.r < eventHorizonR) {
            absorbed = true;
            break;
        }

        WxState s = WxState { x, pCov };
        WxState k1 = wxDerivatives(s, physicalSpinA, physicalQ, 1.0f, geo);
        const float rho = length(x.xz);
        const float distRing = sqrt(x.y * x.y + pow(rho - abs(physicalSpinA), 2.0f));
        const float velMag = max(length(k1.x), 1e-7f);
        const float forceMag = max(length(k1.p), 1e-12f);
        const float momMag = max(length(pCov), 1e-6f);
        float dLambda = 0.45f * min(distRing / velMag, momMag / forceMag);
        dLambda = clamp(dLambda, 0.004f, distanceToBlackHole > 80.0f ? 6.0f : 1.15f);

        const float4 lastX = x;
        const float3 lastPos = x.xyz;
        wxStepGeodesicRK4(x, pCov, energy, -dLambda, physicalSpinA, physicalQ, 1.0f, currentSign, geo, k1);

        const float3 stepVec = x.xyz - lastPos;
        const float actualStepLength = length(stepVec);
        if (actualStepLength > 1e-7f) {
            rayDir = stepVec / actualStepLength;
        }

        if (lastPos.y * x.y < 0.0f) {
            const float tCross = lastPos.y / max(lastPos.y - x.y, 1e-8f);
            const float rhoCross = length(mix(lastPos.xz, x.xz, tCross));
            if (rhoCross < abs(physicalSpinA)) {
                currentSign *= -1.0f;
            }
        }

        const float dr = geo.r - lastR;
        const float drdl = dr / max(actualStepLength, 1e-8f);
        const float rotFact = clamp(1.0f + 0.75f * dot(-stepVec, float3(x.z, 0.0f, -x.x)) / max(actualStepLength * length(x.xz), 1e-8f) * 0.99f, 0.0f, 1.0f);
        if (geo.r < 1.6f + pow(abs(0.99f), 0.666666f)) {
            thetaInShell += actualStepLength / max(0.5f * lastR + 0.5f * geo.r, 1e-5f) / (1.0f + 1000.0f * drdl * drdl) * rotFact;
        }
        lastR = geo.r;

        if (currentSign > 0.0f) {
            result = wxDiskAndJetEmission(result, actualStepLength, x, lastX, rayDir, pCov, energy, physicalSpinA, physicalQ, thetaInShell, time);
        }
    }

    if (!absorbed) {
        WxKerrGeometry geo = wxComputeGeometryScalars(x.xyz, physicalSpinA, physicalQ, 1.0f, currentSign);
        const float4 pContra = wxRaiseIndex(pCov, geo);
        const float3 escapeDir = escaped ? normalize(pContra.xyz) : rayDir;
        float3 background = blackHoleStarField(escapeDir, float3(0.004f, 0.006f, 0.014f)) * 1.9f;
        const float shift = clamp(1.0f / sqrt(max(1.0f - 1.0f / max(abs(geo.r), 1.01f), 0.02f)), 0.6f, 2.0f);
        background *= pow(shift, 1.7f);
        result.rgb += background * pow(max(1.0f - result.a, 0.0f), 1.0f);
    }

    float3 color = wxToneMap(result, 1.0f);
    const float photonRing = exp(-pow((minR - 1.48f) / 0.045f, 2.0f));
    color += photonRing * float3(1.6f, 2.7f, 5.2f) * (absorbed ? 1.25f : 0.55f);
    if (absorbed && result.a < 0.2f) {
        color *= 0.025f;
    }
    return max(color, float3(0.0f));
}

inline float w3RandomStep(float2 input, float seed) {
    return fract(sin(dot(input + fract(11.4514f * sin(seed)), float2(12.9898f, 78.233f))) * 43758.5453f);
}

inline float w3CubicInterpolate(float x) {
    return x * x * (3.0f - 2.0f * x);
}

inline float w3PerlinNoise(float3 position) {
    const float3 pi = floor(position);
    const float3 pf = fract(position);
    const float3 u = pf * pf * (3.0f - 2.0f * pf);

    const float v000 = 2.0f * fract(sin(dot(pi + float3(0.0f, 0.0f, 0.0f), float3(12.9898f, 78.233f, 213.765f))) * 43758.5453f) - 1.0f;
    const float v100 = 2.0f * fract(sin(dot(pi + float3(1.0f, 0.0f, 0.0f), float3(12.9898f, 78.233f, 213.765f))) * 43758.5453f) - 1.0f;
    const float v010 = 2.0f * fract(sin(dot(pi + float3(0.0f, 1.0f, 0.0f), float3(12.9898f, 78.233f, 213.765f))) * 43758.5453f) - 1.0f;
    const float v110 = 2.0f * fract(sin(dot(pi + float3(1.0f, 1.0f, 0.0f), float3(12.9898f, 78.233f, 213.765f))) * 43758.5453f) - 1.0f;
    const float v001 = 2.0f * fract(sin(dot(pi + float3(0.0f, 0.0f, 1.0f), float3(12.9898f, 78.233f, 213.765f))) * 43758.5453f) - 1.0f;
    const float v101 = 2.0f * fract(sin(dot(pi + float3(1.0f, 0.0f, 1.0f), float3(12.9898f, 78.233f, 213.765f))) * 43758.5453f) - 1.0f;
    const float v011 = 2.0f * fract(sin(dot(pi + float3(0.0f, 1.0f, 1.0f), float3(12.9898f, 78.233f, 213.765f))) * 43758.5453f) - 1.0f;
    const float v111 = 2.0f * fract(sin(dot(pi + float3(1.0f, 1.0f, 1.0f), float3(12.9898f, 78.233f, 213.765f))) * 43758.5453f) - 1.0f;

    const float x00 = mix(v000, v100, u.x);
    const float x10 = mix(v010, v110, u.x);
    const float x01 = mix(v001, v101, u.x);
    const float x11 = mix(v011, v111, u.x);
    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

inline float w3PerlinNoise1D(float position) {
    const float pi = floor(position);
    const float pf = fract(position);
    const float v0 = 2.0f * fract(sin(pi * 12.9898f) * 43758.5453f) - 1.0f;
    const float v1 = 2.0f * fract(sin((pi + 1.0f) * 12.9898f) * 43758.5453f) - 1.0f;
    return mix(v0, v1, w3CubicInterpolate(pf));
}

inline float w3SoftSaturate(float x) {
    return 1.0f - 1.0f / (max(x, 0.0f) + 1.0f);
}

inline float w3AccretionDiskNoise(float3 position, float noiseStartLevel, float noiseEndLevel, float contrastLevel) {
    float accumulator = 10.0f;
    const int iStart = int(floor(noiseStartLevel));
    const int iEnd = int(ceil(noiseEndLevel));

    for (int i = -2; i <= 10; i++) {
        if (i < iStart || i >= iEnd) {
            continue;
        }

        const float fi = float(i);
        const float w = max(0.0f, min(noiseEndLevel, fi + 1.0f) - max(noiseStartLevel, fi));
        const float frequency = pow(3.0f, fi);
        accumulator *= 1.0f + 0.1f * w3PerlinNoise(position * frequency) * w;
    }

    return log(1.0f + pow(max(0.0f, 0.1f * accumulator), contrastLevel));
}

inline float w3Vec2ToTheta(float2 v1, float2 v2) {
    const float denom = max(length(v1) * length(v2), 1e-7f);
    const float s = clamp((v1.x * v2.y - v1.y * v2.x) / denom, -0.999999f, 0.999999f);
    const float c = dot(v1, v2);
    if (c > 0.0f) {
        return asin(s);
    }
    return s >= 0.0f ? 3.141592653589f - asin(s) : -3.141592653589f - asin(s);
}

inline float w3Shape(float x, float alpha, float beta) {
    const float sx = saturate(x);
    const float k = pow(alpha + beta, alpha + beta) / max(pow(alpha, alpha) * pow(beta, beta), 1e-6f);
    return k * pow(max(sx, 1e-5f), alpha) * pow(max(1.0f - sx, 1e-5f), beta);
}

inline float3 w3KelvinToRgb(float kelvin) {
    if (kelvin < 400.01f) {
        return float3(0.0f);
    }

    const float t = (kelvin - 6500.0f) / (6500.0f * kelvin * 2.2f);
    float3 color = float3(
        exp(2.05539304e4f * t),
        exp(2.63463675e4f * t),
        exp(3.30145739e4f * t)
    );
    float brightnessScale = 1.0f / max(max(1.5f * color.r, color.g), color.b);
    if (kelvin < 1000.0f) {
        brightnessScale *= (kelvin - 400.0f) / 600.0f;
    }
    return max(color * brightnessScale, float3(0.0f));
}

inline float3 w3WavelengthToRgb(float wavelength) {
    float3 color = float3(0.0f);
    if (wavelength < 380.0f || wavelength > 750.0f) {
        return color;
    }

    if (wavelength < 440.0f) {
        color = float3(-(wavelength - 440.0f) / 60.0f, 0.0f, 1.0f);
    } else if (wavelength < 490.0f) {
        color = float3(0.0f, (wavelength - 440.0f) / 50.0f, 1.0f);
    } else if (wavelength < 510.0f) {
        color = float3(0.0f, 1.0f, -(wavelength - 510.0f) / 20.0f);
    } else if (wavelength < 580.0f) {
        color = float3((wavelength - 510.0f) / 70.0f, 1.0f, 0.0f);
    } else if (wavelength < 645.0f) {
        color = float3(1.0f, -(wavelength - 645.0f) / 65.0f, 0.0f);
    } else {
        color = float3(1.0f, 0.0f, 0.0f);
    }

    const float factor = wavelength < 420.0f ? 0.3f + 0.7f * (wavelength - 380.0f) / 40.0f
        : (wavelength < 645.0f ? 1.0f : 0.3f + 0.7f * (750.0f - wavelength) / 105.0f);
    const float luminance = max(sqrt(color.r * color.r + 2.25f * color.g * color.g + 0.36f * color.b * color.b), 1e-5f);
    return color * factor / luminance * (0.1f * (color.r + color.g + color.b) + 0.9f);
}

inline float w3KeplerianAngularVelocity(float radius, float rs) {
    const float cOverLy = 299792458.0f / 9460730472580800.0f;
    return sqrt(cOverLy * 299792458.0f * rs / max((2.0f * radius - 3.0f * rs) * radius * radius, 1e-20f));
}

inline float3 w3DiskLocal(float3 p, float3 diskNormal, float3 diskTangent) {
    const float3 y = normalize(diskNormal);
    const float3 x = normalize(diskTangent);
    const float3 z = normalize(cross(x, y));
    return float3(dot(p, x), dot(p, y), dot(p, z));
}

inline float4 w3AccumulateEmission(float4 baseColor, float4 emission) {
    const float transmittance = pow(max(1.0f - baseColor.a, 0.0f), 1.0f);
    baseColor.rgb += emission.rgb * transmittance;
    baseColor.a += emission.a * transmittance;
    return baseColor;
}

inline float4 w3DiskColor(
    float4 baseColor,
    float stepLength,
    float3 rayPos,
    float3 lastRayPos,
    float3 rayDir,
    float3 diskNormal,
    float3 diskTangent,
    float rs,
    float interRadius,
    float outerRadius,
    float thin,
    float hopper,
    float diskArgument,
    float peakTemperature,
    float time
) {
    const float3 posDisk = w3DiskLocal(rayPos, diskNormal, diskTangent);
    const float3 lastDisk = w3DiskLocal(lastRayPos, diskNormal, diskTangent);
    const float3 dirDisk = normalize(w3DiskLocal(rayDir, diskNormal, diskTangent));

    float3 samplePos = posDisk;
    if (lastDisk.y * posDisk.y < 0.0f) {
        const float t = saturate(lastDisk.y / max(lastDisk.y - posDisk.y, 1e-7f));
        samplePos = mix(lastDisk, posDisk, t);
    }

    float posR = length(samplePos.xz);
    float posY = samplePos.y;
    float geometricThin = thin + max(0.0f, (posR - 3.0f * rs) * hopper);
    const float interCloudRadius = (posR - interRadius) / max(min(outerRadius - interRadius, 12.0f * rs), 1e-9f);
    const float innerCloudBound = geometricThin * (1.0f - 5.0f * interCloudRadius * interCloudRadius);

    if (posR <= interRadius || posR >= outerRadius || abs(posY) > max(geometricThin * 1.5f, innerCloudBound)) {
        return baseColor;
    }

    const float x = saturate((posR - interRadius) / max(outerRadius - interRadius, 1e-9f));
    const float a = max(1.0f, (outerRadius - interRadius) / (10.0f * rs));
    const float effectiveRadius = a == 1.0f ? x : (-1.0f + sqrt(max(1.0f + 4.0f * a * a * x - 4.0f * x * a, 0.0f))) / max(2.0f * a - 2.0f, 1e-6f);
    const float densityShape = w3Shape(effectiveRadius, 0.9f, 1.5f);
    const float frac = max(0.0f, 2.0f - 0.6f * geometricThin / rs);

    if (abs(posY) > geometricThin * densityShape && posY > innerCloudBound) {
        return baseColor;
    }

    const float angularVelocity = w3KeplerianAngularVelocity(max(posR, interRadius), rs);
    const float halfPiTimeInside = 3.141592653589f / w3KeplerianAngularVelocity(3.0f * rs, rs);
    const float innerTheta = 3.141592653589f / halfPiTimeInside * time * 30000.0f;
    const float spiralTheta = 12.0f * 2.0f / sqrt(3.0f) * atan(sqrt(max(0.6666666f * (posR / rs) - 1.0f, 0.0f)));
    const float posTheta = w3Vec2ToTheta(samplePos.zx, float2(cos(-spiralTheta), sin(-spiralTheta)));
    const float posLogTheta = w3Vec2ToTheta(samplePos.zx, float2(cos(-2.0f * log(max(posR / rs, 1.001f))), sin(-2.0f * log(max(posR / rs, 1.001f)))));
    const float rotPosR = posR / rs + 0.3f * sqrt(3.0f) * 299792458.0f / 9460730472580800.0f / 3.0f / sqrt(3.0f) / rs * 30000.0f * time;

    const float levelMut = 0.91f * log(1.0f + 0.06f / 0.91f * max(0.0f, min(1000.0f, posR / rs) - 10.0f));
    const float contrastMut = 80.0f * log(1.0f + 0.006f * max(0.0f, min(1000000.0f, posR / rs) - 10.0f));
    float cloud = w3AccretionDiskNoise(float3(0.1f * rotPosR, 0.1f * posY / rs, 0.02f * pow(max(outerRadius / rs, 1.0f), 0.7f) * posTheta), frac + 2.0f - levelMut, frac + 4.0f - levelMut, max(1.0f, 80.0f - contrastMut));

    if (posR > max(0.15379f * outerRadius, 0.15379f * 64.0f * rs)) {
        const float timeShiftedRadius = posR - 0.1f * sqrt(3.0f) * 299792458.0f / 9460730472580800.0f / 3.0f / sqrt(3.0f) / rs * 30000.0f * time;
        const float spiral = w3AccretionDiskNoise(float3(0.1f * (timeShiftedRadius - 0.08f * outerRadius / rs * posLogTheta), 0.1f * posY / rs, 0.02f * pow(max(outerRadius / rs, 1.0f), 0.7f) * posLogTheta), frac + 2.0f - levelMut, frac + 3.0f - levelMut, max(1.0f, 80.0f - contrastMut));
        cloud *= mix(1.0f, clamp(1.05f * spiral - 0.5f, 0.0f, 3.0f), 0.5f + 0.5f * max(-1.0f, 1.0f - exp(-0.15f * (100.0f * posR / max(outerRadius, 64.0f * rs) - 20.0f))));
    }

    const float thickNoise = w3AccretionDiskNoise(float3(1.5f * posTheta, rotPosR, 1.0f), -0.7f + frac, 1.3f + frac, 80.0f);
    const float thick = max(geometricThin * densityShape * (0.4f + 0.6f * clamp(geometricThin / rs - 0.5f, 0.0f, 2.5f) / 2.5f + 0.6f * w3SoftSaturate(thickNoise)), 1e-8f);
    const float vertical = max(0.0f, 1.0f - abs(posY) / thick);
    const float density = densityShape * densityShape * vertical;

    float dust = 0.0f;
    if (abs(posY) < innerCloudBound) {
        const float innerCloudTheta = w3Vec2ToTheta(samplePos.zx, float2(cos(0.666666f * innerTheta), sin(0.666666f * innerTheta)));
        dust = max(1.0f - pow(posY / max(innerCloudBound, 1e-7f), 2.0f), 0.0f)
            * w3AccretionDiskNoise(float3(1.5f * fract((1.5f * innerCloudTheta + innerTheta) / (2.0f * 3.141592653589f)) * 2.0f * 3.141592653589f, posR / rs, posY / rs), 0.0f, 6.0f, 80.0f);
    }

    const float diskTemperature = pow(diskArgument * pow(rs / max(posR, 1e-9f), 3.0f) * max(1.0f - sqrt(interRadius / max(posR, 1e-9f)), 0.000001f), 0.25f);
    const float3 cloudVelocity = 9460730472580800.0f / 299792458.0f * angularVelocity * cross(float3(0.0f, 1.0f, 0.0f), samplePos);
    const float relativeVelocity = clamp(dot(-dirDisk, cloudVelocity), -0.95f, 0.95f);
    const float doppler = sqrt((1.0f + relativeVelocity) / max(1.0f - relativeVelocity, 1e-4f));
    const float redShift = doppler * sqrt(max(1.0f - rs / max(posR, 1e-9f), 0.000001f)) / sqrt(max(1.0f - rs / (36.0f * rs), 0.000001f));
    const float brightness = (0.05f * min(outerRadius / (1000.0f * rs), 1000.0f * rs / outerRadius) + 0.55f / exp(5.0f * effectiveRadius))
        * pow(max(diskTemperature / max(peakTemperature, 1.0f), 0.0f), 0.5f);
    const float3 thermal = w3KelvinToRgb(diskTemperature * pow(max(redShift, 0.05f), 3.0f));

    float4 emission = float4(0.0f);
    emission.rgb = (cloud * density * 1.4f + 0.02f * dust) * thermal * brightness * min(pow(max(redShift, 0.0f), 4.0f), 1.25f);
    emission.rgb *= min(1.0f, 1.8f * (outerRadius - posR) / max(outerRadius - interRadius, 1e-9f)) * 0.92f;
    emission.a = (cloud * density * density / 0.3f + 0.2f * dust) * 0.25f;
    emission *= stepLength / rs;
    return w3AccumulateEmission(baseColor, emission);
}

inline float4 w3JetColor(
    float4 baseColor,
    float stepLength,
    float3 rayPos,
    float3 rayDir,
    float3 diskNormal,
    float3 diskTangent,
    float rs,
    float interRadius,
    float outerRadius,
    float time
) {
    const float3 posDisk = w3DiskLocal(rayPos, diskNormal, diskTangent);
    const float3 dirDisk = normalize(w3DiskLocal(rayDir, diskNormal, diskTangent));
    const float rho = length(posDisk.xz);
    const float posR = max(length(posDisk), 1e-6f);
    const float posY = posDisk.y;
    float intensity = 0.0f;

    if (rho * rho < 2.0f * interRadius * interRadius + 0.03f * 0.03f * posY * posY && posR < sqrt(2.0f) * outerRadius) {
        const float shape = 1.0f / sqrt(max(interRadius * interRadius + 0.02f * 0.02f * posY * posY, 1e-9f));
        const float flow = 0.7f + 0.3f * w3PerlinNoise1D(0.3f * (30000.0f * time - 9460730472580800.0f / 0.8f / 299792458.0f * abs(posY)) / max(outerRadius / 100.0f, 1e-7f));
        intensity += flow * max(0.0f, 1.0f - 5.0f * rs * shape * abs(1.0f - pow(rho * shape, 2.0f))) * rs * shape;
        intensity *= max(0.0f, 1.0f - exp(-0.0001f * posY * posY / max(interRadius * interRadius, 1e-10f)));
        intensity *= exp(-2.0f * posR * posR / max(outerRadius * outerRadius, 1e-10f));
    }

    const float wid = abs(posY);
    if (rho < 1.3f * interRadius + 0.25f * wid && rho > 0.7f * interRadius + 0.15f * wid && posR < 30.0f * interRadius) {
        const float shape = 1.0f / max(interRadius + 0.2f * wid, 1e-9f);
        intensity += 0.5f * max(0.0f, 1.0f - 2.0f * abs(1.0f - pow(rho * shape, 2.0f))) * rs * shape
            * (1.0f - exp(-posY * posY / max(interRadius * interRadius, 1e-10f)))
            * exp(-0.005f * posY * posY / max(interRadius * interRadius, 1e-10f));
    }

    if (intensity <= 0.0f) {
        return baseColor;
    }

    const float relativeVelocity = clamp(-dirDisk.y * sqrt(rs / max(posR, rs)) * sign(posY), -0.92f, 0.92f);
    const float doppler = sqrt((1.0f + relativeVelocity) / max(1.0f - relativeVelocity, 1e-4f));
    const float redShift = doppler * sqrt(max(1.0f - rs / max(posR, 1e-9f), 0.000001f));
    float4 emission = float4(w3KelvinToRgb(100000.0f) * intensity * min(pow(max(redShift, 0.0f), 2.0f), 3.0f), 0.0f);
    emission.rgb *= stepLength / rs * 0.55f;
    return w3AccumulateEmission(baseColor, emission);
}

inline float3 renderW3BBzKBufferA(float2 uv, constant FrameUniforms &uniforms) {
    const float time = uniforms.time;
    const float rs = 4.67e-6f;
    const float interRadius = 2.1f * rs;
    const float outerRadius = (57.0f + 45.0f * cos(0.5f * time)) * rs;
    const float thin = (2.25f + 1.75f * cos(0.21f * time)) * rs;
    const float hopper = 0.375f * (1.0f - cos(0.6f * time));
    const float diskArgument = 1.7e26f * pow(10.0f, -6.0f + 3.5f + 3.5f * cos(0.7f * time));
    const float peakTemperature = pow(max(diskArgument * 0.05665278f * pow(rs / interRadius, 3.0f), 1.0f), 0.25f);

    const float3 diskNormal = normalize(float3(0.4f, 1.0f, -0.4f));
    const float3 diskTangent = normalize(float3(1.0f, -0.4f, 0.0f));

    const float2 mouseNorm = uniforms.shadertoyMouse.xy / max(uniforms.resolution, float2(1.0f));
    const bool hasMouse = mouseNorm.x > 0.01f || mouseNorm.y > 0.01f;
    const float theta = hasMouse ? 4.0f * 3.141592653589f * clamp(mouseNorm.x, 0.0f, 1.0f) : 4.0f * 3.141592653589f * 0.15f;
    const float phi = hasMouse ? 0.999f * 3.141592653589f * clamp(mouseNorm.y, 0.0f, 1.0f) + 0.0005f : 0.999f * 3.141592653589f * 0.5f + 0.0005f;
    float cameraDistance = 0.000207f;
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 2)) {
        cameraDistance = 0.000807f;
    }
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 0)) {
        cameraDistance = 0.0000186f;
    }
    const float3 ro = float3(
        cameraDistance * sin(phi) * cos(theta),
        -cameraDistance * cos(phi),
        -cameraDistance * sin(phi) * sin(theta)
    );
    const float3 target = float3(0.0f, 0.0f, 0.0f);
    const float3 forward = normalize(target - ro);
    const float3 right = normalize(cross(float3(0.0f, 1.0f, 0.0f), forward));
    const float3 up = cross(forward, right);
    float3 rayDir = normalize(0.5f * uv.x * right + 0.5f * uv.y * up + forward);

    float3 rayPos = ro;
    float3 lastRayPos = rayPos;
    float3 lastRayDir = rayDir;
    float lastR = length(rayPos);
    float4 result = float4(0.0f);
    float stepLength = 0.0f;
    const int raySteps = clamp(uniforms.rayMarchSteps, 96, 192);

    for (int i = 0; i < 192; i++) {
        if (i >= raySteps) {
            break;
        }

        const float distanceToBlackHole = max(length(rayPos), 1e-8f);
        const float3 normalToBlackHole = rayPos / distanceToBlackHole;
        if (distanceToBlackHole < 0.11f * rs || result.a > 0.99f) {
            break;
        }

        result = w3DiskColor(result, max(stepLength, 0.12f * rs), rayPos, lastRayPos, rayDir, diskNormal, diskTangent, rs, interRadius, outerRadius, thin, hopper, diskArgument, peakTemperature, time);
        result = w3JetColor(result, max(stepLength, 0.12f * rs), rayPos, rayDir, diskNormal, diskTangent, rs, interRadius, outerRadius, time);

        if (distanceToBlackHole > 2.5f * outerRadius && distanceToBlackHole > lastR && i > 48) {
            const float backgroundShift = min(1.0f / sqrt(max(1.0f - rs / max(distanceToBlackHole, 1.001f * rs) + 0.005f, 1e-5f)), 2.0f);
            float3 background = blackHoleStarField(rayDir, float3(0.006f, 0.005f, 0.004f)) * 1.8f;
            if (distanceToBlackHole < 200.0f * rs) {
                const float3 shifted = background.r * w3WavelengthToRgb(max(453.0f, 645.0f / backgroundShift))
                    + background.g * 1.5f * w3WavelengthToRgb(max(416.0f, 510.0f / backgroundShift))
                    + background.b * 0.6f * w3WavelengthToRgb(max(380.0f, 440.0f / backgroundShift));
                background = shifted * pow(backgroundShift, 4.0f);
            }
            result.rgb += 0.2f * background * pow(max(1.0f - result.a, 0.0f), 1.0f);
            break;
        }

        lastRayPos = rayPos;
        lastRayDir = rayDir;
        lastR = distanceToBlackHole;

        const float cosTheta = max(length(cross(normalToBlackHole, rayDir)), 1e-4f);
        const float deltaPhiRate = -cosTheta * cosTheta * cosTheta * (1.5f * rs / distanceToBlackHole);
        float rayStep = i == 0 ? w3RandomStep(uv, fract(time)) : 1.0f;
        rayStep *= 0.15f + 0.25f * min(max(0.0f, 0.5f * (0.5f * distanceToBlackHole / max(10.0f * rs, outerRadius) - 1.0f)), 1.0f);

        if (distanceToBlackHole >= 2.0f * outerRadius) {
            rayStep *= distanceToBlackHole;
        } else if (distanceToBlackHole >= outerRadius) {
            rayStep *= ((rs + 0.25f * max(distanceToBlackHole - 12.0f * rs, 0.0f)) * (2.0f * outerRadius - distanceToBlackHole)
                + distanceToBlackHole * (distanceToBlackHole - outerRadius)) / outerRadius;
        } else {
            rayStep *= min(rs + 0.25f * max(distanceToBlackHole - 12.0f * rs, 0.0f), distanceToBlackHole);
        }

        const float deltaPhi = rayStep / distanceToBlackHole * deltaPhiRate;
        rayDir = normalize(rayDir + (deltaPhi + deltaPhi * deltaPhi * deltaPhi / 3.0f) * cross(cross(rayDir, normalToBlackHole), rayDir) / cosTheta);
        rayPos += rayDir * rayStep;
        stepLength = rayStep;
    }

    const float sum = result.r + result.g + result.b;
    if (sum > 1e-5f) {
        const float3 colorFactor = 3.0f * result.rgb / sum;
        const float3 safeColor = clamp(result.rgb, float3(0.0f), float3(0.995f));
        result.rgb = min(-4.0f * log(1.0f - pow(safeColor, float3(2.2f))), 12.0f * colorFactor);
    }
    return max(result.rgb, float3(0.0f));
}

inline float3 renderShadertoyW3BBzKBase(float2 uv, constant FrameUniforms &uniforms) {
    return renderW3BBzKBufferA(uv, uniforms);
}

inline float3 sampleChannel(texture2d<float, access::sample> sourceTexture, sampler linearSampler, float2 uv) {
    return sourceTexture.sample(linearSampler, saturate(uv)).rgb;
}

inline float3 blackHoleBloomPrefilter(
    texture2d<float, access::sample> baseTexture,
    sampler linearSampler,
    float2 uv,
    constant FrameUniforms &uniforms
) {
    const float2 pixelStep = 1.0f / max(uniforms.resolution, float2(1.0f));
    float3 color = sampleChannel(baseTexture, linearSampler, uv) * 0.22f;

    for (int ring = 1; ring <= 4; ring++) {
        const float radius = pow(2.0f, float(ring - 1));
        const float weight = ring == 1 ? 0.115f : (ring == 2 ? 0.072f : (ring == 3 ? 0.040f : 0.022f));
        const float2 d = pixelStep * radius;
        color += sampleChannel(baseTexture, linearSampler, uv + d * float2(1.0f, 0.0f)) * weight;
        color += sampleChannel(baseTexture, linearSampler, uv + d * float2(-1.0f, 0.0f)) * weight;
        color += sampleChannel(baseTexture, linearSampler, uv + d * float2(0.0f, 1.0f)) * weight;
        color += sampleChannel(baseTexture, linearSampler, uv + d * float2(0.0f, -1.0f)) * weight;
        color += sampleChannel(baseTexture, linearSampler, uv + d * float2(1.0f, 1.0f)) * weight * 0.55f;
        color += sampleChannel(baseTexture, linearSampler, uv + d * float2(-1.0f, 1.0f)) * weight * 0.55f;
        color += sampleChannel(baseTexture, linearSampler, uv + d * float2(1.0f, -1.0f)) * weight * 0.55f;
        color += sampleChannel(baseTexture, linearSampler, uv + d * float2(-1.0f, -1.0f)) * weight * 0.55f;
    }

    const float threshold = 0.25f;
    const float brightness = max(max(color.r, color.g), color.b);
    const float bloomMask = smoothstep(threshold, threshold + 1.6f, brightness);
    const float3 warmBias = float3(1.0f, 0.62f, 0.28f);
    const float3 tint = warmBias;
    return max(color - threshold, float3(0.0f)) * bloomMask * tint * 1.65f;
}

inline float3 blackHoleGaussianBlur(
    texture2d<float, access::sample> sourceTexture,
    sampler linearSampler,
    float2 uv,
    float2 axis,
    constant FrameUniforms &uniforms
) {
    const float2 pixelStep = axis / max(uniforms.resolution, float2(1.0f));
    float3 color = sampleChannel(sourceTexture, linearSampler, uv) * 0.19638062f;

    const float2 off1 = pixelStep * 1.41176471f;
    const float2 off2 = pixelStep * 3.29411765f;
    const float2 off3 = pixelStep * 5.17647059f;
    const float2 off4 = pixelStep * 7.05882353f;

    color += (sampleChannel(sourceTexture, linearSampler, uv + off1) + sampleChannel(sourceTexture, linearSampler, uv - off1)) * 0.29675293f;
    color += (sampleChannel(sourceTexture, linearSampler, uv + off2) + sampleChannel(sourceTexture, linearSampler, uv - off2)) * 0.09442139f;
    color += (sampleChannel(sourceTexture, linearSampler, uv + off3) + sampleChannel(sourceTexture, linearSampler, uv - off3)) * 0.01037598f;
    color += (sampleChannel(sourceTexture, linearSampler, uv + off4) + sampleChannel(sourceTexture, linearSampler, uv - off4)) * 0.00025940f;
    return color;
}

inline float3 composeBlackHoleMultipass(
    texture2d<float, access::sample> baseTexture,
    texture2d<float, access::sample> bloomTexture,
    sampler linearSampler,
    float2 uv,
    constant FrameUniforms &uniforms
) {
    float3 base = sampleChannel(baseTexture, linearSampler, uv);
    const float2 pixelStep = 1.0f / max(uniforms.resolution, float2(1.0f));
    float3 bloom = sampleChannel(bloomTexture, linearSampler, uv) * 1.0f;
    bloom += sampleChannel(bloomTexture, linearSampler, uv + pixelStep * float2(2.0f, 0.0f)) * 0.75f;
    bloom += sampleChannel(bloomTexture, linearSampler, uv + pixelStep * float2(-2.0f, 0.0f)) * 0.75f;
    bloom += sampleChannel(bloomTexture, linearSampler, uv + pixelStep * float2(0.0f, 2.0f)) * 0.75f;
    bloom += sampleChannel(bloomTexture, linearSampler, uv + pixelStep * float2(0.0f, -2.0f)) * 0.75f;
    bloom += sampleChannel(bloomTexture, linearSampler, uv + pixelStep * float2(6.0f, 3.0f)) * 0.55f;
    bloom += sampleChannel(bloomTexture, linearSampler, uv + pixelStep * float2(-6.0f, -3.0f)) * 0.55f;
    bloom += sampleChannel(bloomTexture, linearSampler, uv + pixelStep * float2(12.0f, -7.0f)) * 0.36f;
    bloom += sampleChannel(bloomTexture, linearSampler, uv + pixelStep * float2(-12.0f, 7.0f)) * 0.36f;
    bloom /= 5.82f;

    const float bloomAmount = 0.08f;
    const float3 tint = float3(1.12f, 0.82f, 0.52f);
    float3 color = base + bloom * bloomAmount * tint;
    color = pow(max(color, float3(0.0f)), float3(1.5f));
    color = color / (1.0f + color);
    color = pow(max(color, float3(0.0f)), float3(1.0f / 1.5f));
    color = color * color * (3.0f - 2.0f * color);
    color = pow(max(color, float3(0.0f)), float3(1.30f, 1.20f, 1.0f));
    color = saturate(color * 1.01f);
    return pow(max(color, float3(0.0f)), float3(0.7f / 2.2f));
}

inline float2 shadertoyBloomCalcOffset(float octave, float2 resolution) {
    const float2 padding = float2(10.0f) / max(resolution, float2(1.0f));
    float2 offset = float2(0.0f);
    offset.x = -min(1.0f, floor(octave / 3.0f)) * (0.25f + padding.x);
    offset.y = -(1.0f - (1.0f / exp2(octave))) - padding.y * octave;
    offset.y += min(1.0f, floor(octave / 3.0f)) * 0.35f;
    return offset;
}

inline float3 shadertoyBloomGrabMip(
    texture2d<float, access::sample> sourceTexture,
    sampler linearSampler,
    float2 coord,
    float octave,
    float2 offset,
    int oversampling,
    float2 resolution
) {
    const float scale = exp2(octave);
    coord = (coord + offset) * scale;

    if (coord.x < 0.0f || coord.x > 1.0f || coord.y < 0.0f || coord.y > 1.0f) {
        return float3(0.0f);
    }

    float3 color = float3(0.0f);
    float weight = 0.0f;
    const int samples = clamp(oversampling, 1, 16);

    for (int y = 0; y < 16; y++) {
        if (y >= samples) {
            break;
        }
        for (int x = 0; x < 16; x++) {
            if (x >= samples) {
                break;
            }

            const float2 sampleOffset = (float2(float(x), float(y)) / resolution - float(samples) * 0.5f / resolution)
                * scale / float(samples);
            color += sampleChannel(sourceTexture, linearSampler, coord + sampleOffset);
            weight += 1.0f;
        }
    }

    return color / max(weight, 1.0f);
}

inline float3 shadertoyBloomMipAtlas(
    texture2d<float, access::sample> baseTexture,
    sampler linearSampler,
    float2 uv,
    constant FrameUniforms &uniforms
) {
    const float2 resolution = max(uniforms.resolution, float2(1.0f));
    float3 color = float3(0.0f);
    color += shadertoyBloomGrabMip(baseTexture, linearSampler, uv, 1.0f, float2(0.0f), 1, resolution);
    color += shadertoyBloomGrabMip(baseTexture, linearSampler, uv, 2.0f, shadertoyBloomCalcOffset(1.0f, resolution), 4, resolution);
    color += shadertoyBloomGrabMip(baseTexture, linearSampler, uv, 3.0f, shadertoyBloomCalcOffset(2.0f, resolution), 8, resolution);
    color += shadertoyBloomGrabMip(baseTexture, linearSampler, uv, 4.0f, shadertoyBloomCalcOffset(3.0f, resolution), 16, resolution);
    color += shadertoyBloomGrabMip(baseTexture, linearSampler, uv, 5.0f, shadertoyBloomCalcOffset(4.0f, resolution), 16, resolution);
    color += shadertoyBloomGrabMip(baseTexture, linearSampler, uv, 6.0f, shadertoyBloomCalcOffset(5.0f, resolution), 16, resolution);
    color += shadertoyBloomGrabMip(baseTexture, linearSampler, uv, 7.0f, shadertoyBloomCalcOffset(6.0f, resolution), 16, resolution);
    color += shadertoyBloomGrabMip(baseTexture, linearSampler, uv, 8.0f, shadertoyBloomCalcOffset(7.0f, resolution), 16, resolution);
    return color;
}

inline float4 shadertoyWxdfzjStatePixel(
    texture2d<float, access::read> previousStateTexture,
    float2 fragCoord,
    constant FrameUniforms &uniforms
) {
    const float2 resolution = max(uniforms.resolution, float2(1.0f));
    const int pxIndex = int(resolution.x) - int(fragCoord.x);

    WxCameraState camera = wxCameraStateFromBuffer(previousStateTexture, uniforms);
    float3 pos = camera.position;
    float3 right = camera.right;
    float3 up = camera.up;
    float3 fwd = camera.forward;
    float universeSign = camera.universeSign;

    const float dt = clamp(uniforms.timeDelta, 0.0f, 0.08f);
    if (uniforms.shadertoyMouse.z > 0.0f) {
        const float4 lastMouse = wxReadStatePixel(previousStateTexture, resolution, 5);
        float2 mouseDelta = uniforms.shadertoyMouse.xy - lastMouse.xy;
        if (lastMouse.z < 0.0f || length(lastMouse.xy) < 0.001f) {
            mouseDelta = float2(0.0f);
        }

        const float yaw = -mouseDelta.x * 0.003f;
        const float pitch = mouseDelta.y * 0.003f;
        fwd = normalize(wxRotateAroundAxis(fwd, up, yaw));
        right = normalize(wxRotateAroundAxis(right, up, yaw));
        fwd = normalize(wxRotateAroundAxis(fwd, right, pitch));
        up = normalize(cross(right, fwd));
        right = normalize(cross(fwd, up));
    }

    float roll = 0.0f;
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 4)) {
        roll -= 2.0f * dt;
    }
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 5)) {
        roll += 2.0f * dt;
    }
    if (roll != 0.0f) {
        right = normalize(wxRotateAroundAxis(right, fwd, roll));
        up = normalize(cross(right, fwd));
    }

    float3 oldPos = pos;
    float3 moveDir = float3(0.0f);
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 0)) {
        moveDir += fwd;
    }
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 2)) {
        moveDir -= fwd;
    }
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 1)) {
        moveDir -= right;
    }
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 3)) {
        moveDir += right;
    }
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 6)) {
        moveDir += up;
    }
    if (wxInputKeyDown(uniforms.shadertoyKeyMask, 7)) {
        moveDir -= up;
    }
    if (dot(moveDir, moveDir) > 0.0f) {
        pos += normalize(moveDir) * dt;
    }

    if (oldPos.y * pos.y < 0.0f) {
        const float t = oldPos.y / max(oldPos.y - pos.y, 1e-8f);
        const float3 crossPoint = mix(oldPos, pos, t);
        if (length(crossPoint.xz) < abs(0.99f * 0.5f)) {
            universeSign *= -1.0f;
        }
    }

    if (pxIndex == 1) {
        return float4(up, 1.0f);
    }
    if (pxIndex == 2) {
        return float4(right, 1.0f);
    }
    if (pxIndex == 3) {
        return float4(pos, 1.0f);
    }
    if (pxIndex == 4) {
        return float4(fwd, 1.0f);
    }
    if (pxIndex == 5) {
        return uniforms.shadertoyMouse;
    }
    if (pxIndex == 6) {
        return float4(uniforms.time, universeSign, 0.0f, 1.0f);
    }
    return float4(0.0f);
}

inline float3 shadertoyBloomBlurAtlas(
    texture2d<float, access::sample> sourceTexture,
    sampler linearSampler,
    float2 uv,
    float2 axis,
    constant FrameUniforms &uniforms
) {
    if (uv.x >= 0.52f) {
        return float3(0.0f);
    }

    const float weights[5] = {
        0.19638062f,
        0.29675293f,
        0.09442139f,
        0.01037598f,
        0.00025940f
    };
    const float offsets[5] = {
        0.0f,
        1.41176471f,
        3.29411765f,
        5.17647059f,
        7.05882353f
    };

    const float2 resolution = max(uniforms.resolution, float2(1.0f));
    float3 color = sampleChannel(sourceTexture, linearSampler, uv) * weights[0];
    float weightSum = weights[0];

    for (int i = 1; i < 5; i++) {
        const float2 sampleOffset = (float2(offsets[i]) / resolution) * axis;
        color += sampleChannel(sourceTexture, linearSampler, uv + sampleOffset) * weights[i];
        color += sampleChannel(sourceTexture, linearSampler, uv - sampleOffset) * weights[i];
        weightSum += weights[i] * 2.0f;
    }

    return color / max(weightSum, 1e-5f);
}

inline float3 shadertoyBloomGrabComposite(
    texture2d<float, access::sample> bloomTexture,
    sampler linearSampler,
    float2 coord,
    float octave,
    float2 offset
) {
    coord /= exp2(octave);
    coord -= offset;
    return sampleChannel(bloomTexture, linearSampler, coord);
}

inline float3 shadertoyBloomComposite(
    texture2d<float, access::sample> baseTexture,
    texture2d<float, access::sample> bloomTexture,
    sampler linearSampler,
    float2 uv,
    constant FrameUniforms &uniforms
) {
    const float2 resolution = max(uniforms.resolution, float2(1.0f));
    float3 color = sampleChannel(baseTexture, linearSampler, uv);
    float3 bloom = float3(0.0f);

    bloom += shadertoyBloomGrabComposite(bloomTexture, linearSampler, uv, 1.0f, shadertoyBloomCalcOffset(0.0f, resolution)) * 1.0f;
    bloom += shadertoyBloomGrabComposite(bloomTexture, linearSampler, uv, 2.0f, shadertoyBloomCalcOffset(1.0f, resolution)) * 1.5f;
    bloom += shadertoyBloomGrabComposite(bloomTexture, linearSampler, uv, 3.0f, shadertoyBloomCalcOffset(2.0f, resolution)) * 1.0f;
    bloom += shadertoyBloomGrabComposite(bloomTexture, linearSampler, uv, 4.0f, shadertoyBloomCalcOffset(3.0f, resolution)) * 1.5f;
    bloom += shadertoyBloomGrabComposite(bloomTexture, linearSampler, uv, 5.0f, shadertoyBloomCalcOffset(4.0f, resolution)) * 1.8f;
    bloom += shadertoyBloomGrabComposite(bloomTexture, linearSampler, uv, 6.0f, shadertoyBloomCalcOffset(5.0f, resolution)) * 1.0f;
    bloom += shadertoyBloomGrabComposite(bloomTexture, linearSampler, uv, 7.0f, shadertoyBloomCalcOffset(6.0f, resolution)) * 1.0f;
    bloom += shadertoyBloomGrabComposite(bloomTexture, linearSampler, uv, 8.0f, shadertoyBloomCalcOffset(7.0f, resolution)) * 1.0f;

    color += bloom * 0.08f;
    color = pow(max(color, float3(0.0f)), float3(1.5f));
    color = color / (1.0f + color);
    color = pow(max(color, float3(0.0f)), float3(1.0f / 1.5f));
    color = color * color * (3.0f - 2.0f * color);
    color = pow(max(color, float3(0.0f)), float3(1.3f, 1.20f, 1.0f));
    color = saturate(color * 1.01f);
    return pow(max(color, float3(0.0f)), float3(0.7f / 2.2f));
}

inline float3 renderFractal4D(float2 uv, constant FrameUniforms &uniforms, int maxIter) {
    const float scale = max(fabs(uniforms.scaleHi + uniforms.scaleLo), 0.08f);
    const float3 target = float3(
        uniforms.centerHi.x + uniforms.centerLo.x,
        uniforms.centerHi.y + uniforms.centerLo.y,
        0.0f
    );
    const float cameraDistance = clamp(uniforms.cameraDistance, 1.4f, 12.0f) * scale * 1.05f;
    const float3 orbit = rotateY(rotateX(float3(0.0f, 0.0f, cameraDistance), uniforms.cameraPitch), uniforms.rotation + 0.05f * uniforms.time);
    const float3 ro = target + orbit;
    const float3 forward = normalize(target - ro);
    const float3 right = normalize(cross(float3(0.0f, 1.0f, 0.0f), forward));
    const float3 up = cross(forward, right);
    const float3 rd = normalize(uv.x * right + uv.y * up + 1.5f * forward);

    const int raySteps = clamp(uniforms.rayMarchSteps, 40, 192);
    const float epsilon = clamp(uniforms.surfaceDetail * scale, 0.00008f, 0.018f);
    const float maxDistance = max(8.0f * scale, 5.5f);
    float t = 0.0f;
    float steps = 0.0f;
    bool hit = false;

    for (int i = 0; i < 192; i++) {
        if (i >= raySteps) {
            break;
        }

        const float3 p = ro + rd * t;
        const float d = fractal4DDistance(p, uniforms, maxIter);
        if (d < epsilon) {
            hit = true;
            break;
        }

        t += clamp(d, 0.0007f * scale, 0.20f * scale);
        steps += 1.0f;

        if (t > maxDistance) {
            break;
        }
    }

    if (!hit) {
        const float sky = pow(saturate(0.6f + 0.4f * rd.y), 1.5f);
        const float4 c = float4(uniforms.juliaConstant, uniforms.quaternionConstantZW);
        const float ribbon = 0.12f * exp(-3.0f * abs(dot(rd, normalize(float3(c.x, c.y, c.z) + 0.001f))));
        return mix(uniforms.backgroundColor.rgb * 0.72f, saturate(uniforms.backgroundColor.rgb + float3(0.08f, 0.12f, 0.18f) + ribbon), sky);
    }

    const float3 p = ro + rd * t;
    const float3 normal = fractal4DNormal(p, uniforms, maxIter, epsilon * 2.0f);
    const float3 lightDirection = normalize(float3(-0.48f, 0.78f, 0.38f));
    const float diffuse = saturate(dot(normal, lightDirection));
    const float rim = pow(saturate(1.0f - dot(normal, -rd)), 2.1f);
    const float ao = fractal4DAmbientOcclusion(p, normal, uniforms, maxIter);
    const float4 c = float4(uniforms.juliaConstant, uniforms.quaternionConstantZW);
    const float sliceTone = 8.0f * abs(uniforms.fourDSlice) + 18.0f * length(c);
    const float liftedTone = uniforms.fractalType >= 27 && uniforms.fractalType != 30 ? 0.1f * lifted4DTone(float4(p, uniforms.fourDSlice), uniforms, maxIter) : 0.0f;
    const float orbitTone = 24.0f + steps * 0.85f + length(p) * 8.0f + sliceTone + liftedTone;
    const float3 baseColor = paletteColor(orbitTone, uniforms.colorPalette);
    const float3 shaded = baseColor * (0.34f + 1.15f * diffuse) * ao + rim * 0.5f;
    const float fog = exp(-0.04f * t * t / max(scale, 0.2f));

    return mix(uniforms.backgroundColor.rgb * 0.76f, shaded, fog);
}

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut mandelbrotVertex(uint vertexID [[vertex_id]]) {
    const float2 grid = float2((vertexID << 1) & 2, vertexID & 2);
    VertexOut out;
    out.position = float4(grid * 2.0f - 1.0f, 0.0f, 1.0f);
    out.uv = grid;
    return out;
}

fragment float4 shadertoyBlackHoleBaseFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> historyTexture [[texture(0)]],
    texture2d<float, access::read> stateTexture [[texture(1)]],
    constant FrameUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 resolution = max(uniforms.resolution, float2(1.0f));
    const float2 pixel = in.uv * resolution;
    const float2 uv = (2.0f * pixel - resolution) / resolution.y;

    float3 currentColor;
    if (uniforms.fractalType == 44) {
        currentColor = renderShadertoyWxdfzjBase(uv, uniforms, wxCameraStateFromBuffer(stateTexture, uniforms));
    } else {
        currentColor = renderShadertoyW3BBzKBase(uv, uniforms);
    }

    const float3 previousColor = sampleChannel(historyTexture, linearSampler, in.uv);
    const bool mouseActive = uniforms.shadertoyMouse.z > 0.0f;
    const float blendWeight = uniforms.frameIndex < 2 || (uniforms.fractalType == 45 && mouseActive) ? 1.0f
        : (uniforms.fractalType == 44 ? 0.5f : clamp(1.0f - pow(0.5f, uniforms.timeDelta / 0.08f), 0.08f, 0.65f));
    return float4(mix(previousColor, currentColor, blendWeight), 1.0f);
}

fragment float4 shadertoyBloomMipFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> baseTexture [[texture(0)]],
    texture2d<float, access::read> previousStateTexture [[texture(1)]],
    constant FrameUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 fragCoord = in.uv * max(uniforms.resolution, float2(1.0f));
    const bool isWxdfzjDataPixel = uniforms.fractalType == 44 && fragCoord.y < 1.0f && fragCoord.x > uniforms.resolution.x - 8.5f;
    if (isWxdfzjDataPixel) {
        return shadertoyWxdfzjStatePixel(previousStateTexture, fragCoord, uniforms);
    }
    return float4(shadertoyBloomMipAtlas(baseTexture, linearSampler, in.uv, uniforms), 1.0f);
}

fragment float4 shadertoyBloomBlurHFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    constant FrameUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return float4(shadertoyBloomBlurAtlas(sourceTexture, linearSampler, in.uv, float2(0.5f, 0.0f), uniforms), 1.0f);
}

fragment float4 shadertoyBloomBlurVFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    constant FrameUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return float4(shadertoyBloomBlurAtlas(sourceTexture, linearSampler, in.uv, float2(0.0f, 0.5f), uniforms), 1.0f);
}

fragment float4 shadertoyBlackHoleCompositeFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> baseTexture [[texture(0)]],
    texture2d<float, access::sample> bloomTexture [[texture(1)]],
    constant FrameUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return float4(shadertoyBloomComposite(baseTexture, bloomTexture, linearSampler, in.uv, uniforms), 1.0f);
}

fragment float4 mandelbrotFragment(
    VertexOut in [[stage_in]],
    constant FrameUniforms &uniforms [[buffer(0)]]
) {
    const float2 resolution = max(uniforms.resolution, float2(1.0f));
    const float2 pixel = in.uv * resolution;
    const int maxIter = clamp(uniforms.maxIter, 260, 4096);
    const float scale = fabs(uniforms.scaleHi + uniforms.scaleLo);
    float3 color = float3(0.0f);

    const bool isRayMarched3D = uniforms.fractalType == 6
        || uniforms.fractalType == 7
        || uniforms.fractalType == 8
        || uniforms.fractalType == 18
        || uniforms.fractalType == 19
        || uniforms.fractalType == 20
        || uniforms.fractalType == 22
        || uniforms.fractalType == 24
        || (uniforms.fractalType >= 25 && uniforms.fractalType <= 46);
    const int aa = (isRayMarched3D && uniforms.antialiasingMode == 0)
        ? 1
        : antialiasingSamples(uniforms.antialiasingMode, maxIter);
    for (int y = 0; y < aa; y++) {
        for (int x = 0; x < aa; x++) {
            const float2 subPixel = pixel + (float2(float(x), float(y)) + 0.5f) / float(aa);
            float2 uv = (2.0f * subPixel - resolution) / resolution.y;

            if (uniforms.fractalType == 6 || uniforms.fractalType == 18) {
                color += renderMandelbulb3D(uv, uniforms, maxIter);
                continue;
            }

            if (uniforms.fractalType == 43) {
                color += renderGalaxyUniverses3DScene(uv, uniforms);
                continue;
            }

            if (uniforms.fractalType == 46) {
                color += renderRelativisticBlackHole3dSyzD(uv, uniforms);
                continue;
            }

            if (uniforms.fractalType == 42) {
                color += renderBlackHole3D(uv, uniforms);
                continue;
            }

            if (uniforms.fractalType >= 25 && uniforms.fractalType <= 41) {
                color += renderFractal4D(uv, uniforms, maxIter);
                continue;
            }

            if (uniforms.fractalType == 7
                || uniforms.fractalType == 8
                || uniforms.fractalType == 19
                || uniforms.fractalType == 20
                || uniforms.fractalType == 22
                || uniforms.fractalType == 24) {
                color += renderShadertoy3D(uv, uniforms, maxIter);
                continue;
            }

            uv = animatedShadertoyUV(uv, uniforms.time);
            const float co = cos(uniforms.rotation);
            const float si = sin(uniforms.rotation);
            uv = float2(uv.x * co - uv.y * si, uv.x * si + uv.y * co);

            const DS2 point = complexFromUV(uv.x, -uv.y, uniforms);
            const float2 pointApprox = float2(dsToFloat(point.x), dsToFloat(point.y));
            if (uniforms.fractalType >= 7) {
                color += renderShadertoyResult(pointApprox, uv, uniforms);
                continue;
            }

            float escape = 0.0f;
            if (uniforms.fractalType == 1) {
                escape = shadertoyJulia(point, uniforms.juliaConstant, maxIter, scale, uniforms.bailoutRadius, uniforms.precisionMode);
            } else if (uniforms.fractalType == 2) {
                escape = burningShip(pointApprox, maxIter, uniforms.bailoutRadius);
            } else if (uniforms.fractalType == 3) {
                escape = newtonFractal(pointApprox, maxIter);
            } else if (uniforms.fractalType == 4) {
                escape = multibrot(pointApprox, maxIter, uniforms.bailoutRadius, uniforms.multibrotPower);
            } else if (uniforms.fractalType == 5) {
                escape = mandelbox2D(pointApprox, maxIter, uniforms.bailoutRadius);
            } else {
                escape = shadertoyMandelbrot(point, maxIter, scale, uniforms.bailoutRadius, uniforms.precisionMode);
            }

            if (uniforms.smoothColoring == 0 && escape >= 0.5f) {
                escape = floor(escape);
            }

            if (escape < 0.5f) {
                color += uniforms.backgroundColor.rgb;
            } else {
                color += paletteColor(escape, uniforms.colorPalette);
            }
        }
    }

    color /= float(aa * aa);
    color = saturate((color - 0.5f) * max(uniforms.contrast, 0.0f) + 0.5f);
    color *= max(uniforms.exposure, 0.0f);
    return float4(color, 1.0f);
}
