Shader "Custom/WaterPixelDistortion"
{
    Properties
    {
        [Header(Pixel Art Resolution)]
        _PixelWidth ("Pixel Width (横のドット数)", Float) = 256.0
        _PixelHeight ("Pixel Height (縦のドット数)", Float) = 144.0

        [Header(Sky and Water Colors)]
        _SkyColorTop ("Horizon Fog Color (奥の霞み空)", Color) = (0.4, 0.75, 1.0, 1.0)
        _WaterColorShallow ("Water Color Shallow (奥の明るい青)", Color) = (0.1, 0.65, 1.0, 1.0) 
        _WaterColorDeep ("Water Color Deep (手前の深い青)", Color) = (0.0, 0.35, 0.8, 1.0)      
        
        [Header(Horizon Wave Settings)]
        _HorizonY ("Horizon Y (地平線の高さ)", Range(0.0, 1.0)) = 0.63 
        _WaveHeight ("Wave Height (波打ちの高さ)", Range(0.0, 0.1)) = 0.02
        _WaveFreq ("Wave Frequency (波の細かさ)", Float) = 8.0
        _WaveSpeed ("Wave Speed (波の速さ)", Float) = 2.0
        
        [Header(Water Distortion and Flow)]
        _Speed ("Forward Speed (奥から手前への速度)", Float) = 0.6
        _Distortion ("Surface Distortion (大波のうねり)", Range(0.0, 0.2)) = 0.05
        _RippleDistortion ("Ripple Distortion (小波による光のブレ)", Range(0.0, 0.1)) = 0.02
        
        [Header(Caustics Detail)]
        _CausticColor ("Caustic Color (光の網目)", Color) = (1.0, 1.0, 1.0, 1.0)            
        _ScatterColor ("Subsurface Scatter (シアンのにじみ)", Color) = (0.0, 0.9, 1.0, 1.0) 
        _CausticScale ("Caustic Scale (網目の細かさ)", Float) = 2.0 
        _LineSharpness ("Line Sharpness (線の極細度)", Range(1.0, 15.0)) = 6.0
        _ChromAb ("Chromatic Aberration (プリズム色収差)", Range(0.0, 0.1)) = 0.02

        [Header(Transparency)]
        _Alpha ("Water Alpha (水面の透明度)", Range(0.0, 1.0)) = 0.7
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off 

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

            float _PixelWidth;
            float _PixelHeight;
            float4 _SkyColorTop;
            float4 _WaterColorDeep;
            float4 _WaterColorShallow;
            float4 _CausticColor;
            float4 _ScatterColor;
            float _HorizonY;
            float _Speed;
            float _Distortion;
            float _RippleDistortion;
            float _WaveHeight;
            float _WaveFreq;
            float _WaveSpeed;
            float _CausticScale;
            float _LineSharpness;
            float _ChromAb;
            float _Alpha;

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float GetCausticPattern(float2 p, float time)
            {
                float2 s1 = p + float2(sin(p.y + time), cos(p.x + time));
                float2 s2 = p * 1.5 + float2(cos(s1.y - time * 0.8), sin(s1.x + time * 0.8));
                float2 s3 = p * 2.2 + float2(sin(s2.x + time * 1.2), cos(s2.y - time * 1.0));
                
                float c1 = abs(sin(s1.x + s1.y));
                float c2 = abs(cos(s2.x - s2.y));
                float c3 = abs(sin(s3.x + s3.y));
                
                return c1 * c2 * c3;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.uv;
                uv.x = floor(uv.x * _PixelWidth) / _PixelWidth;
                uv.y = floor(uv.y * _PixelHeight) / _PixelHeight;

                float4 finalColor = float4(0, 0, 0, 1);
                float time = _Time.y;

                float waveOffset = sin(uv.x * _WaveFreq + time * _WaveSpeed) * _WaveHeight;
                waveOffset += cos(uv.x * (_WaveFreq * 1.6) - time * (_WaveSpeed * 0.7)) * (_WaveHeight * 0.3);
                float dynamicHorizon = _HorizonY + waveOffset;

                // --- A. 背景領域（空） ---
                if (uv.y >= dynamicHorizon)
                {
                    finalColor = float4(0.0, 0.0, 0.0, 0.0);
                }
                // --- B. 水面領域 ---
                else
                {
                    float depth = dynamicHorizon - uv.y;

                    float distortTime = time * _Speed;
                    float bigWaveX = sin(uv.y * 12.0 + distortTime * 0.8) * _Distortion;
                    float bigWaveY = cos(uv.x * 10.0 + distortTime * 0.8) * _Distortion;
                    
                    float rippleX = sin(uv.x * 40.0 - time * 3.0) * _RippleDistortion;
                    float rippleY = cos(uv.y * 40.0 + time * 2.5) * _RippleDistortion;

                    uv.x += (bigWaveX + rippleX) * depth;
                    uv.y += (bigWaveY + rippleY) * depth;

                    float perspectiveY = 1.0 / (depth + 0.005);
                    float perspectiveX = (uv.x - 0.5) * perspectiveY;

                    float2 waterUV;
                    waterUV.x = perspectiveX * 0.5;
                    waterUV.y = (perspectiveY * 0.2) + (time * _Speed);

                    float2 p = waterUV * _CausticScale;
                    
                    float combR, combG, combB;
                    float abShift = _ChromAb * 0.08 * perspectiveY; 
                    
                    combR = GetCausticPattern(p + float2(-abShift, 0.0), time);
                    combG = GetCausticPattern(p, time);
                    combB = GetCausticPattern(p + float2(abShift, 0.0), time);
                    
                    float3 causticMaskRGB;
                    causticMaskRGB.r = pow(saturate(1.0 - combR), _LineSharpness * 3.0);
                    causticMaskRGB.g = pow(saturate(1.0 - combG), _LineSharpness * 3.0);
                    causticMaskRGB.b = pow(saturate(1.0 - combB), _LineSharpness * 3.0);

                    float depthMask = smoothstep(0.0, 0.4, depth);
                    float3 poolBaseColor = lerp(_WaterColorShallow.rgb, _WaterColorDeep.rgb, depthMask);

                    float shadowMask = smoothstep(0.02, 0.2, combG);
                    poolBaseColor *= lerp(0.7, 1.0, shadowMask);

                    float scatterMask = pow(saturate(1.0 - combG), _LineSharpness * 1.2); 
                    float3 scatterLight = _ScatterColor.rgb * scatterMask * 0.4;

                    float fogFactor = smoothstep(0.0, 0.08, depth);
                    float3 lightNet = (_CausticColor.rgb * causticMaskRGB + scatterLight) * 2.5 * fogFactor;
                    
                    finalColor.rgb = poolBaseColor + lightNet;
                    finalColor.a = _Alpha;

                    float fog = smoothstep(0.0, 0.015, depth);
                    finalColor.rgb = lerp(_WaterColorShallow.rgb, finalColor.rgb, fog);
                }

                return finalColor;
            }
            ENDHLSL
        }
    }
}