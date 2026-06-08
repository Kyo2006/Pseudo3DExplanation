Shader "Custom/Pseudo3D2"
{
    Properties
    {
        [Header(Colors)]
        _ColorA1 ("Color A1", Color) = (0.0, 0.4, 1.0, 1)
        _ColorA2 ("Color A2", Color) = (1.0, 1.0, 1.0, 1)
        _ColorB1 ("Color B1", Color) = (1.0, 0.0, 0.0, 1)
        _ColorB2 ("Color B2", Color) = (1.0, 1.0, 1.0, 1)

        [Header(Camera)]
        _Perspective ("Perspective Gain", Range(0.1, 3.0)) = 1.0 
        _HorizonOffset ("Horizon Smoothness", Range(0.001, 0.1)) = 0.01
        
        [Header(Movement)]
        _Density ("Grid Density", Range(1, 100)) = 40
        _ForwardSpeed ("Forward Speed (Very Slow)", Range(0, 5)) = 0 // 0～5の範囲で微調整可能
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

            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float2 uv : TEXCOORD0; float4 vertex : SV_POSITION; };

            fixed4 _ColorA1, _ColorA2, _ColorB1, _ColorB2;
            float _Perspective, _HorizonOffset, _Density, _ForwardSpeed, _FlashSpeed;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 1. 深度計算 (画面全体に広がるように上端を消失点にする)
                float depth = 1.0 / (pow(max(0.0001, 1.0 - i.uv.y), _Perspective) + _HorizonOffset);
                
                float2 p3Duv;
                p3Duv.x = (i.uv.x - 0.5) * depth;
                
                // 2. 超低速移動
                // _ForwardSpeedを小さくすることで、じわじわと動かします
                p3Duv.y = depth + (_Time.y * _ForwardSpeed);

                // 3. 市松模様
                float2 grid = floor(p3Duv * _Density * 0.05);
                float checker = abs(fmod(grid.x + grid.y, 2.0));
                float isColor2 = step(0.5, checker);

                // 4. 色の点滅 (点滅も速度に合わせてゆっくり)
                float flash = step(0.5, frac(_Time.y * _FlashSpeed * 0.1));
                
                fixed4 col;
                if (flash < 0.5) {
                    col = lerp(_ColorA1, _ColorA2, isColor2);
                } else {
                    col = lerp(_ColorB1, _ColorB2, isColor2);
                }

                return col;
            }
            ENDCG
        }
    }
}