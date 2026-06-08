Shader "Custom/NightSkyCloud2D"
{
    Properties
    {
        // --- 夜空のプロパティ ---
        _SkyColorTop ("Sky Color Top (宇宙の深み)", Color) = (0.02, 0.04, 0.1, 1.0)
        _SkyColorBottom ("Sky Color Bottom (地平線の夜明)", Color) = (0.1, 0.07, 0.18, 1.0)
        _StarDensity ("Star Density (星の数・出現率)", Range(0.1, 1.0)) = 0.48
        _StarTwinkleSpeed ("Star Twinkle Speed (瞬きの速さ)", Float) = 4.5

        // --- 月のプロパティ ---
        _MoonColor ("Moon Color (月のベース色)", Color) = (1.0, 0.92, 0.82, 1.0)
        _MoonPatternColor ("Moon Pattern Color (模様の暗い海)", Color) = (0.35, 0.38, 0.48, 1.0)
        _MoonPos ("Moon Position (X, Y) [0～1]", Vector) = (0.5, 0.65, 0.0, 0.0) // 画面内の月の位置
        _MoonSize ("Moon Size (月の大きさ)", Range(0.01, 0.9)) = 10.0
        _MoonGlow ("Moon Glow (月の光輪)", Range(0.01, 0.5)) = 0.12
        _AspectRatio ("Aspect Ratio (横幅 / 縦幅)", Float) = 1.7777 // 月が楕円にならないための補正係数

        // --- 雲海のプロパティ ---
        _CloudBaseColor ("Cloud Base Color (光)", Color) = (0.98, 0.88, 0.75, 1.0)
        _CloudShadowColor ("Cloud Shadow Color (影)", Color) = (0.35, 0.32, 0.45, 1.0)
        
        _HorizonY ("Horizon Y (地平線の高さ)", Range(0.0, 1.0)) = 0.52 // ここを境に上下を分割
        _Speed ("Forward Speed (超高速)", Float) = 40.0
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
            // 1. ノイズ関連関数 (自然な模様や乱数を作る)
            // ==========================================
            
            // 1Dハッシュ（入力から単一のランダムな値を返す）
            float hash(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123); }

            // 2Dハッシュ（入力からXとY、2つのランダムな値を返す。星の配置などに使用）
            float2 hash2D(float2 p)
            {
                return frac(sin(float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)))) * 43758.5453123);
            }

            // バリューノイズ（格子点間の乱数を滑らかにつなぐ）
            float noise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
                return lerp(lerp(hash(i + float2(0.0,0.0)), hash(i + float2(1.0,0.0)), u.x),
                            lerp(hash(i + float2(0.0,1.0)), hash(i + float2(1.0,1.0)), u.x), u.y);
            }

            // フラクタルノイズ(FBM)（複数回のノイズを重ねて、雲や月のクレーターなどの複雑な模様を作る）
            float fbm(float2 p)
            {
                float v = 0.0;
                float amplitude = 0.5;
                float2x2 m = float2x2(1.6,  1.2, -1.2,  1.6); // 回転行列（ノイズの方向を散らす）
                for (int i = 0; i < 5; i++)
                {
                    v += amplitude * noise(p);
                    p = mul(m, p) * 1.9; // 座標を回転させながら縮小
                    amplitude *= 0.42;   // 影響力を下げる
                }
                return v;
            }

            // ==========================================
            // 2. 空間・オブジェクト計算関数
            // ==========================================

            // 擬似3Dパース変換
            // 画面のY座標(縦)を「奥行き(Z)」とみなし、奥へ行くほどX座標(横)を圧縮することで
            // 平面の2D画像を無理やり「奥へと続く地面」に見せる強力な錯視テクニック。
            float2 getPerspectivePos(float2 uv, float depth, float time)
            {
                // 地平線(depth=0)に近づくほど、perspectiveYの値が無限大に近づく（奥へのパース）
                float perspectiveY = 1.0 / (depth + 0.015); 
                // 奥に行くほど、横幅が中心に向かってギュッと圧縮される
                float perspectiveX = (uv.x - 0.5) * perspectiveY;

                float2 p;
                p.x = perspectiveX * _CloudScale;
                p.y = perspectiveY * _CloudScale + (time * _Speed); // 時間を足して奥へ奥へと進む
                return p;
            }

            // 【星空生成関数】
            // 画面を細かいグリッド(網目)に分割し、各マスにランダムで星を1つ配置する
            float3 getSuperStarField(float2 uv, float time)
            {
                float2 gridScale = uv * 180.0; // 画面を180マスのグリッドに分割
                float2 id = floor(gridScale);  // マスのID（番地）
                float2 guv = frac(gridScale) - 0.5; // マス内のローカル座標 (-0.5 から 0.5)

                float2 rand = hash2D(id); // マスの番地から固有の乱数を取得
                
                // 乱数が_StarDensityの条件を満たした場合のみ星を出現させる(0 or 1)
                float starElement = step(0.1 - _StarDensity * 0.09, rand.x);
                
                // 星の中心からの距離を測る（乱数で少し位置をずらす）
                float dist = length(guv - (rand - 0.5) * 0.7);
                float starBrite = smoothstep(0.05, 0.0, dist) * starElement;

                // 時間と乱数を使って星をチカチカさせる(0.0から1.0の間で行ったり来たり)
                float twinkle = sin(time * _StarTwinkleSpeed + rand.y * 6.28) * 0.5 + 0.5;
                twinkle = pow(twinkle, 4.0); // 光の明暗を鋭くする

                return float3(0.9, 0.95, 1.0) * starBrite * (0.25 + twinkle * 0.75);
            }

            // 月生成
            float4 getRealisticMoon(float2 uv, float skyT)
            {
                float2 distUV = uv - _MoonPos.xy; // 月の中心からのベクトル
                distUV.x *= _AspectRatio; // 真ん丸に補正

                float dist = length(distUV);

                // 月の外側の処理（光の輪郭・グロウ）
                float moonMask = smoothstep(_MoonSize + 0.003, _MoonSize, dist);
                if (moonMask <= 0.0)
                {
                    float moonGlow = smoothstep(_MoonSize + _MoonGlow, _MoonSize, dist);
                    moonGlow = pow(moonGlow, 2.5) * 0.5; // ぼんやり光る
                    return float4(_MoonColor.rgb * moonGlow, 0.0); // a=0にして背景と加算合成しやすくする
                }

                // --- 月の内側(表面)の処理 ---
                float2 mUV = distUV / _MoonSize; // 月を -1.0 から 1.0 の座標系に直す

                // 1. ノイズを重ねて大きな「暗い海」と小さな「クレーターのザラザラ」を作る
                float nBase = noise(mUV * 2.2 + float2(0.5, -0.3)) * 0.5 
                            + noise(mUV * 4.5 + float2(-1.2, 0.8)) * 0.3;
                float nDetail = noise(mUV * 12.0) * 0.15 
                              + noise(mUV * 28.0) * 0.05;
                float totalNoise = nBase + nDetail;

                // 2. 巨大なクレーターから放射状に伸びる線（レイズ）の生成
                float2 craterCenter = float2(-0.35, -0.45); // クレーターの位置
                float2 toCrater = mUV - craterCenter;
                float distToCrater = length(toCrater);
                float angle = atan2(toCrater.y, toCrater.x); // 角度を取得
                
                // 角度をsin関数に入れて放射状のギザギザを作る
                float rays = sin(angle * 16.0 + noise(mUV * 5.0) * 4.0) * 0.5 + 0.5;
                rays *= smoothstep(0.8, 0.1, distToCrater); // クレーター周辺だけ強く
                rays *= noise(mUV * 20.0) * 0.6; // まばらにする

                // 3. ベース色と模様(海)の色をブレンドし、光条(レイズ)を加算
                float patternLerp = smoothstep(0.35, 0.58, totalNoise);
                float3 moonSurface = lerp(_MoonColor.rgb, _MoonPatternColor.rgb, patternLerp);
                moonSurface += _MoonColor.rgb * rays * 0.35;

                // 4. 【疑似3Dライティング】
                // 2Dの円を「球体」に見せるため、端を暗くし(shade3D)、
                // 指定した方向(光の向き)との内積(dot)をとって影を作る
                float shade3D = smoothstep(1.0, -0.2, dist / _MoonSize);
                float lightDir = smoothstep(-1.0, 0.8, dot(mUV, normalize(float2(-0.3, 0.2))));
                moonSurface *= lerp(0.5, 1.0, shade3D * lightDir);

                return float4(moonSurface, 1.0);
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            // ==========================================
            // 3. メインの描画処理 (フラグメントシェーダー)
            // ==========================================
            float4 frag(Varyings input) : SV_Target
            {
                // SFC風ドット絵解像度に強制丸め
                float2 uv = floor(input.uv * _PixelSize) / _PixelSize;
                float4 finalColor = float4(0, 0, 0, 1);
                float time = _Time.y;

                // ------------------------------------------
                // ① 上半分の描画：【星空 ＆ リアル巨大月】
                // ------------------------------------------
                if (uv.y >= _HorizonY)
                {
                    // 空のグラデーション位置を計算 (0.0=地平線、1.0=画面上端)
                    float skyT = (uv.y - _HorizonY) / (1.0 - _HorizonY);
                    
                    // ベースの空の色をグラデーション補間
                    float3 skyColor = lerp(_SkyColorBottom.rgb, _SkyColorTop.rgb, pow(skyT, 0.7));

                    // 星を描画して足し合わせる
                    float3 stars = getSuperStarField(uv, time);
                    skyColor += stars;

                    // 月を描画
                    float4 moonOutput = getRealisticMoon(uv, skyT);
                    if (moonOutput.a > 0.0) 
                    {
                        // 月本体(アルファ1)の場合は空を月で上書き
                        skyColor = moonOutput.rgb;
                    }
                    else
                    {
                        // 月の外側（光輪、アルファ0）の場合は、空の色と加算(明るい方をとる)
                        skyColor = max(skyColor, moonOutput.rgb);
                    }

                    // 地平線付近は少し白っぽく霞ませる(フォグ)
                    float fogFactor = smoothstep(0.0, 0.12, skyT);
                    skyColor = lerp(_SkyColorBottom.rgb, skyColor, fogFactor);

                    finalColor = float4(skyColor, 1.0);
                }
                // ------------------------------------------
                // ② 下半分の描画：【雲海】
                // ------------------------------------------
                else
                {
                    // 地平線からの深さ（遠近感のベースになる）
                    float depth = _HorizonY - uv.y;

                    // 雲の模様座標を「擬似3Dパース座標」に変換
                    float2 p = getPerspectivePos(uv, depth, time);
                    float density = fbm(p); // 雲の密度

                    // 光の方向へ少しずらした位置でもう一度計算し、段差（立体影）を割り出す
                    float2 lightDir = float2(-0.04, 0.03); 
                    float2 pLight = getPerspectivePos(uv + lightDir * depth, depth, time);
                    float densityLight = fbm(pLight);

                    // 影の強さと雲のくっきり度合いを計算
                    float shadow = saturate(densityLight - density) * _ShadowIntensity;
                    density = smoothstep(0.25, 0.65, density);

                    // 影色と光色をブレンド
                    float4 cloudColor = lerp(_CloudBaseColor, _CloudShadowColor, shadow);
                    cloudColor = lerp(cloudColor * 0.4, cloudColor, density); 

                    // 地平線（奥）に行くほど、空の下部の色に溶け込ませる（フォグ・空気遠近法）
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