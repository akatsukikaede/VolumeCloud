// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Hidden/CloudRenderer"
{// Provided by our script
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}
		_cutoff("_cutoff",float)=0.3 
		_cloudScale("_cloudScale",float)=3.0
		_heightText("_heightText",2D)="white" {}
		_cloudBase("_cloudBase",float)=30
		_layerHeight("_layerHeight",float)=15
		 _cloudNoise3D("_cloudNoise3D",3D)="white" {}
		 _randomNoiseTex("_randomNoiseTex",2D)="white"{}
		 _lightDir("_lightDir",vector)=(1,1,1)
		 _detailTex("_detailTex",3D)="white" {}
		 _edgeScale("_edgeScale",float)=0.3
		 _erodeDepth("_erodeDepth",float)=0.5
		 _coverage("_coverage",float)=0.2
		 _extinction("_extinction",float)=0.2
		 _cloudDensity("_cloudDensity",float)=0.1
		 _cameraWS("_cameraWS",vector)=(0,0,0)
	     _NoiseTex("Texture",3D)="" {}
		 _BeerLaw("BeerLaw",float) = 1
		 _SilverIntensity("SilverIntensity",float) = .8
		 _SilverSpread("SilverSpread",float) = .75
		 _screenHeight("ScreenHeight",float)=1080
         _screenWidth("ScreenWidth",float)=1920
		 _DepthTexture("DepthTexture",2D)="white" {}
		 _CurlNoise("CurlNoise", 2D) = "white"{}
		 _CurlTile("CurlTile", float) = .2
		 _CurlStrength("CurlStrength", float) = 1
		 _WindDirection("WindDirection",Vector) = (1,1,10,1)
		 _CloudTopOffset("TopOffset",float) = 100
		 _MaxDistance("MaxDistance",float)=100000
		 //_skyLight("skyLight",float3)=(1,1,1)
	}
		SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
	{
		CGPROGRAM

        #pragma vertex vert
        #pragma fragment frag

		//Tags { LightMode = Vertex }

		//#include "noiseSimplex.cginc"
		#include "./CloudMarchingHelper.cginc"
		#include "UnityCG.cginc"
		//#include "UnityDeferredLibrary.cginc"

			uniform float4x4 _FrustumCornersES;
			uniform sampler2D _MainTex;
			uniform float4 _MainTex_TexelSize;
			uniform float4x4 _CameraInvViewMatrix;
			uniform sampler2D _CameraDepthTexture;
			uniform sampler2D _CloudShadowMap;
			fixed4 _LightColor0;
			

			// Input to vertex shader
			struct appdata
			{
				// Remember, the z value here contains the index of _FrustumCornersES to use
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			// Output of vertex shader / input to fragment shader
			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 ray : TEXCOORD1;
				float4 screenPos : TEXCOORD2;
			};

			v2f vert(appdata v)
			{
				v2f o;

				// Index passed via custom blit function in RaymarchGeneric.cs
				half index = v.vertex.z;
				v.vertex.z = 0.1;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.screenPos = ComputeScreenPos(o.pos);
				o.uv = v.uv.xy;

		#if UNITY_UV_STARTS_AT_TOP
				if (_MainTex_TexelSize.y < 0)
					o.uv.y = 1 - o.uv.y;
		#endif

				// Get the eyespace view ray (normalized)
				o.ray = _FrustumCornersES[(int)index].xyz;
				o.ray /= abs(o.ray.z);

				// Transform the ray from eyespace to worldspace
				// Note: _CameraInvViewMatrix was provided by the script
				o.ray = mul(_CameraInvViewMatrix, o.ray);


				return o;
			}

			fixed4 frag(v2f i) : SV_Target
			{
				// ray direction
				float3 rd = normalize(i.ray.xyz);
				// ray origin (camera position)
				float3 ro = _cameraWS;

				float2 duv = i.uv;
                #if UNITY_UV_STARTS_AT_TOP
                if (_MainTex_TexelSize.y < 0)
				{
				   duv.y = 1 - duv.y;
				}
                 #endif 
                // Convert from depth buffer (eye space) to true distance from camera
                // This is done by multiplying the eyespace depth by the length of the "z-normalized"
                // ray (see vert()).  Think of similar triangles: the view-space z-distance between a point
                // and the camera is proportional to the absolute distance.
                float depthVal = LinearEyeDepth(tex2D(_CameraDepthTexture, duv).r);
                depthVal *= length(i.ray.xyz);
				float cloudDepth;
				//_cameraWS=ro;
				fixed3 col = tex2D(_MainTex,i.uv); // Color of the scene before this shader was run
				float2 screenPos = i.screenPos.xy / i.screenPos.w;
			    //RandomOffset
				float  noiseSample = tex2Dlod(_randomNoiseTex, float4(frac((screenPos * _ScreenParams.xy / 64).y + _SinTime.x), frac((screenPos * _ScreenParams.xy / 64).x + _SinTime.y),0,0)).r ;
				float intensity;
				float add = raymarch(ro, rd, noiseSample,150, intensity,cloudDepth,depthVal);
				if(cloudDepth>_MaxDistance)
				{
				   float distinct=cloudDepth-_MaxDistance;
				   add=add/(0.000008*distinct*distinct+1);
				}
				fixed4 result;
				
				   float3 skyCol=intensity*_LightColor0.xyz;
				   result=fixed4(skyCol, add);
				
				//Get depth map to blend cloud into the scene
				float3 ScreenToWorldP=ro+rd*depthVal;
				fixed4 ShadowResult=0;
				fixed4 shadowTex=0;
				if(depthVal<1000)
				{
				   float _TempIntensity;
				   float _TempDepth;
				   //calculating shadow
				   float ShadowAmount= GetCloudDensity(ScreenToWorldP, _WorldSpaceLightPos0,5,15, noiseSample,20,_TempDepth);
				  
					 float3 shadowcol=float3(0,0,0);
					 
					 if(ShadowAmount>0)
					 {
					   shadowTex=fixed4(shadowcol,ShadowAmount/1.5);
					 }
					 else
					 {
					   shadowTex=0;
					 }
				}

				//Test for volumetric light
				float LightMount=GetAccumulatedLight(ro, rd, 60, 5,noiseSample, depthVal);

				float theta=dot(normalize(rd),normalize(_WorldSpaceLightPos0));

				fixed4 lightCol=fixed4(_LightColor0.xyz,LightMount*saturate(theta*theta));

				
				fixed4 lightResult=fixed4(shadowTex.xyz.xyz*(1-lightCol.w)+lightCol.xyz*lightCol.w, shadowTex.w*(1-lightCol.w)+lightCol.w*lightCol.w);

				fixed4 cloudResult = fixed4(lightResult.xyz*(1 - result.w) + result.xyz*result.w, lightResult.w*(1 - result.w) + result.w*result.w);
			
				return  cloudResult;
				
			}
				ENDCG
		}
	}
}