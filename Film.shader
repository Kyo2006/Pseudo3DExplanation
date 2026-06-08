Shader "Custom/CastlevaniaFilmPerforation7PhotoShape"
{
    Properties
    {
        _ScrollSpeed ("Scroll Speed", Float) = 0.1
        _PixelResX ("Pixel Resolution X", Float) = 256
        _PixelResY ("Pixel Resolution Y", Float) = 224
        
        [Header(Film Strip Settings)]
        _FilmWidth ("Film Width (Black Band)", Range(0.0, 0.5)) = 0.15
        
        [Header(Hole Settings)]
        _HoleOffsetX ("Hole Center Offset X", Range(0.0, 0.5)) = 0.075
        
        _HoleWidthPixels ("Hole Width (Pixels)", Range(0.0, 64.0)) = 32.0
        _HoleHeightPixels ("Hole Height (Pixels)", Range(0.0, 64.0)) = 24.0
        _HoleRoundnessPixels ("Hole Roundness (Pixels)", Range(0.0, 16.0)) = 2.0
        
        _FilmColor ("Hole Color (Yellow)", Color) = (0.95, 0.85, 0.56, 1.0)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
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

            float _ScrollSpeed;
            float _PixelResX;
            float _PixelResY;
            float _FilmWidth;
            float _HoleOffsetX;
            float _HoleWidthPixels;
            float _HoleHeightPixels;
            float _HoleRoundnessPixels;
            fixed4 _FilmColor;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float sdRoundedBox(float2 p, float2 b, float r)
            {
                float2 d = abs(p) - b + float2(r, r);
                return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float2 uv = floor(i.uv * float2(_PixelResX, _PixelResY)) / float2(_PixelResX, _PixelResY);
                float timeStep = floor(_Time.y * _ScrollSpeed * _PixelResY) / _PixelResY;

                float distFromCenter = abs(uv.x - 0.5);

                // 2. 両端の黒い帯エリアの定義
                float bandMask = step(0.5 - _FilmWidth, distFromCenter);

                // 3. 縦方向にぴったり7分割してループスクロール
                float scrollY = uv.y - timeStep;
                float fracY = frac(scrollY * 7.0);

                // 4. ピクセル単位のローカル座標に変換（歪み補正）
                float holeLocalX = abs(distFromCenter - (0.5 - _HoleOffsetX));
                float holeLocalY = fracY - 0.5;
                
                float pixelX = holeLocalX * _PixelResX;
                float pixelY = holeLocalY * (_PixelResY / 7.0);
                float2 holeLocalPixels = float2(pixelX, pixelY);

                // 5. ピクセル単位で長方形（写真の形）のSDFを計算
                float2 halfSize = float2(_HoleWidthPixels * 0.5, _HoleHeightPixels * 0.5);
                float distToBox = sdRoundedBox(holeLocalPixels, halfSize, _HoleRoundnessPixels);
                
                // 穴の内側を1、外側を0にする
                float holeMask = step(distToBox, 0.0);

                // 6. 帯の範囲内に存在する穴だけを抽出
                float finalPattern = bandMask * holeMask;

                // 7. カラー出力
                fixed4 finalColor = lerp(fixed4(0, 0, 0, 1), _FilmColor, finalPattern);

                return finalColor;
            }
            ENDCG
        }
    }
}