Shader "Custom/TohoLogosBackground"
{
    Properties
    {
        _BGColor ("Background Color (ベースの闇)", Color) = (0.01, 0.04, 0.08, 1.0)       
        _CoreColor ("Core Glow Color (中心のまばゆい光)", Color) = (0.45, 0.95, 1.0, 1.0)   
        _FlashColorA ("Line Color A (鮮烈なコバルト青)", Color) = (0.0, 0.45, 0.85, 1.0)   
        _FlashColorB ("Line Color B (ゴールド橙)", Color) = (0.95, 0.55, 0.25, 1.0)       
        
        _CenterY ("Center Y (中心の高さ)", Range(0.0, 1.0)) = 0.58                        
        _Speed ("Tunnel Speed (噴き出す速度)", Float) = 3.5                                
        _LineDensity ("Line Density (光の線の粗さ)", Float) = 14.0                       
        _CoreSize ("Core Size (中心の光の大きさ)", Range(0.05, 0.5)) = 0.22            
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
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

            float4 _BGColor;
            float4 _CoreColor;
            float4 _FlashColorA;
            float4 _FlashColorB;
            float _CenterY;
            float _Speed;
            float _LineDensity;
            float _CoreSize;

            float hash(float n)
            {
                return frac(sin(n) * 43758.5453123);
            }

            float noise(float p)
            {
                float i = floor(p);
                float f = frac(p);
                float u = f * f * (3.0 - 2.0 * f);
                return lerp(hash(i), hash(i + 1.0), u);
            }

            float getFBMNoise(float p)
            {
                float v = 0.0;
                v += 0.5 * noise(p);
                v += 0.25 * noise(p * 2.3);
                v += 0.125 * noise(p * 4.7);
                return v;
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
                float2 uv = input.uv;
                float time = _Time.y;

                float2 center = float2(0.5, _CenterY);
                float2 toCenter = uv - center;

                float dist = length(toCenter);
                float angle = atan2(toCenter.y, toCenter.x);

                float angleParam = angle * _LineDensity;
                float rawLines = getFBMNoise(angleParam);

                float pY = 1.0 / (dist + 0.005);
                float forwardScroll = (rawLines * 12.0) - (time * _Speed) + (pY * 0.4);
                
                float lineMask = saturate(sin(forwardScroll) * 0.5 + 0.5);
                lineMask = pow(lineMask, 2.5); 

                float colorPattern = noise(angleParam * 0.6 + time * 0.1);
                float3 lineBaseColor = _BGColor.rgb;

                if (colorPattern > 0.3)
                {
                    lineBaseColor = lerp(_FlashColorA.rgb, float3(0.5, 0.9, 1.0), lineMask * 0.4);
                }
                if (colorPattern > 0.68)
                {
                    lineBaseColor = lerp(_FlashColorB.rgb, float3(1.0, 0.9, 0.6), lineMask * 0.5);
                }

                float3 finalColor = lerp(_BGColor.rgb, lineBaseColor, lineMask * 0.85);

                // 1. ノイズの密度を上げ（18.0 25.0）、トゲをより細かくシャープに
                float coreSpikes = getFBMNoise(angle * 25.0 + time * 0.5);
                
                // 2. 中心の光の広がりを _CoreSize (初期値0.22) でギュッとコンパクトに制限
                float coreMask = smoothstep(_CoreSize, 0.0, dist);
                
                // 3. トゲの根本を削ぎ落として、より鋭いトゲにするために pow(..., 2.0) を適用
                float dynamicCore = pow(coreMask, 2.0) * (0.3 + coreSpikes * 1.2);

                // 4. 水色のグロウ光線と、中心の一番白いコアを綺麗に重ねる
                finalColor += _CoreColor.rgb * dynamicCore * 2.5;
                finalColor += float3(1, 1, 1) * pow(coreMask, 6.0) * 4.0; // 完全な真ん中だけがピンポイントで白飛びする

                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
