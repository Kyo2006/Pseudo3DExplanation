Shader "Custom/CloudAxelay2D"
{
    Properties
    {
        _CloudBaseColor ("Cloud Base Color (â_ÇÃåıñ ÅEîñâ©ìç)", Color) = (0.92, 0.82, 0.75, 1.0)
        _CloudShadowColor ("Cloud Shadow Color (â_ÇÃâeñ ÅEê[Ç¢éá)", Color) = (0.32, 0.25, 0.42, 1.0)
        _HorizonColor ("Horizon Fog Color (ç≈âúÇÃÉÇÉÑÅEâ©ã‡)", Color) = (0.95, 0.72, 0.55, 1.0)
        
        _Speed ("Forward Speed", Float) = 6.0
        _CloudScale ("Cloud Scale", Float) = 0.35
        _ShadowIntensity ("Shadow Intensity", Range(0.0, 2.0)) = 1.4
        _PixelSize ("Pixel Size (SFCècâëúìx)", Float) = 224.0
        
        _RollPower ("Roll Power", Range(1.0, 5.0)) = 3.0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        Blend SrcAlpha OneMinusSrcAlpha
        LOD 100

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
                float2 uv           : TEXCOORD0;
            };

            float4 _CloudBaseColor;
            float4 _CloudShadowColor;
            float4 _HorizonColor;
            float _Speed;
            float _CloudScale;
            float _ShadowIntensity;
            float _PixelSize;
            float _RollPower;

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
                float2x2 m = float2x2(1.6,  1.2, -1.2,  1.6);
                for (int i = 0; i < 5; i++)
                {
                    v += amplitude * noise(p);
                    p = mul(m, p) * 1.9;
                    amplitude *= 0.42;
                }
                return v;
            }

            float2 getAxelayWarpPos(float2 uv, float depth, float time)
            {
                // depth=0ÅiâÊñ ç≈è„ïîÅjÇ≈í¥à≥èkÇ≥ÇÍÅAêÇíºÇ…óßÇøè„Ç™ÇÈï«ÇçÏÇÈ
                float curve = pow(saturate(depth), _RollPower);
                
                float perspectiveY = 1.0 / (1.001 - curve);
                float perspectiveX = (uv.x - 0.5) * perspectiveY;

                float2 p;
                p.x = perspectiveX * _CloudScale;
                p.y = curve * (_CloudScale * 10.0) + (time * _Speed);
                return p;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = floor(input.uv * _PixelSize) / _PixelSize;
                
                // âÊñ ÇÃàÍî‘è„Ç™è¡é∏ì_ÅiínïΩê¸ÇÃç≈âúÅjÇ…Ç»ÇÈÇÊÇ§Ç…ê›íË
                float depth = 1.0 - uv.y; 
                float time = _Time.y;

                float2 p = getAxelayWarpPos(uv, depth, time);
                float density = fbm(p);

                float2 lightDir = float2(0.02, 0.01);
                float2 pLight = getAxelayWarpPos(uv + lightDir * depth, depth, time);
                float densityLight = fbm(pLight);

                float shadow = saturate(densityLight - density) * _ShadowIntensity;
                density = smoothstep(0.22, 0.62, density);

                float4 cloudColor = lerp(_CloudBaseColor, _CloudShadowColor, shadow);
                cloudColor = lerp(cloudColor * 0.45, cloudColor, density);

                float fogFactor = smoothstep(0.0, 0.05, depth);
                float4 terrainColor = lerp(_CloudShadowColor * 0.8, cloudColor, density);
                
                float4 finalColor = lerp(_HorizonColor, terrainColor, fogFactor);

                float edgeMask = smoothstep(0.0, 0.02, uv.y);
                finalColor *= edgeMask;

                return finalColor;
            }
            ENDHLSL
        }
    }
}