Shader "Custom/Hole"
{
    Properties
    {
        _MainTex ("Base (RGB)", 2D) = "white" {}
        _CloudColorTop ("Cloud Color Top", Color) = (0.2, 0.5, 0.9, 1.0)
        _CloudColorBottom ("Cloud Color Bottom", Color) = (0.05, 0.15, 0.4, 1.0)
        _BGColor ("Hole/Background Color (穴の色)", Color) = (0.0, 0.0, 0.0, 1.0) // 真っ黒な穴
        _CloudDensity ("Cloud Density", Range(0.1, 0.9)) = 0.5
        _PixelSize ("Pixel Size (ドットの粗さ)", Float) = 240.0
        
        // --- 穴の調整用プロパティ ---
        _HoleSize ("Hole Size (穴の大きさ)", Range(0.0, 0.5)) = 0.15
        _HoleEdge ("Hole Edge Blur (フチのボカシ値)", Range(0.001, 0.1)) = 0.01
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

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _CloudColorTop;
            float4 _CloudColorBottom;
            float4 _BGColor;
            float _CloudDensity;
            float _PixelSize;
            float _HoleSize;
            float _HoleEdge;

            float hash(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
            }

            float noise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);

                return lerp(lerp(hash(i + float2(0.0, 0.0)), hash(i + float2(1.0, 0.0)), u.x),
                            lerp(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), u.x), u.y);
            }

            float2 getPolarCoord(float2 uv)
            {
                float2 p = uv * 2.0 - 1.0;
                float r = length(p);
                float a = atan2(p.y, p.x);
                return float2(r, a);
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
                // ドット絵の粗さに固定
                float2 pixelatedUV = floor(uv * _PixelSize) / _PixelSize;
                float time = _Time.y;

                // 極座標の取得
                float2 polar = getPolarCoord(pixelatedUV);
                float r = polar.x; // 中心からの距離
                float a = polar.y; // 角度

                // 雲ノイズの計算（奥に向かって吸い込まれる動き）
                float n = noise(float2(r * 10.0 + time * 5.0, a * 5.0 + time * 2.0));
                float cloudMask = smoothstep(_CloudDensity, _CloudDensity + 0.1, n);

                // 雲の色グラデーション
                float3 cloudColor = lerp(_CloudColorBottom.rgb, _CloudColorTop.rgb, r);

                // 中心からの距離(r)が _HoleSize より小さい部分をくり抜くマスク
                float holeMask = smoothstep(_HoleSize, _HoleSize + _HoleEdge, r);

                // 雲のマスクに穴のマスクを掛け合わせる（穴の部分を消去）
                float finalCloudMask = cloudMask * holeMask;

                // 最終カラー：背景の黒（穴）の上に、くり抜かれた雲を重ねる
                float3 finalColor = lerp(_BGColor.rgb, cloudColor, finalCloudMask);

                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}