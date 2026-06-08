Shader "Custom/Pseudo3DCheckPixelated"
{
    Properties
    {
        [Header(Color Settings)]
        _ColorA ("Floor Mint Green", Color) = (0.50, 0.90, 0.61, 1)
        _ColorB ("Floor Emerald Green", Color) = (0.31, 0.78, 0.47, 1)
        _ColorFog ("Horizon Fog Color", Color) = (0.60, 0.88, 0.75, 1)
        
        [Header(Grid Settings)]
        _LinesCount ("放射ラインの数", Float) = 28.0
        _DensityY ("奥への詰まり具合", Float) = 32.0
        _Speed ("Scroll Speed", Float) = 30.0                          // コマ送り化により、さらに数値を上げても線が繋がりません
        _FrameRate ("Pattern Animation FPS", Float) = 30.0             // 地面の更新コマ数（30fpsや60fpsに制限して残像を防ぐ）
        
        [Header(Retro Settings)]
        _PixelSize ("Pixelation Level", Float) = 500.0
        _Jitter ("Scanline Jitter", Float) = 0.002
        
        [Header(Internal Offsets)]
        _HorizontalOffset ("Horizontal Offset", Float) = 0.0
        _VerticalOffset ("Vertical Offset", Float) = 0.0
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

            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float2 uv : TEXCOORD0; float4 vertex : SV_POSITION; };

            fixed4 _ColorA, _ColorB, _ColorFog;
            float _LinesCount, _DensityY, _Speed, _FrameRate, _PixelSize, _Jitter;
            float _HorizontalOffset, _VerticalOffset;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float2 uv = floor(i.uv * _PixelSize) / _PixelSize;
                uv.x += sin(uv.y * 500.0) * _Jitter;

                // 地平線制御
                float shiftedY = uv.y + _VerticalOffset;
                if (shiftedY <= 0.0) discard;

                // 2. 擬似3Dパース計算
                float perspective = 1.0 / (shiftedY + 0.005);
                float radialX = (uv.x - 0.5) * perspective + (_HorizontalOffset * 2.0);
                
                // これにより、ハイスピードでも横ラインが引き伸ばされて繋がることがなくなります
                float pixelTime = floor(_Time.y * _FrameRate) / _FrameRate;
                float depthY = perspective + (pixelTime * _Speed) + (_HorizontalOffset * 0.4);

                // 3. 模様の生成（stepでパキッと分ける）
                float stripX = step(0.0, sin(radialX * _LinesCount));
                float stripY = step(0.0, sin(depthY * _DensityY));
                
                float pattern = saturate(stripX * 0.6 + stripY * 0.4);
                
                // 4. 色の量子化
                fixed4 finalCol = lerp(_ColorB, _ColorA, pattern);
                finalCol = floor(finalCol * 8.0) / 8.0;

                // 5. 大気効果
                float fogFactor = saturate(shiftedY * 2.5);
                finalCol.rgb = lerp(_ColorFog.rgb, finalCol.rgb, pow(fogFactor, 0.4));
                
                return finalCol;
            }
            ENDCG
        }
    }
}