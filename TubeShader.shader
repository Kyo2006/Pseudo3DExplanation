Shader "Custom/TubeShader"
{
    Properties
    {
        // --- インスペクターから調整できるパラメータ群 ---
        _CloudBaseColor ("Cloud Base Color (雲の光面)", Color) = (0.92, 0.82, 0.75, 1.0)
        _CloudShadowColor ("Cloud Shadow Color (雲の影面)", Color) = (0.32, 0.25, 0.42, 1.0)
        _HorizonColor ("Center Fog Color (最奥の中心光)", Color) = (0.95, 0.72, 0.55, 1.0)
        
        _Speed ("Forward Speed (前進速度)", Float) = 20.0
        _CloudScale ("Cloud Scale (雲の大きさの倍率)", Float) = 0.5
        _ShadowIntensity ("Shadow Intensity (影の濃さ)", Range(0.0, 2.0)) = 1.4
        _PixelSize ("Pixel Size (SFC縦解像度・ドットの粗さ)", Float) = 224.0
        
        _TunnelPower ("Tunnel Power (中心への吸い込み度・パースの強さ)", Range(1.0, 5.0)) = 2.5
        
        // 画面の比率（16:9 なら 16*9 ＝ 約1.777）を設定して楕円化を防ぐ
        _AspectRatio ("Aspect Ratio (横幅 / 縦幅)", Float) = 1.7777
    }

    SubShader
    {
        // 透過処理（Transparent）を行うためのUnity設定
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        Blend SrcAlpha OneMinusSrcAlpha
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // 頂点シェーダーへの入力構造体
            struct Attributes
            {
                float4 positionOS   : POSITION; // オブジェクトスペースでの頂点座標
                float2 uv           : TEXCOORD0;// メッシュのUV座標
            };

            // フラグメントシェーダーへの橋渡し構造体
            struct Varyings
            {
                float4 positionCS   : SV_POSITION; // クリップスペースでの頂点座標
                float2 uv           : TEXCOORD0;   // フラグメントに渡すUV座標
            };

            // Propertiesで定義した変数をCBUFFER（定数バッファ）として宣言
            float4 _CloudBaseColor;
            float4 _CloudShadowColor;
            float4 _HorizonColor;
            float _Speed;
            float _CloudScale;
            float _ShadowIntensity;
            float _PixelSize;
            float _TunnelPower;
            float _AspectRatio;

            // ==========================================
            // 1. ノイズ生成用ハッシュ関数 (3次元入力)
            // ==========================================
            // 入力された3D座標（x, y, z）から、0.0から1.0の「規則性のない一意の極小値」を返す（擬似乱数）
            float hash3D(float3 p)
            {
                return frac(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453123);
            }

            // ==========================================
            // 2. 3次元バリューノイズ関数
            // ==========================================
            // 空間上の格子点（ハッシュ値）の間を、なめらかなカーブ（3次から5次関数）で補間する
            float noise3D(float3 p)
            {
                float3 i = floor(p); // 整数部分（格子のインデックス）
                float3 f = frac(p);  // 小数部分（格子内のどこにいるか）
                
                // 補間用のなめらかなクエンティクカーブ（フェード関数）
                float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

                // 立方体の角の8点（前後・左右・上下）の乱数を取得
                float n000 = hash3D(i + float3(0,0,0));
                float n100 = hash3D(i + float3(1,0,0));
                float n010 = hash3D(i + float3(0,1,0));
                float n110 = hash3D(i + float3(1,1,0));
                float n001 = hash3D(i + float3(0,0,1));
                float n101 = hash3D(i + float3(1,0,1));
                float n011 = hash3D(i + float3(0,1,1));
                float n111 = hash3D(i + float3(1,1,1));

                // 8点を線形補間（lerp）して、空間内のなめらかな数値を計算
                return lerp(lerp(lerp(n000, n100, u.x), lerp(n010, n110, u.x), u.y),
                            lerp(lerp(n001, n101, u.x), lerp(n011, n111, u.x), u.y), u.z);
            }

            // ==========================================
            // 3. フラクタルブラウン運動 (FBM) ノイズ
            // ==========================================
            // 解像度と濃淡の異なるノイズを4回（4オクターブ）重ね合わせることで、
            // 単調な模様から「自然な雲のモコモコ感」や「地形のような複雑さ」を作り出す
            float fbm3D(float3 p)
            {
                float v = 0.0;
                float amplitude = 0.5; // 最初（1周目）のノイズの影響力
                for (int i = 0; i < 4; i++)
                {
                    v += amplitude * noise3D(p);
                    p = p * 2.1;       // ループごとに細かさ（周波数）を倍にする
                    amplitude *= 0.45; // ループごとに影響力を半分以下に減らす（ディテール用）
                }
                return v;
            }

            // ==========================================
            // 4. 【核心部】円筒プロジェクション（トンネル座標変換）
            // ==========================================
            // 平面の2D座標(UV)を、奥へ進む無限のトンネル（3Dの円筒）の座標へとねじ曲げる関数
            float3 getSeamlessTunnelPos(float2 uv, float time, out float outRadius)
            {
                // 中心を (0, 0) にずらす（デフォルトは左下が0,0、右上が1,1）
                float2 centeredUV = uv - float2(0.5, 0.5);
                
                // 画面が横長（16:9など）だと円が楕円に歪むため、横軸に比率を掛けて「真ん丸」に補正
                centeredUV.x *= _AspectRatio; 
                
                // 中心からの距離（これがトンネルの奥行き表現のベースになる）
                float radius = length(centeredUV);
                outRadius = radius; // 外の処理でも使うため出力用変数に退避

                // 中心を基準とした「角度（ラジアン：-πからπ）」を計算
                float angle = atan2(centeredUV.x, centeredUV.y);

                // 【完璧なシームレス化のトリック】
                // 角度をそのまま使うと「12時の位置」で数値がジャンプして繋ぎ目（線）が見えてしまう。
                // そこで、角度からsinとcosを逆算して「3D空間上の円周の座標」へと変換する。
                // これにより、1周したときに完全に数値が繋がり、切れ目が消滅する。
                float3 p;
                p.x = sin(angle) * _CloudScale * 2.0; // 円筒の横の壁
                p.y = cos(angle) * _CloudScale * 2.0; // 円筒の縦の壁

                // 【トンネルの吸い込み計算】
                // 中心（radiusが0に近い）に行くほど、反比例（1.0 / depthFactor）でZ軸（奥）の数値が爆発的に大きくなる。
                // `pow` を使うことで、手前はゆっくり動き、中心付近はものすごい速さで奥に吸い込まれるパースペクティブ（遠近感）が生まれる。
                float depthFactor = pow(saturate(radius * 1.2), _TunnelPower);
                p.z = (1.0 / (depthFactor + 0.001)) * _CloudScale + (time * _Speed); // 時間を足して前進させる
                
                return p;
            }

            // 頂点シェーダー：頂点の位置を画面空間に変換（標準処理）
            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            // ==========================================
            // 5. ピクセル（フラグメント）シェーダー
            // ==========================================
            float4 frag(Varyings input) : SV_Target
            {
                // 【SFC風モザイク化】
                // UV座標を指定のピクセル数（例：224マス）で段階的に丸める（floor）ことで、
                // どんな環境でもレトロゲームの解像度（ドット絵風）に強制変換する
                float2 uv = floor(input.uv * _PixelSize) / _PixelSize;

                float time = _Time.y;
                float radius = 0.0;

                // ① ドット化したUVから、切れ目のない3次元トンネル空間の座標を取得
                float3 p = getSeamlessTunnelPos(uv, time, radius);
                
                // ② 3D FBMノイズを使って、トンネルの壁に「雲の密度（模様）」を描く
                float density = fbm3D(p);

                // 【擬似的な立体影の計算】
                // 少しだけずらした座標（UV + lightDir）で、もう一度トンネル座標とノイズ（densityLight）を計算する。
                // 本物の密度（density）と、ずらした密度（densityLight）の差を見ることで、
                // 光が遮られているような「モコモコした立体的な影」の範囲を割り出す。
                float2 lightDir = float2(0.01, 0.01);
                float dummyRadius = 0.0;
                float3 pLight = getSeamlessTunnelPos(uv + lightDir * radius, time, dummyRadius);
                float densityLight = fbm3D(pLight);

                // 影の強さを計算し、Propertiesで指定した係数を掛ける
                float shadow = saturate(densityLight - density) * _ShadowIntensity;
                
                // 雲のグラデーションの境界をくっきりさせて、アニメ風（ドット絵風）に整える
                density = smoothstep(0.22, 0.62, density);

                // 影の計算結果を元に、雲の「光が当たっている色」と「影の色」をブレンド（lerp）
                float4 cloudColor = lerp(_CloudBaseColor, _CloudShadowColor, shadow);
                
                // 雲の密度が薄い部分は、さらに暗い影色にして奥に沈ませる
                cloudColor = lerp(cloudColor * 0.45, cloudColor, density);

                // 【最奥の中心光（フォグ）の合成】
                // 中心（radiusが0）に近づくほど、雲の模様を消して「最奥の中心光（_HorizonColor）」へと滑らかに遷移させる
                float fogFactor = smoothstep(0.0, 0.25, radius);
                float4 terrainColor = lerp(_CloudShadowColor * 0.8, cloudColor, density);
                
                // 中心光と雲の色をブレンドして、最終的な色を決定
                float4 finalColor = lerp(_HorizonColor, terrainColor, fogFactor);

                // 【ビネット効果（外側の減衰）】
                // トンネルの外側（画面の四隅）に向かって、色を滑らかに暗く落とすことで、
                // 画面に奥行き（チューブの出口を覗いているような感覚）を強調する
                finalColor *= smoothstep(1.5, 0.4, radius);

                return finalColor;
            }
            ENDHLSL
        }
    }
}