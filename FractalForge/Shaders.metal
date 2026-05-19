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
        || uniforms.fractalType == 24;
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
