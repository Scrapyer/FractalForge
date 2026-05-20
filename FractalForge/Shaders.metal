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

inline float3 renderShadertoyWxdfzjBase(float2 uv, constant FrameUniforms &uniforms) {
    const float time = uniforms.time;
    float2 p = uv * 0.86f;
    const float co = cos(uniforms.rotation * 0.35f);
    const float si = sin(uniforms.rotation * 0.35f);
    p = float2(p.x * co - p.y * si, p.x * si + p.y * co);

    float3 color = shadertoySourceStarField(p, time, float3(0.34f, 0.48f, 0.86f));
    const float r = length(p);
    const float angle = atan2(p.y, p.x);
    const float spin = 0.99f;

    const float horizon = 0.235f;
    const float photon = 0.335f + 0.018f * sin(angle + time * 0.12f);
    const float frameDrag = spin * 0.16f * exp(-r * 4.0f);
    const float lens = 0.16f / max(abs(p.x) + 0.13f, 0.13f);
    const float diskY = p.y + 0.045f * sin(p.x * 4.0f + frameDrag * 7.0f) - sign(p.y + 0.0001f) * lens * exp(-abs(p.x) * 2.3f) * 0.20f;
    const float diskRadius = abs(p.x);
    const float diskMask = smoothstep(0.19f, 0.34f, diskRadius) * (1.0f - smoothstep(1.72f, 2.08f, diskRadius));
    const float thickness = 0.026f + 0.040f * smoothstep(0.2f, 1.5f, diskRadius);
    const float diskCore = exp(-pow(diskY / max(thickness, 0.001f), 2.0f)) * diskMask;
    const float turbulentLane = 0.66f + 0.34f * sin(46.0f * log(max(diskRadius, 0.08f)) + angle * 2.4f - time * 2.0f);
    const float granular = 0.78f + 0.22f * fbm2D(float2(angle * 3.0f, diskRadius * 9.0f) + time * 0.08f);
    const float doppler = 0.54f + 1.42f * smoothstep(-0.92f, 0.95f, -p.x + 0.12f * p.y);
    const float innerHeat = exp(-diskRadius * 1.55f);
    const float3 coldBlue = float3(0.20f, 0.42f, 1.35f);
    const float3 hotBlue = float3(1.10f, 1.38f, 1.75f);
    const float3 diskColor = mix(coldBlue, hotBlue, innerHeat) * diskCore * turbulentLane * granular * doppler * 4.8f;
    color += diskColor;

    const float ring = exp(-pow((r - photon) / 0.012f, 2.0f));
    const float ringGlow = exp(-pow((r - photon * 1.08f) / 0.055f, 2.0f));
    const float ringAsym = 0.70f + 0.65f * saturate(cos(angle - 0.25f) * spin);
    color += ring * ringAsym * float3(6.8f, 8.2f, 10.5f);
    color += ringGlow * float3(0.45f, 0.74f, 1.55f);

    const float jetX = abs(p.x + 0.035f * sin(p.y * 7.0f + time));
    const float jet = exp(-pow(jetX / (0.025f + abs(p.y) * 0.055f), 2.0f))
        * smoothstep(0.28f, 0.62f, abs(p.y))
        * (1.0f - smoothstep(1.55f, 2.1f, abs(p.y)));
    color += jet * float3(0.20f, 0.62f, 2.8f) * (0.72f + 0.28f * sin(abs(p.y) * 18.0f - time * 2.0f));

    const float shadow = 1.0f - smoothstep(horizon, horizon + 0.018f, r);
    color = mix(color, float3(0.0f), shadow);
    color *= 1.0f - 0.34f * exp(-pow((r - horizon * 1.22f) / 0.065f, 2.0f));
    return max(color, float3(0.0f));
}

inline float3 renderShadertoyW3BBzKBase(float2 uv, constant FrameUniforms &uniforms) {
    const float time = uniforms.time;
    float2 p = uv * 0.82f;
    const float co = cos(uniforms.rotation * 0.18f);
    const float si = sin(uniforms.rotation * 0.18f);
    p = float2(p.x * co - p.y * si, p.x * si + p.y * co);

    float3 color = shadertoySourceStarField(p, time, float3(0.90f, 0.78f, 0.55f));
    const float r = length(p);
    const float angle = atan2(p.y, p.x);

    const float horizon = 0.265f;
    const float photon = 0.365f;
    const float lensBend = 0.19f / max(abs(p.x) + 0.18f, 0.18f);
    const float diskY = p.y - sign(p.y + 0.0001f) * lensBend * exp(-abs(p.x) * 2.2f) * 0.26f;
    const float diskRadius = abs(p.x);
    const float diskMask = smoothstep(0.22f, 0.38f, diskRadius) * (1.0f - smoothstep(1.88f, 2.26f, diskRadius));
    const float thickness = 0.033f + 0.050f * smoothstep(0.2f, 1.7f, diskRadius);
    const float diskCore = exp(-pow(diskY / max(thickness, 0.001f), 2.0f)) * diskMask;
    const float rings = 0.58f + 0.42f * sin(58.0f * log(max(diskRadius, 0.075f)) + angle * 1.7f - time * 1.35f);
    const float turbulence = 0.80f + 0.20f * fbm2D(float2(angle * 2.4f, diskRadius * 8.5f) + time * 0.055f);
    const float doppler = 0.62f + 1.15f * smoothstep(-0.9f, 0.9f, p.x - 0.08f * p.y);
    const float heat = exp(-diskRadius * 1.35f);
    const float3 red = float3(1.35f, 0.18f, 0.045f);
    const float3 gold = float3(1.45f, 0.78f, 0.24f);
    const float3 white = float3(1.7f, 1.42f, 0.95f);
    const float3 diskColor = mix(mix(red, gold, heat), white, heat * heat) * diskCore * rings * turbulence * doppler * 5.6f;
    color += diskColor;

    const float primary = exp(-pow((r - photon) / 0.014f, 2.0f));
    const float secondary = exp(-pow((r - photon * 1.33f) / 0.026f, 2.0f));
    const float tertiary = exp(-pow((r - photon * 1.72f) / 0.044f, 2.0f));
    const float broad = exp(-pow((r - photon * 1.09f) / 0.074f, 2.0f));
    const float asym = 0.74f + 0.55f * saturate(cos(angle + 0.15f));
    color += primary * asym * float3(8.0f, 4.0f, 1.15f);
    color += secondary * float3(3.0f, 1.55f, 0.56f);
    color += tertiary * float3(1.1f, 0.52f, 0.18f);
    color += broad * float3(0.85f, 0.35f, 0.12f);

    const float shadow = 1.0f - smoothstep(horizon, horizon + 0.020f, r);
    color = mix(color, float3(0.0f), shadow);
    color *= 1.0f - 0.42f * exp(-pow((r - horizon * 1.18f) / 0.075f, 2.0f));
    return max(color, float3(0.0f));
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
