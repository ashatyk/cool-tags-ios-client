#include <metal_stdlib>
using namespace metal;

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

vertex Varyings vert(uint vid [[vertex_id]]) {
    const float2 pos[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
    };
    Varyings o; float2 p = pos[vid];
    o.position = float4(p, 0, 1);
    o.uv = p * 0.5 + 0.5;
    o.uv.y = 1.0 - o.uv.y;
    return o;
}

struct Uniforms {
    float2 uResolution;
    float  uTime;
    float3 _pad;
};

struct EffectUniforms {
    float  uEdgeFeatherPx;
    float  uCenterTranslation;
    float4 uColor0;
    float4 uColor1;
    float4 uColor2;
    float3 uRayStrength3;
    float3 uRayLengthPx3;
    float3 uRaySharpness3;
    float3 uRayDensity3;
    float3 uRaySpeed3;
    float3 uRayFalloff3;
    float3 uRayStartSoftPx3;
    float3 uJoinSoftness3;
};

struct PolyUniforms {
    float4 uPointAABB;        // [minX,minY,maxX,maxY] in [0..1]
    int    uPointTexelCount;
    float2 uPointTextureDim;  // (w,h)
    int    _pad;
};

constant float PI       = 3.14159265359f;
constant float INV_TAU  = 0.15915494309f;   // 1/(2π)

#define MAX_POINTS 1024

inline uint uhash(uint x){
    x ^= (x >> 16u);
    x *= 2246822519u;
    x ^= (x >> 13u);
    x *= 3266489917u;
    x ^= (x >> 16u);
    return x;
}

inline float hash11(float x){
    uint u = as_type<uint>(x);
    return float(uhash(u)) * (1.0f / 4294967296.0f);
}

inline float pick3(float3 v, int i){
    return (i==0)? v.x : ((i==1)? v.y : v.z);
}
inline float3 colorPick(int i, constant EffectUniforms& E){
    return (i==0)? E.uColor0.rgb : ((i==1)? E.uColor1.rgb : E.uColor2.rgb);
}


// GEOMETRY: чтение точек полигона
inline float2 readPointN(int i, constant PolyUniforms& P, texture2d<float> pts, sampler /*unused*/) {
    int w = max(1, (int)P.uPointTextureDim.x);
    uint2 xy = uint2(uint(i % w), uint(i / w));
    float4 texel = pts.read(xy, 0);
    return texel.rg;
}

inline float2 readPointPx(int i, constant Uniforms& U, constant PolyUniforms& P, texture2d<float> pts, sampler s) {
    return readPointN(i, P, pts, s) * U.uResolution;
}

// SDF: расстояние до полигона + флаг inside (четно-нечетное правило)
inline float2 signedDistanceField(float2 p,
  constant Uniforms& U,
  constant PolyUniforms& P,
  texture2d<float> pts,
  sampler s) {
    float bestD = 1e20f;
    bool  inside = false;

    int N = min(P.uPointTexelCount, (int)MAX_POINTS);
    
    const float EPS = 1e-6f;

    if (N <= 0) return float2(bestD, 0.0f);
    
    float2 a = readPointPx(0, U, P, pts, s);
    
    for (int i = 0; i < MAX_POINTS; ++i) {
        if (i >= N) break;
        int j = (i + 1 == N) ? 0 : (i + 1);
        float2 b  = readPointPx(j, U, P, pts, s);
        float2 ab = b - a;

        if (fabs(ab.x) + fabs(ab.y) > EPS) {
            float2 pa = p - a;
            float  denom = max(dot(ab, ab), 1e-8f);
            float  h = clamp(dot(pa, ab) / denom, 0.0f, 1.0f);
            bestD = min(bestD, length(pa - ab * h));

            if (((a.y <= p.y) && (b.y > p.y)) || ((b.y <= p.y) && (a.y > p.y)) && fabs(ab.y) > EPS) {
                float xInt = a.x + (p.y - a.y) * ab.x / ab.y;
                if (p.x < xInt) inside = !inside;
            }
        }
        a = b;
    }
    return float2(bestD, inside ? 1.0f : 0.0f);
}


inline float tri(float x){ return fabs(fract(x) - 0.5f); }
inline float3 tri3(float3 p){ return float3(tri(p.x), tri(p.y), tri(p.z)); }
inline float triNoise3D(float3 p, float spd, float uTime){
    float z = 0.3f, rz = 0.1f; float3 bp = p;
    for (float i = 0.0f; i <= 3.0f; i += 1.0f) {
        float3 dg = tri3(bp * 0.01f);
        p  += (dg + uTime * 0.1f * spd);
        bp *= 2.0f; z *= 0.9f; p *= 1.6f;
        rz += tri(p.z + tri(0.6f * p.x + 0.1f * tri(p.y))) / z;
    }
    return smoothstep(0.0f, 8.0f, rz + sin(rz + sin(z) * 2.8f) * 2.2f);
}

