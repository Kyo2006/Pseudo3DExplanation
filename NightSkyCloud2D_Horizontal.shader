Shader "Custom/NightSkyCloud2D_HugeMoon"
{
    Properties
    {
        // --- 夜空のプロパティ ---
        _SkyColorTop ("Sky Color Top (宇宙の深み)", Color) = (0.02, 0.04, 0.1, 1.0)
        _SkyColorBottom ("Sky Color Bottom (地平線の夜明)", Color) = (0.1, 0.07, 0.18, 1.0)
        _StarDensity ("Star Density (星の数・出現率)", Range(0.1, 1.0)) = 0.48
        _StarTwinkleSpeed ("Star Twinkle Speed (瞬きの速さ)", Float) = 4.5

        // --- 月のプロパティ（巨大化に向けた調整） ---
        _MoonColor ("Moon Color (月のベース色)", Color) = (1.0, 0.92, 0.82, 1.0)
        _MoonPatternColor ("Moon Pattern Color (模様の暗い海)", Color) = (0.35, 0.38, 0.48, 1.0)
        // 巨大化に合わせて、月が上に見切れすぎないよう中心Y座標を少し下(0.45)に調整
        _MoonPos ("Moon Position (X, Y) [0～1]", Vector) = (0.5, 0.45, 0.0, 0.0) 
        // 画面いっぱいに広がる圧倒的なサイズ感（0.95）
        _MoonSize ("Moon Size (月の大きさ)", Range(0.05, 2.0)) = 0.95 
        _MoonGlow ("Moon Glow (月の光輪)", Range(0.01, 1.0)) = 0.3
        _AspectRatio ("Aspect Ratio (横幅 / 縦幅)", Float) = 1.7777

        // --- 雲海のプロパティ ---
        _CloudBaseColor ("Cloud Base Color (光)", Color) = (0.98, 0.88, 0.75, 1.0)
        _CloudShadowColor ("Cloud Shadow Color (影)", Color) = (0.35, 0.32, 0.45, 1.0)
        
        _HorizonY ("Horizon Y (地平線の高さ)", Range(0.0, 1.0)) = 0.52
        // 前進ではなく「横スクロール」の速度として扱う
        _Speed ("Horizontal Speed (右から左への速度)", Float) = 15.0
        _CloudScale ("Cloud Scale", Float) = 0.5
        _ShadowIntensity ("Shadow Intensity", Range(0.0, 2.0)) = 1.3
        
        _PixelSize ("Pixel Size (ドットの粗さ)", Float) = 240.0
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

            float4 _SkyColorTop, _SkyColorBottom;
            float _StarDensity, _StarTwinkleSpeed;
            float4 _MoonColor, _MoonPatternColor, _MoonPos;
            float _MoonSize, _MoonGlow, _AspectRatio;
            float4 _CloudBaseColor, _CloudShadowColor;
            float _HorizonY, _Speed, _CloudScale, _ShadowIntensity, _PixelSize;

            // ==========================================
            // ノイズ生成関数群（前回と同じ）
            // ==========================================
            float hash(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123); }
            
            float2 hash2D(float2 p)
            {
                return frac(sin(float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)))) * 43758.5453123);
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

            // ==========================================
            // 【変更点】横スクロール用のパースペクティブ変換
            // ==========================================
            float2 getPerspectivePos(float2 uv, float depth, float time)
            {
                // 地平線に近づくほど数値が大きくなる係数（奥への圧縮率）
                float perspectiveFactor = 1.0 / (depth + 0.015);
                float2 p;
                
                // 横軸（X）に時間を足すことで「右から左へ流れる」横スクロールを実現。
                // 遠く（perspectiveFactorが大きい）ほど速く流れるように見えるため、
                // 立体的な奥行き感を保ったままカメラが横移動しているように見えます。
                p.x = (uv.x * perspectiveFactor * _CloudScale) + (time * _Speed);
                p.y = uv.y * perspectiveFactor * _CloudScale;
                return p;
            }

            // 星空描画（前回と同じ）
            float3 getSuperStarField(float2 uv, float time)
            {
                float2 gridScale = uv * 180.0; 
                float2 id = floor(gridScale);
                float2 guv = frac(gridScale) - 0.5;
                float2 rand = hash2D(id);
                float starElement = step(0.1 - _StarDensity * 0.09, rand.x);
                float dist = length(guv - (rand - 0.5) * 0.7);
                float starBrite = smoothstep(0.05, 0.0, dist) * starElement;
                float twinkle = sin(time * _StarTwinkleSpeed + rand.y * 6.28) * 0.5 + 0.5;
                twinkle = pow(twinkle, 4.0);
                return float3(0.9, 0.95, 1.0) * starBrite * (0.25 + twinkle * 0.75);
            }

            // ==========================================
            // 【変更点】巨大月（Huge Moon）への最適化
            // ==========================================
            float4 getRealisticMoon(float2 uv, float skyT)
            {
                float2 distUV = uv - _MoonPos.xy;
                distUV.x *= _AspectRatio;

                float dist = length(distUV);

                // 【修正点】月の光輪と本体の境界マスクを、サイズ変更(_MoonSize)に完全連動させる
                float moonMask = smoothstep(_MoonSize + 0.005, _MoonSize, dist);
                
                if (moonMask <= 0.0)
                {
                    float moonGlow = smoothstep(_MoonSize + _MoonGlow, _MoonSize, dist);
                    moonGlow = pow(moonGlow, 2.0) * 0.6; // 光輪の広がり方と強さを調整
                    return float4(_MoonColor.rgb * moonGlow, 0.0);
                }

                float2 mUV = distUV / _MoonSize;

                // リアル模様アルゴリズム
                // 月を巨大化すると模様も一緒に拡大されて「ぼやけた低解像度の月」になってしまいます。
                // それを防ぐため、noise関数の入力にかける係数（2.5, 5.0, 15.0, 32.0）を少し大きくして、
                // 「月は大きいまま、クレーターや海の模様の密度（ディテール）を細かく保つ」調整が入っています。
                float nBase = noise(mUV * 2.5 + float2(0.5, -0.3)) * 0.5 
                            + noise(mUV * 5.0 + float2(-1.2, 0.8)) * 0.3;
                
                float nDetail = noise(mUV * 15.0) * 0.15 
                              + noise(mUV * 32.0) * 0.05;
                
                float totalNoise = nBase + nDetail;

                // クレーターからの放射状の光条（レイズ）
                float2 craterCenter = float2(-0.35, -0.45);
                float2 toCrater = mUV - craterCenter;
                float distToCrater = length(toCrater);
                float angle = atan2(toCrater.y, toCrater.x);
                
                float rays = sin(angle * 16.0 + noise(mUV * 5.0) * 4.0) * 0.5 + 0.5;
                rays *= smoothstep(0.8, 0.1, distToCrater);
                rays *= noise(mUV * 20.0) * 0.6;

                // 模様のブレンド
                float patternLerp = smoothstep(0.35, 0.58, totalNoise);
                float3 moonSurface = lerp(_MoonColor.rgb, _MoonPatternColor.rgb, patternLerp);
                moonSurface += _MoonColor.rgb * rays * 0.35;

                // 3D影のシミュレーション
                // 月が巨大化すると端のカーブが緩やかになるため、影のつき方（0.4～1.0のlerp）を
                // 少し暗く調整して、のっぺりしないように立体感を強調しています。
                float shade3D = smoothstep(1.0, -0.2, dist / _MoonSize);
                float lightDir = smoothstep(-1.0, 0.8, dot(mUV, normalize(float2(-0.3, 0.2))));
                moonSurface *= lerp(0.4, 1.0, shade3D * lightDir);

                return float4(moonSurface, 1.0);
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
                float2 uv = floor(input.uv * _PixelSize) / _PixelSize;
                float4 finalColor = float4(0, 0, 0, 1);
                float time = _Time.y;

                if (uv.y >= _HorizonY)
                {
                    float skyT = (uv.y - _HorizonY) / (1.0 - _HorizonY);
                    float3 skyColor = lerp(_SkyColorBottom.rgb, _SkyColorTop.rgb, pow(skyT, 0.7));

                    float3 stars = getSuperStarField(uv, time);
                    skyColor += stars;

                    float4 moonOutput = getRealisticMoon(uv, skyT);
                    
                    if (moonOutput.a > 0.0)
                    {
                        skyColor = moonOutput.rgb;
                    }
                    else
                    {
                        skyColor = max(skyColor, moonOutput.rgb);
                    }

                    float fogFactor = smoothstep(0.0, 0.12, skyT);
                    skyColor = lerp(_SkyColorBottom.rgb, skyColor, fogFactor);

                    finalColor = float4(skyColor, 1.0);
                }
                // 横スクロール雲海の描画
                else
                {
                    float depth = _HorizonY - uv.y;

                    // getPerspectivePosでX軸に時間が足されるため、横スクロールになる
                    float2 p = getPerspectivePos(uv, depth, time);
                    float density = fbm(p);

                    // 光の当たる方向（影の落ち方）を微調整
                    // 前進から横スクロールに変わったため、違和感が出ないよう影の角度を変えています。
                    float2 lightDir = float2(0.03, 0.02); 
                    float2 pLight = getPerspectivePos(uv + lightDir * depth, depth, time);
                    float densityLight = fbm(pLight);

                    float shadow = saturate(densityLight - density) * _ShadowIntensity;
                    density = smoothstep(0.25, 0.65, density);

                    float4 cloudColor = lerp(_CloudBaseColor, _CloudShadowColor, shadow);
                    cloudColor = lerp(cloudColor * 0.4, cloudColor, density); 

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