Shader "Custom/2DWaterReflectionURP"
{
    Properties
    {
        [HideInInspector] _MainTex ("Main Tex", 2D) = "white" {} // Sprite Renderer用
        _ReflectTex ("Reflection Target (反射させる画像)", 2D) = "white" {}
        _WaveScale ("Wave Scale (波の細かさ)", Float) = 10.0
        _WaveStrength ("Wave Strength (くねくねの強さ)", Float) = 0.02
        _WaveSpeed ("Wave Speed (波の速さ)", Float) = 2.0
    }
    SubShader
    {
        Tags 
        { 
            "RenderType"="Transparent" 
            "Queue"="Transparent" 
            "RenderPipeline"="UniversalPipeline" 
        }
        
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
                float4 color        : COLOR;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float4 color        : COLOR;
            };

            TEXTURE2D(_ReflectTex);
            SAMPLER(sampler_ReflectTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _ReflectTex_ST;
                float _WaveScale;
                float _WaveStrength;
                float _WaveSpeed;
            CBUFFER_END

            Varyings vert (Attributes input)
            {
                Varyings output;
                // オブジェクト座標からクリップ空間座標へ変換（URPの関数）
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                output.color = input.color;
                return output;
            }

            half4 frag (Varyings input) : SV_Target
            {
                // 1. 時間とサイン波を使って、UV座標を「くねくね」させる
                // URPでは _Time.y をそのまま使えます
                float time = _Time.y * _WaveSpeed;
                float distortX = sin(input.uv.y * _WaveScale + time) * _WaveStrength;
                float distortY = cos(input.uv.x * _WaveScale + time) * _WaveStrength;
                float2 distortion = float2(distortX, distortY);

                // 2. Y軸を反転させて、そこに歪みを足す
                float2 reflectUV = float2(input.uv.x, 1.0 - input.uv.y) + distortion;

                // 3. URPの関数を使ってテクスチャをサンプリング
                half4 col = SAMPLE_TEXTURE2D(_ReflectTex, sampler_ReflectTex, reflectUV);

                // 4. 水面っぽく青みを足して、SpriteRendererの色を乗算
                col.rgb *= half3(0.7, 0.85, 1.0);
                col *= input.color;

                return col;
            }
            ENDHLSL
        }
    }
}