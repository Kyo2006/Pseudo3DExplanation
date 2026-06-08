Shader "Custom/PixelStarAndCRT"
{
    Properties
    {
        _MainTex ("Base (RGB)", 2D) = "white" {}
        
        // --- 渦（Vortex）のプロパティ ---
        _VortexColorTop ("Vortex Color Top (外周)", Color) = (0.2, 0.4, 0.9, 1.0)
        _VortexColorBottom ("Vortex Color Bottom (中心)", Color) = (0.6, 0.2, 0.8, 1.0)
        _VortexDensity ("Vortex Density (粒の量)", Range(0.1, 2.0)) = 1.5
        _VortexDotScale ("Vortex Dot Scale (粒の大きさ)", Range(1.0, 8.0)) = 3.5
        
        // --- スピード調整用（ここを爆速化しました） ---
        _VortexWarpSpeed ("Warp Speed (奥から迫る速さ)", Float) = 1.2    // 奥から手前へ飛び出してくるループ速度
        _VortexOrbitSpeed ("Orbit Speed (回転速度)", Float) = 6.0       // 画面全体がぐるぐる回る速度
        _VortexTwinkleSpeed ("Vortex Twinkle Speed", Float) = 8.0
        
        _VortexCoreSize ("Vortex Core Size", Range(0.01, 0.5)) = 0.05
        
        // --- 背景のプロパティ ---
        _BGColorTop ("Background Color Top", Color) = (0.01, 0.02, 0.05, 1.0)
        _BGColorBottom ("Background Color Bottom", Color) = (0.05, 0.03, 0.08, 1.0)
        _StarDensity ("Star Density", Range(0.01, 1.0)) = 0.35
        
        // --- CRT/Pixelのプロパティ ---
        _PixelSize ("Pixel Size (ドットの粗さ)", Float) = 240.0
        _ScanlineColor ("Scanline Color", Color) = (0.0, 0.0, 0.0, 0.5)
        _ScanlineCount ("Scanline Count", Float) = 480.0 // ブラウン管の走査線の数（昔のテレビは480本が主流でした）
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

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _VortexColorTop, _VortexColorBottom;
            float _VortexDensity, _VortexDotScale, _VortexWarpSpeed, _VortexOrbitSpeed, _VortexTwinkleSpeed, _VortexCoreSize;
            float4 _BGColorTop, _BGColorBottom;
            float _StarDensity, _PixelSize;
            float4 _ScanlineColor;
            float _ScanlineCount;

            // ==========================================
            // 乱数生成関数群
            // ==========================================
            float hash(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123); }
            float2 hash2D(float2 p) { return frac(sin(float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)))) * 43758.5453123); }

            // ==========================================
            // 爆速ワープ渦の生成（3Dトンネル表現）
            // ==========================================
            float3 getStarVortex(float2 uv, float time)
            {
                // UVを画面中心(0,0)にする (-1.0 から 1.0)
                float2 p = (uv - 0.5) * 2.0;
                float r = length(p); // 中心からの距離
                float angle = atan2(p.y, p.x); // 現在のピクセルの角度

                float2 gridScale = uv * _PixelSize; 
                float2 id = floor(gridScale);
                float2 rand = hash2D(id);
                
                float starElement = step(rand.x * 0.5, _VortexDensity);
                
                // 【高速化のキモ①】_VortexWarpSpeed を乗算してループを超高速化
                // frac()を使うことで、0.0(奥)から1.0(手前)に達すると即座に0.0に戻るループを作ります。
                float t = frac(time * _VortexWarpSpeed + rand.y);
                
                // 3Dパース感（遠近法）の調整
                // pow(t, 2.2) にすることで、奥(0.0近辺)ではゆっくり動き、
                // 手前(1.0近辺)に来るほどギュンッ！と急加速するような「迫ってくる感」を演出しています。
                float spiralDist = pow(t, 2.2) * 0.85;
                
                // 【高速化のキモ②】_VortexOrbitSpeed で回転のスピードを爆速化
                // spiralDistが影響しているため、外側にいくほど回転のねじれが強くなります。
                float spiralAngle = angle + (spiralDist * 9.0) - (time * _VortexOrbitSpeed);

                // 星の目標座標を極座標(角度と距離)から直交座標(X,Y)に変換
                float2 targetPos;
                targetPos.x = cos(spiralAngle) * spiralDist;
                targetPos.y = sin(spiralAngle) * spiralDist;

                float distToStar = length(p - targetPos);

                // 星のサイズも遠近法に連動
                // 奥(t=0)にいる時は小さく、手前(t=1)に来るほど大きくなるようにlerpで補間します。
                float starRadius = lerp(0.015, 0.045 * _VortexDotScale, t);
                float vortexMask = step(distToStar, starRadius) * starElement;

                // 中心（特異点）と外側のフェードアウト処理
                // これにより、中心から突然現れたり、画面端で不自然に消えたりするのを防ぎます。
                float fade_core = smoothstep(_VortexCoreSize, _VortexCoreSize + 0.05, r);
                float fade_outer = smoothstep(0.95, 0.75, r);
                vortexMask *= fade_core * fade_outer;

                // 瞬き（ここもチカチカ感を上げるために高速化）
                float twinkle = sin(time * _VortexTwinkleSpeed + rand.y * 6.28) * 0.5 + 0.5;
                twinkle = pow(twinkle, 2.0); 

                // 色も遠近に連動：奥(Bottom)から手前(Top)へグラデーション変化
                float3 vortexColor = lerp(_VortexColorBottom.rgb, _VortexColorTop.rgb, spiralDist) * vortexMask * (0.5 + twinkle * 0.5);
                return vortexColor;
            }

            // ==========================================
            // 固定背景星の生成
            // ==========================================
            float3 getStarField(float2 uv)
            {
                float2 gridScale = uv * 120.0; 
                float2 id = floor(gridScale);
                float2 guv = frac(gridScale) - 0.5;

                float2 rand = hash2D(id);
                float starElement = step(rand.x, _StarDensity);
                
                float dist = length(guv - (rand - 0.5) * 0.7);
                float starBrite = smoothstep(0.06, 0.0, dist) * starElement;

                return float3(0.9, 0.95, 1.0) * starBrite;
            }

            // ==========================================
            // CRT走査線（スキャンライン）の生成
            // ==========================================
            float3 getScanlines(float2 uv, float3 color)
            {
                // ピクセル化される「前」の生UVを使うことで、ドット絵の上に細い横線が乗るリアルなCRT感を表現します。
                // sin波を使って、画面全体に_ScanlineCount分の黒いシマシマを作ります。
                float scanline = sin(uv.y * _ScanlineCount * 3.141592) * 0.5 + 0.5;
                color = lerp(color, color * _ScanlineColor.rgb, scanline * _ScanlineColor.a);
                return color;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            // メイン描画処理
            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.uv;
                float time = _Time.y;

                // --- 1. ドット絵化（ピクセルモザイク）処理 ---
                // 解像度を強制的に下げることでレトロゲーム感を出す
                float2 pixelatedUV = floor(uv * _PixelSize) / _PixelSize;

                // --- 2. 背景と星空の合成（ピクセル化されたUVを使用） ---
                float3 skyColor = lerp(_BGColorBottom.rgb, _BGColorTop.rgb, pixelatedUV.y);
                skyColor += getStarField(pixelatedUV);

                // 超高速の渦つぶつぶを描画
                float3 vortexStars = getStarVortex(pixelatedUV, time);
                float3 finalColor = skyColor + vortexStars;

                // --- 3. CRT走査線の合成（ピクセル化されていない生UVを使用） ---
                // モザイクがかかった絵の上に、細かく綺麗な走査線を乗せることで「ブラウン管で表示されたドット絵」になります。
                finalColor = getScanlines(uv, finalColor);

                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}