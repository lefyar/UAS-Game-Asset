Shader "Custom/Wota"
{
    Properties
    {
        [Header(Water Settings)]
        [MainColor] _BaseColor("Water Color", Color) = (0.0, 0.5, 0.8, 0.8)
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.1
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.9

        [Header(Wave Settings)]
        [Normal] _NormalMap("Wave Normal Map", 2D) = "bump" {}
        _NormalStrength("Wave Strength", Range(0.0, 2.0)) = 1.0
        _WaveSpeedX("Wave Speed X", Float) = 0.1
        _WaveSpeedY("Wave Speed Y", Float) = 0.1
        _WaveScale("Wave Scale", Float) = 1.0

        [Header(Intersection Foam Settings)]
        _FoamColor("Foam Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _FoamTexture("Foam Noise Map", 2D) = "white" {}
        _FoamDistance("Foam Distance (Thickness)", Range(0.01, 5.0)) = 1.0
        _FoamScale("Foam Noise Scale", Float) = 2.0
        _FoamSpeed("Foam Speed", Float) = 0.2
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half _Metallic;
                half _Smoothness;
                half _NormalStrength;
                float _WaveSpeedX;
                float _WaveSpeedY;
                float _WaveScale;

                half4 _FoamColor;
                float _FoamDistance;
                float _FoamScale;
                float _FoamSpeed;
            CBUFFER_END

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            TEXTURE2D(_FoamTexture);
            SAMPLER(sampler_FoamTexture);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 uv         : TEXCOORD1;
                float3 normalWS   : NORMAL;
                float4 tangentWS  : TANGENT;
                float4 screenPos  : TEXCOORD2;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;

                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.screenPos = ComputeScreenPos(output.positionCS);

                float2 timeOffset = float2(_Time.y * _WaveSpeedX, _Time.y * _WaveSpeedY);
                output.uv = (input.uv * _WaveScale) + timeOffset;

                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInput.normalWS;
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 normalSample = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv);
                float3 normalTS = UnpackNormalScale(normalSample, _NormalStrength);

                float sgn = input.tangentWS.w * GetOddNegativeScale();
                float3 bitangentWS = sgn * cross(input.normalWS, input.tangentWS.xyz);
                float3 normalWS = TransformTangentToWorld(normalTS,
                    half3x3(input.tangentWS.xyz, bitangentWS, input.normalWS));
                normalWS = NormalizeNormalPerPixel(normalWS);

                float2 screenUV = input.screenPos.xy / input.screenPos.w;

                float rawDepth = SampleSceneDepth(screenUV);
                float sceneZ = LinearEyeDepth(rawDepth, _ZBufferParams);

                float surfaceZ = input.screenPos.w;

                float depthDiff = sceneZ - surfaceZ;

                float foamFactor = 1.0 - saturate(depthDiff / _FoamDistance);

                float2 foamUV = (input.positionWS.xz * _FoamScale) +
                    float2(_Time.y * _FoamSpeed, _Time.y * _FoamSpeed * 0.5);
                half foamNoise = SAMPLE_TEXTURE2D(_FoamTexture, sampler_FoamTexture, foamUV).r;

                half finalFoam = smoothstep(0.0, 1.0, foamFactor * foamNoise * 2.0);

                SurfaceData surfaceData = (SurfaceData)0;

                surfaceData.albedo = lerp(_BaseColor.rgb, _FoamColor.rgb, finalFoam);
                surfaceData.metallic = _Metallic;
                surfaceData.smoothness = lerp(_Smoothness, 0.1, finalFoam);
                surfaceData.normalTS = normalTS;
                surfaceData.emission = half3(0, 0, 0);
                surfaceData.occlusion = 1.0;
                surfaceData.alpha = saturate(_BaseColor.a + finalFoam);

                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

                half4 color = UniversalFragmentPBR(inputData, surfaceData);

                return half4(color.rgb, surfaceData.alpha);
                // return half4(foamNoise, foamNoise, foamNoise, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
