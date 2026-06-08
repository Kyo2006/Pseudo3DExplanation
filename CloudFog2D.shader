Shader "Custom/CloudFog2D"
{
    Properties
    {
        _SkyColorTop ("Sky Color Top", Color) = (0.28, 0.28, 0.45, 1.0)
        _SkyColorBottom ("Sky Color Bottom", Color) = (0.95, 0.75, 0.55, 1.0)
        _CloudBaseColor ("Cloud Base Color (光)", Color) = (0.98, 0.88, 0.75, 1.0)
        _CloudShadowColor ("Cloud Shadow Color (影)", Color) = (0.35, 0.32, 0.45, 1.0)
        
        _HorizonY ("Horizon Y (地平線の高さ)", Range(0.0, 1.0)) = 0.52
        _Speed ("Forward Speed (超高速)", Float) = 40.0 // 初期値を爆速に設定
        _CloudScale ("Cloud Scale", Float) = 0.5
        _ShadowIntensity ("Shadow Intensity", Range(0.0, 2.0)) = 1.3
        
        _PixelSize ("Pixel Size (ドットの粗さ)", Float) = 180.0 // レトロ感を出すためにやや粗めに
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

            float4 _SkyColorTop;
            float4 _SkyColorBottom;
            float4 _CloudBaseColor;
            float4 _CloudShadowColor;
            float _HorizonY;
            float _Speed;
            float _CloudScale;
            float _ShadowIntensity;
            float _PixelSize;

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

            // 超高速時にディテールが潰れすぎないよう、ループごとにノイズの乗り方を調整
            float fbm(float2 p)
            {
                float v = 0.0;
                float amplitude = 0.5;
                float2x2 m = float2x2(1.6,  1.2, -1.2,  1.6);
                for (int i = 0; i < 5; i++) // 高速化に伴い5ループに最適化
                {
                    v += amplitude * noise(p);
                    p = mul(m, p) * 1.9;
                    amplitude *= 0.42;
                }
                return v;
            }

            // 【超高速スクロール用の3Dパース変換】
            float2 getPerspectivePos(float2 uv, float depth, float time)
            {
                // 超高速飛行時の歪みを綺麗に見せるため、分母の安定化係数を微調整（0.015）
                float perspectiveY = 1.0 / (depth + 0.015);
                float perspectiveX = (uv.x - 0.5) * perspectiveY;

                float2 p;
                p.x = perspectiveX * _CloudScale;
                
                // time * _Speed で奥から手前へ爆速で流す
                p.y = perspectiveY * _CloudScale + (time * _Speed);
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
                // 1. まず画面全体のUVをドット絵化（モザイク化）
                float2 uv = floor(input.uv * _PixelSize) / _PixelSize;
                
                float4 finalColor = float4(0, 0, 0, 1);

                // --- 空の描画 ---
                if (uv.y >= _HorizonY)
                {
                    float skyT = (uv.y - _HorizonY) / (1.0 - _HorizonY);
                    finalColor = lerp(_SkyColorBottom, _SkyColorTop, pow(skyT, 0.8));
                }
                // --- 超高速ドット絵雲海の描画 ---
                else
                {
                    float depth = _HorizonY - uv.y;
                    float time = _Time.y;

                    // ドット化されたUVを元にパース空間を計算
                    float2 p = getPerspectivePos(uv, depth, time);
                    float density = fbm(p);

                    // 高速移動に耐えうるパキッとした陰影を計算
                    float2 lightDir = float2(-0.04, 0.03); // 光源（左奥）
                    float2 pLight = getPerspectivePos(uv + lightDir * depth, depth, time);
                    float densityLight = fbm(pLight);

                    // 影のコントラストを強めにして、ドットのドットらしさを強調
                    float shadow = saturate(densityLight - density) * _ShadowIntensity;
                    density = smoothstep(0.25, 0.65, density);

                    float4 cloudColor = lerp(_CloudBaseColor, _CloudShadowColor, shadow);
                    cloudColor = lerp(cloudColor * 0.4, cloudColor, density); // 影の底をさらに暗く引き締め

                    // 地平線の空気遠近フォグ（ここもドット絵のマス目に沿って溶ける）
                    float fogFactor = smoothstep(0.02, 0.15, depth);
                    
                    float4 terrainColor = lerp(_CloudShadowColor * 0.6, cloudColor, density);
                    finalColor = lerp(_SkyColorBottom, terrainColor, fogFactor);
                }

                return finalColor;
            }
            ENDHLSL
        }
    }
}