inline float fastAtan2(float y, float x){
    float ax = fabs(x), ay = fabs(y);
    float a  = min(ax, ay) / max(ax + 1e-8f, ay + 1e-8f);
    float s  = a * a;
    float r = (((-0.0464964749f * s + 0.15931422f) * s - 0.327622764f) * s + 0.999787841f) * a;
    if (ay > ax) r = 1.57079637f - r; if (x  < 0.0f) r = 3.14159274f - r; return (y < 0.0f) ? -r : r;
}
inline float smoothMax2(float a, float b, float k){
    float h = clamp(0.5f + 0.5f * (a - b) / k, 0.0f, 1.0f);
    return mix(b, a, h) + k * h * (1.0f - h);
}

inline float smoothMax3(float a, float b, float c, float k){ return smoothMax2(smoothMax2(a, b, k), c, k); }

// Интенсивность одного цветового слоя
inline float shadeColor(int i, float uu, float d, float edgeMask, constant Uniforms& U, constant EffectUniforms& E){
    float density = pick3(E.uRayDensity3, i);
    float rayId   = floor(uu * density);
    float r1 = hash11(float(i) + rayId + 13.37f);
    float r2 = hash11(float(i) + rayId + 71.17f);
    float r3 = hash11(float(i) + rayId + 131.9f);
    float lenVar   = mix(0.65f, 1.35f, r1);
    float ampVar   = mix(0.70f, 1.25f, r2);
    float speedVar = mix(0.50f, 1.10f, r3);
    float rayLen = pick3(E.uRayLengthPx3, i);
    float startS = pick3(E.uRayStartSoftPx3, i);
    float dShift = max(0.0f, d - startS);
    float maxLen = max(1.0f, rayLen * lenVar);
    float t = clamp(dShift / maxLen, 0.0f, 1.0f);
    float phase = 0.1f * pick3(E.uRaySpeed3, i) * speedVar;
    float base  = uu * density + r1 * 6.2831853f; // 2π
    float du    = 0.5f / max(density, 1.0f);
    float s0 = triNoise3D(float3(base, 0.0f, uu * density), phase, U.uTime);
    float sL = triNoise3D(float3((uu - du) * density + r1 * 6.2831853f, 0.0f, (uu - du) * density), phase, U.uTime);
    float sR = triNoise3D(float3((uu + du) * density + r1 * 6.2831853f, 0.0f, (uu + du) * density), phase, U.uTime);
    float kJoin = mix(0.1f, 0.6f, clamp(pick3(E.uJoinSoftness3, i), 0.0f, 1.0f));
    float s = smoothMax3(s0, sL, sR, kJoin);
    float sharp = clamp(pick3(E.uRaySharpness3, i), 0.0f, 1.0f);
    float th    = mix(0.60f, 0.95f, t);
    float core  = smoothstep(th, 1.0f, s);
    core = pow(core, mix(1.2f, 10.0f, t * sharp));
    float taper = pow(1.0f - t, mix(0.8f, 4.0f, sharp));
    float fall     = exp(-pick3(E.uRayFalloff3, i) * d);
    float strength = pick3(E.uRayStrength3, i);
    return strength * ampVar * core * taper * fall * edgeMask;
}

// Fragment
fragment half4 frag(Varyings in [[stage_in]],
   constant Uniforms& U [[buffer(0)]],
   constant EffectUniforms& E [[buffer(1)]],
   constant PolyUniforms&  P [[buffer(2)]],
   texture2d<float> ptsTex [[texture(0)]],
   sampler pointSamp [[sampler(0)]]) {
    if (P.uPointTexelCount < 2) { return half4(0.0); }

    float2 p = in.uv * U.uResolution;
    float2 bbMin  = P.uPointAABB.xy * U.uResolution;
    float2 bbMax  = P.uPointAABB.zw * U.uResolution;
    float2 center = 0.5f * (bbMin + bbMax);

    float2 translatedP = mix(p, center, E.uCenterTranslation);

    float2 di = signedDistanceField(translatedP, U, P, ptsTex, pointSamp);
    float  d  = di.x; bool inside = di.y > 0.5f;
    if (inside) { return half4(0.0); }

    float edgeMask = smoothstep(E.uEdgeFeatherPx - d, E.uEdgeFeatherPx + d, log(max(d, 1e-6f)));

    float2 v   = p - center;
    float  ang = fastAtan2(v.y, v.x);
    float  uu  = (ang + PI) * INV_TAU;

    float3 col = float3(0.0); float sumI = 0.0;
    for (int c = 0; c < 3; ++c){
        float I = shadeColor(c, uu, d, edgeMask, U, E);
        col  += colorPick(c, E) * I;
        sumI += I;
    }
    return half4(float4(col, clamp(sumI, 0.0f, 1.0f)));
}
