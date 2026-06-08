Shader "Custom/RealisticRippleWater2D"
{
    Properties
    {
        _WaterColorDeep ("Water Color Deep (深い水の色)", Color) = (0.05, 0.18, 0.42, 1.0)     // 外側の深く澄んだ紺・青
        _WaterColorShallow ("Water Color Shallow (浅い水の色)", Color) = (0.2, 0.75, 0.85, 1.0) // 中心の光が透ける明るい水色
        _CausticColor ("Caustic Color (反射・波頭)", Color) = (1.0, 1.0, 1.0, 1.0)              // 太陽光の眩しい純白のきらめき
        
        _WaveSpeed ("Wave Speed (波の広がる速さ)", Float) = 0.8
        _WaveScale ("Wave Scale (波の細かさ)", Float) = 25.0
        _ReflectionIntensity ("Reflection (光の反射強度)", Range(0.0, 2.0)) = 1.3
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float4 objectScale  : TEXCOORD0; 
                float2 uv           : TEXCOORD1;
            };

            float4 _WaterColorDeep;
            float4 _WaterColorShallow;
            float4 _CausticColor;
            float _WaveSpeed;
            float _WaveScale;
            float _ReflectionIntensity;

            float hash(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
            }

            float noise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

                return lerp(lerp(hash(i + float2(0.0,0.0)), hash(i + float2(1.0,0.0)), u.x),
                            lerp(hash(i + float2(0.0,1.0)), hash(i + float2(1.0,1.0)), u.x), u.y);
            }

            float fbm(float2 p)
            {
                float v = 0.0;
                float amplitude = 0.5;
                for (int i = 0; i < 4; i++)
                {
                    v += amplitude * noise(p);
                    p *= 2.2;
                    amplitude *= 0.45;
                }
                return v;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;

                float scaleX = length(GetObjectToWorldMatrix()._m00_m10_m20);
                float scaleY = length(GetObjectToWorldMatrix()._m01_m11_m21);
                output.objectScale = float4(scaleX, scaleY, 1.0, 1.0);

                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float aspect = input.objectScale.x / input.objectScale.y;
                float2 uv = input.uv;
                uv.x *= aspect;
                
                float2 center = float2(0.5 * aspect, 0.5);
                float2 toCenter = uv - center;
                float dist = length(toCenter);
                
                float time = _Time.y;

                // 水面の有機的なゆらぎ
                float2 noiseUV = uv * 5.0;
                float2 distort = float2(
                    fbm(noiseUV + float2(time * 0.1, time * 0.05)),
                    fbm(noiseUV - float2(time * 0.05, time * 0.1))
                );
                
                // 円形波紋のパース計算
                float modifiedDist = dist + distort.x * 0.08;
                
                float wave1 = sin(modifiedDist * _WaveScale - time * _WaveSpeed * 4.0);
                float wave2 = sin(modifiedDist * (_WaveScale * 1.5) + time * _WaveSpeed * 2.0);
                float combinedWave = lerp(wave1, wave2, 0.3);

                // 中心から外側へ向かう青の水の深みグラデーション
                float lightGlow = smoothstep(0.6, 0.0, dist);
                float3 waterBaseColor = lerp(_WaterColorDeep.rgb, _WaterColorShallow.rgb, pow(lightGlow, 1.2));

                // 太陽光のリアルなエッジ反射効果
                float waveEdge = smoothstep(0.1, 0.8, combinedWave) * (1.0 - smoothstep(0.6, 1.0, combinedWave));
                
                // 光の白さを際立たせる加算ブレンド風の計算
                float3 reflection = _CausticColor.rgb * waveEdge * _ReflectionIntensity;

                // 最終カラー合成
                float3 finalColor = waterBaseColor + reflection;

                // 画面端のフェード
                float edgeAlpha = smoothstep(0.0, 0.02, input.uv.x) * smoothstep(1.0, 0.98, input.uv.x) *
                                  smoothstep(0.0, 0.02, input.uv.y) * smoothstep(1.0, 0.98, input.uv.y);

                return float4(finalColor, edgeAlpha);
            }
            ENDHLSL
        }
    }
}
