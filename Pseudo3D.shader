Shader "Custom/Pseudo3D"
{
    Properties
    {
        _ColorA1 ("Color A (State 1)", Color) = (1, 1, 1, 1)
        _ColorA2 ("Color A (State 2)", Color) = (0.8, 0.8, 0.8, 1)
        _ColorB1 ("Color B (State 1)", Color) = (0, 0, 0, 1)
        _ColorB2 ("Color B (State 2)", Color) = (0.2, 0.2, 0.2, 1)
        _Density ("Grid Density", Float) = 10
        _Speed ("Scroll Speed", Float) = 2.0
        _FlashSpeed ("Color Swap Speed", Float) = 5.0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            fixed4 _ColorA1, _ColorA2, _ColorB1, _ColorB2;
            float _Density, _Speed, _FlashSpeed;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float2 uv = i.uv;

                // --- 1. 擬似3Dパースの計算 ---
                // uv.yを反転させて、上が地平線、下が手前になるように調整
                float perspective = 1.0 / (uv.y + 0.05);
                
                float2 p3Duv;
                // X座標：中央(0.5)から広がるように計算
                p3Duv.x = (uv.x - 0.5) * perspective + 0.5;
                // Y座標：パースを適用し、時間でスクロール
                p3Duv.y = perspective + (_Time.y * _Speed);

                // --- 2. 市松模様の計算 ---
                float2 grid = floor(p3Duv * _Density);
                // XとYのインデックスを足して2で割った余り(0か1)
                float checker = abs(fmod(grid.x + grid.y, 2.0));
                // fmodの結果が1に近いか0に近いかで0か1に丸める
                checker = step(0.5, checker);

                // --- 3. 時間による色の切り替え (動画の再現) ---
                // 0か1でパカパカ切り替わるフラグ
                float colorSwap = step(0.5, frac(_Time.y * _FlashSpeed * 0.2));
                
                fixed4 colA = lerp(_ColorA1, _ColorA2, colorSwap);
                fixed4 colB = lerp(_ColorB1, _ColorB2, colorSwap);

                // 市松模様の色を決定
                fixed4 finalCol = lerp(colA, colB, checker);

                // --- 4. 仕上げ (フォグ/フェード) ---
                // 上(地平線)に行くほど暗く、または透明にする
                finalCol.rgb *= pow(uv.y, 1.5); 
                
                return finalCol;
            }
            ENDCG
        }
    }
}