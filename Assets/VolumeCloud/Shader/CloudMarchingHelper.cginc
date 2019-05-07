#include "UnityCG.cginc"
#define MIN_SAMPLE_COUNT 64
#define MAX_SAMPLE_COUNT 128
#define earthRadius 6500000.0

//#define THICKNESS 6500.0
#define CENTER 4750.0

//Camera position
float3 _cameraWS;
//Cutoff parameter
float _cutoff;
//Cloud scale
float _cloudScale;
//Height gradience
sampler2D _heightTex;

float _cloudBase;

float _layerHeight;

sampler3D _cloudNoise3D;

sampler2D _randomNoiseTex;

float3 _lightDir;

sampler3D _detailTex;

float _edgeScale;

float _erodeDepth;

float _coverage;

float _cloudDensity;

float _nearestRenderDistance;

//Lighting
float _BeerLaw;
float _SilverIntensity;
float _SilverSpread;

//Curl distortion
sampler2D _CurlNoise;
float _CurlTile;
float _CurlStrength;

half4 _WindDirection;
//Top offset
float _CloudTopOffset;

sampler2D _WeatherTex;
float _WeatherTexSize;

float _MaxDistance;
float _WindSpeed;
float _skyLight;

//Matrices
uniform float4x4 _inverseVP;
uniform float4x4 _WorldToShadow;





//Remapping original_value from [original_min,original_max] to [new_min,new_max]
float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}
////Remapping original_value from [original_min,original_max] to [new_min,new_max] but clamped
float RemapClamped(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (saturate((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

//Calculating height percentage, the cloud is rendered between to sphere
float HeightPercent(float3 worldPos) 
{
    //earth center is straight down from point£¨_CameraWS.x£¬0£¬_CameraWS.z)
	float3 earthCenter=float3(_cameraWS.x,-earthRadius,_cameraWS.z);
	//Height of worldPos should be length(worldPos-earthCenter)-earthRadius
	float RealHeight=length(worldPos-earthCenter)-earthRadius;

	return saturate((RealHeight-_cloudBase)/_layerHeight);
}

//Get heightGradient
float SampleHeightGradient(float h, int lod)
{
    if(h<0||h>1)
	{
	  return 0;
	}
	else
	{
	   float density=tex2Dlod(_heightTex,float4(0.5,h,0,lod)).r;
	   return density;
	}
}

float3 ApplyWind(float3 worldPos) {
	float heightPercent = HeightPercent(worldPos);
	
	// skew in wind direction
	worldPos.xz -= (heightPercent) * _WindDirection.xy * 10;

	//animate clouds in wind direction and add a small upward bias to the wind direction
	worldPos.xz -= (_WindDirection.xy + float3(0.0, 0.1, 0.0)) * _Time.y * _WindDirection.z*_WindSpeed;
	worldPos.y -= _WindDirection.z * 0.4 * _Time.y*_WindSpeed;
	return worldPos;
}

//sample density of world point with lod
float SampleDensity(float3 worldPos,int lod, bool cheap)
{
  float heightPercent = HeightPercent(worldPos);

  fixed4 tempResult;
  float3 unwindWorldPos = worldPos;
  worldPos = ApplyWind(worldPos);

  //Sample noise
  tempResult=tex3Dlod(_cloudNoise3D,float4(worldPos/_cloudScale,lod)).rgba;
  //Fbm
  float low_freq_fbm=(tempResult.g * 0.625) + (tempResult.b * 0.25) + (tempResult.a * 0.125);
  float sampleResult = tempResult.r;
  sampleResult = Remap(tempResult.r, -(1.0 - low_freq_fbm), 1.0, 0.0, 1.0);
  //Weather info
  half4 coverageSampleUV = half4((worldPos.xz*0.5 / _WeatherTexSize), 0, 0);

  coverageSampleUV.xy = (coverageSampleUV.xy + 0.01);
  float3 weatherData = tex2Dlod(_WeatherTex, coverageSampleUV);
  float coverageMulti = weatherData.r;
  
  
  //Cloud density changes according to height gradient
  sampleResult *= SampleHeightGradient(heightPercent, weatherData.g);

  sampleResult = RemapClamped(sampleResult, 1.0 - _coverage, 1.0, 0.0, 1.0);
  sampleResult *= _coverage*coverageMulti;

  //detailed sample
  if(!cheap)
  {
    float2 curl_noise = tex2Dlod(_CurlNoise, float4(unwindWorldPos.xz / _cloudScale * _CurlTile, 0.0, 1.0)).rg;
    worldPos.xz += curl_noise.rg * (1-heightPercent) * _cloudScale * _CurlStrength;
    //detail texture
    float3 tempResult2=tex3Dlod(_detailTex,half4(worldPos/_edgeScale,lod)).rgb;
	//Fbm
	float sampleDetailResult=(tempResult2.r * 0.625) + (tempResult2.g * 0.25) + (tempResult2.b * 0.125);
	//Invert sample result to get some whispy shape
	sampleDetailResult=1.0-sampleDetailResult;
	//Detail changes according to height gradient
	float detail_modifier = lerp(sampleDetailResult, 1.0 - sampleDetailResult, saturate(heightPercent));
	//Erode edge
	sampleResult = Remap(sampleResult, detail_modifier * _erodeDepth, 1.0, 0.0, 1.0);

  }
  return max(0,sampleResult);
}



//Generate random number
half rand(half3 co)
{
	return frac(sin(dot(co.xyz, half3(12.9898, 78.233, 45.5432))) * 43758.5453) - 0.5f;
}
//Hg
float HenryGreenstein(float g, float cosTheta) {
	float pif = 1.0;// (1.0 / (4.0 * 3.1415926f));
	float numerator = 1 - g * g ;
	float denominator = pow(1 + g * g - 2 * g * cosTheta, 1.5);
	return pif * numerator / denominator;
}
//Beer law
float BeerLaw(float d, float cosTheta) {
	d *= _BeerLaw;
	float firstIntes = exp(-d);
	float secondIntens = exp(-d * 0.25) * 0.7;
	float secondIntensCurve = 0.5;
	float tmp = max(firstIntes, secondIntens * RemapClamped(cosTheta, 0.7, 1.0, secondIntensCurve, secondIntensCurve * 0.25));
	return tmp;
}
 //Inscatter(adjusted powder effect)
float Inscatter(float3 worldPos,float dl, float cosTheta) {
	float heightPercent = HeightPercent(worldPos);
	float lodded_density = saturate(SampleDensity(worldPos, 1, false));
	float depth_probability = 0.3 + pow(lodded_density, RemapClamped(heightPercent, 0.3, 0.85, 0.5, 2.0));
	depth_probability = lerp(depth_probability, 1.0, saturate(dl*1));
	float vertical_probability = pow(max(0, Remap(heightPercent, 0.0, 0.14, 0.1, 1.0)), 0.8);
	return saturate(depth_probability * vertical_probability);
}

float Energy(float3 worldPos, float d, float cosTheta) {
	float hgImproved = max(HenryGreenstein(.1, cosTheta), _SilverIntensity * HenryGreenstein(0.99 - _SilverSpread, cosTheta));
	//return Inscatter(worldPos, d, cosTheta) *hgImproved * BeerLaw(d, cosTheta) * 5.0;
	//return Inscatter(worldPos, d, cosTheta) * BeerLaw(d, cosTheta) * 5.0;
	return  Inscatter(worldPos, d, cosTheta)* BeerLaw(d, cosTheta)*hgImproved;
}



//Sample energy with cone sampling
float SampleEnergy(float3 worldPos, float3 viewDir) {
#define DETAIL_ENERGY_SAMPLE_COUNT 6
	float totalSample = 0;
	int mipmapOffset = 0.5;
	for (float i = 1; i <= DETAIL_ENERGY_SAMPLE_COUNT; i++) {
		half3 rand3 = half3(rand(half3(0, i, 0)), rand(half3(1, i, 0)), rand(half3(0, i, 1)));
		half3 direction =  _WorldSpaceLightPos0* 2 + normalize(rand3);
		direction = normalize(direction);
		float3 samplePoint = worldPos 
			+ (direction * i / DETAIL_ENERGY_SAMPLE_COUNT) * 10;
		totalSample += SampleDensity(samplePoint, mipmapOffset,0);
		mipmapOffset += 0.5;
	}
	float energy = Energy(worldPos ,totalSample / DETAIL_ENERGY_SAMPLE_COUNT * _cloudDensity, dot(viewDir,_WorldSpaceLightPos0 ));
	return energy;
}

// Raymarch along given ray
				// ro: ray origin
				// rd: ray direction
				float raymarch(float3 ro, float3 rd, float randomOffset, int marchingStep, out float intensity, out float CloudDepth,float ZBuffer) {
				intensity=0;
				fixed4 ret = fixed4(0, 0, 0, 0);
				float Alpha = 0;
				CloudDepth=-1;
				int maxstep =marchingStep;
				float CheapStep=15;
				float DetailStep=5;
				float sampleStep = DetailStep;
				float Col=0;
				float d=0 ;//sample value
				float RaymarchDistance=0;
				float LastDistance;
				bool Cheap=false;
				int missedCount=0;
				for (int i = 0; i < maxstep; ++i)
				{ 
					float3 p = ro + rd*RaymarchDistance; // Sample point
					 float toAtmosphereDistance=0;
					//if ro is under _cloudBase,launch the ray directly to the bottom of the cloud
				    if(ro.y<_cloudBase)
				    {
					    //Calculating intersection point of ray and sphere, but this doesn't work properly, need improvement.
				        float3 earthCenter=float3(_cameraWS.x,-earthRadius,_cameraWS.z);
						float radius=earthRadius;
						float delta=pow(2*dot(rd,(ro-earthCenter)),2)-4*dot(rd,rd)*(dot((ro-earthCenter),(ro-earthCenter))-pow(radius,2));
						if(delta>=0)
						{
						   //-dot(OC, D) - ¡Ì( sqr( dot(OC, D) ) - dot(OC, OC) + R¡¤R )
						   
						   if(rd.y>=0)
						   {
						     toAtmosphereDistance = -dot(rd, ro-earthCenter) - pow(pow(dot(rd, ro-earthCenter), 2) - dot(ro-earthCenter, ro-earthCenter) + pow(radius, 2), 0.5);
							 if(toAtmosphereDistance>0)
							 {
							   p+=rd*toAtmosphereDistance;
							 }
						   }
						   else
						   {
						     toAtmosphereDistance = -dot(rd, ro-earthCenter) + pow(pow(dot(rd, ro-earthCenter), 2) - dot(ro-earthCenter, ro-earthCenter) + pow(radius, 2), 0.5);
							 if(toAtmosphereDistance>0)
							 {
							   p+=rd*toAtmosphereDistance;	
							 }
						   }
						}
				    }
					//if ro is above cloud, launch the ray directly to the top of the cloud layer
					else if(ro.y>_cloudBase+_layerHeight)
					{
				        float3 earthCenter=float3(_cameraWS.x,-earthRadius,_cameraWS.z);
						float radius=earthRadius+_cloudBase+_layerHeight;
						float delta=pow(2*dot(rd,(ro-earthCenter)),2)+4*dot(rd,rd)*(dot((ro-earthCenter),(ro-earthCenter))-pow(radius,2));
						if(delta>=0)
						{
						   //-dot(OC, D) - ¡Ì( sqr( dot(OC, D) ) - dot(OC, OC) + R¡¤R )
						   toAtmosphereDistance = -dot(rd, ro-earthCenter) - pow(pow(dot(rd, ro-earthCenter), 2) - dot(ro-earthCenter, ro-earthCenter) + pow(radius, 2), 0.5);
						   if(rd.y<0&&toAtmosphereDistance>0)
						   {
						     p+=rd*toAtmosphereDistance;
						   }
						}
					}
					else
					{
						p += rd * _nearestRenderDistance;
					}
					float dist=length(p-ro);
					//Cloud depth
					if(dist>=ZBuffer)
					{
					   break;
					}
					if(p.y>_cloudBase+_layerHeight&&rd.y>0)
					  {
					     break;
					  }
					 
					  if(i==0)
					  {
					     RaymarchDistance+=randomOffset*(CheapStep+DetailStep)/2;
					  }
					  if(!Cheap)
					  {
					    d=SampleDensity(p,0,false);
					    //Sample step size will change according to sample result
					    if(d!=0)
				        {
					      missedCount=0;
				          float sampleAlpha=d*sampleStep*_cloudDensity;
						  float sampledEnergy = SampleEnergy(p, rd);
				          intensity += (1 - Alpha) * sampledEnergy * sampleAlpha;
				          Alpha += (1-Alpha)*sampleAlpha;
				          sampleStep=DetailStep;
						  if(CloudDepth==-1)
				          {
							   CloudDepth=dist; 
				          }
				    	 }
			  		    else
					    {
					       //if there are over 10 steps that sampled nothing, step size will switch to a larger size
					       if(missedCount<10)
						   {
						     missedCount++;
						   }
						   else
						   {
						     Cheap=true;
						     sampleStep=CheapStep;
						   }
					    }
					  }
					  else
				   	  {
					    d=SampleDensity(p,5,true);
					    //If sample value is not 0, switch to detail step, but step back once before continue.
					    if(d!=0)
					    {
					      Cheap=false;
						  sampleStep=DetailStep;
						  missedCount=0;
						  RaymarchDistance-=CheapStep;
					    }
					    else
					    {
					      Cheap=true;
					    }
					  }
					RaymarchDistance+=sampleStep;
					//If alpha reaches 1, break the loop
					if(Alpha>=1)
					{
					  intensity /= Alpha;
					  return 1;
					}
					
				}		

				//Cut off
				Alpha=saturate((Alpha-_cutoff)/(1-_cutoff));
				if(Alpha>0)
				{
				  intensity /= Alpha;
				}
				if(CloudDepth==-1)
				{
				   CloudDepth=_MaxDistance;
				}
				return Alpha;
			}

			//Almost same above but no light calculation
			float GetCloudDensity(float3 ro, float3 rd,float DetailStep,float CheapStep, float randomOffset, int marchingStep, out float CloudDepth)
			{
			   fixed4 ret = fixed4(0, 0, 0, 0);
				float Alpha = 0;
				CloudDepth=-1;
				int maxstep =marchingStep;
				float sampleStep = DetailStep;
				float Col=0;
				float d=0 ;
				float RaymarchDistance=0;
				float LastDistance;
				bool Cheap=false;
				int missedCount=0;
				for (int i = 0; i < maxstep; ++i)
				{ 
					float3 p = ro + rd*RaymarchDistance; 
				    if(ro.y<_cloudBase)
				    {
				        float3 earthCenter=float3(_cameraWS.x,-earthRadius,_cameraWS.z);
						float radius=earthRadius;
						float delta=pow(2*dot(rd,(ro-earthCenter)),2)-4*dot(rd,rd)*(dot((ro-earthCenter),(ro-earthCenter))-pow(radius,2));
						if(delta>=0)
						{
						   //-dot(OC, D) - ¡Ì( sqr( dot(OC, D) ) - dot(OC, OC) + R¡¤R )
						   if(rd.y>0)
						   {
						     float toAtmosphereDistance = -dot(rd, ro-earthCenter) + pow(pow(dot(rd, ro-earthCenter), 2) - dot(ro-earthCenter, ro-earthCenter) + pow(radius, 2), 0.5);
							 if(toAtmosphereDistance>0)
							 {
							   p+=rd*toAtmosphereDistance;
							 }
						   }
						   else
						   {
						     float toAtmosphereDistance = -dot(rd, ro-earthCenter) + pow(pow(dot(rd, ro-earthCenter), 2) - dot(ro-earthCenter, ro-earthCenter) + pow(radius, 2), 0.5);
							 if(toAtmosphereDistance>0)
							 {
							   p+=rd*toAtmosphereDistance;
							 }
						   }
						}
				    }
					else if(ro.y>_cloudBase+_layerHeight)
					{
				        float3 earthCenter=float3(_cameraWS.x,-earthRadius,_cameraWS.z);
						float radius=earthRadius+_cloudBase+_layerHeight;
						float delta=pow(2*dot(rd,(ro-earthCenter)),2)+4*dot(rd,rd)*(dot((ro-earthCenter),(ro-earthCenter))-pow(radius,2));
						if(delta>=0)
						{
						   float toAtmosphereDistance = -dot(rd, ro-earthCenter) - pow(pow(dot(rd, ro-earthCenter), 2) - dot(ro-earthCenter, ro-earthCenter) + pow(radius, 2), 0.5);
						   if(rd.y<0&&toAtmosphereDistance>0)
						   {
						     p+=rd*toAtmosphereDistance;
						   }
						}
					}
					  if(p.y>_cloudBase+_layerHeight&&rd.y>0)
					  {
					     break;
					  }
					  if(i==0)
					  {
					     RaymarchDistance+=randomOffset*5;
					  }
					  if(!Cheap)
					  {
					    d=SampleDensity(p,0,false);
					    if(d!=0)
				        {
					      missedCount=0;
				          float sampleAlpha=d*sampleStep*_cloudDensity;
				          Alpha += (1-Alpha)*sampleAlpha;
				          sampleStep=DetailStep;
						  //This part should have been used for screen space shadow calculation, but the function is not finished yet
						  if(CloudDepth==-1)
				          {
				             float z = length(p-ro);
                             float near = _ProjectionParams.y; //nearPlane
                             float far = _ProjectionParams.z; //farPlane
                             float _offset=10;
                             //Use WorldUnit offset(linear) to calculate needed Depth Buffer offset(non-linear)
                             //float offsetNeeded = z*(1/z-1/(z-_offset))*(far*near/(far-near));
                             float depthBufferOffset = (1 - z /(z - _offset)) * (far*near/(far-near)); //Simplfy
				             CloudDepth=depthBufferOffset;
				          }
				    	 }
			  		    else
					    {
					       if(missedCount<10)
						   {
						     missedCount++;
						   }
						   else
						   {
						     Cheap=true;
						     sampleStep=CheapStep;
						   }
					    }
					   
					  }
					  else
				   	  {
					    d=SampleDensity(p,5,true);
					    if(d!=0)
					    {
					      Cheap=false;
						  sampleStep=DetailStep;
						  missedCount=0;
						  RaymarchDistance-=CheapStep;
					    }
					    else
					    {
					      Cheap=true;
					    }
					  }
					RaymarchDistance+=sampleStep;
					if(Alpha>=1)
					{
					  return 1;
					}
					
				}
				if(CloudDepth==-1)
				{
				   CloudDepth=1;
				}
				Alpha=saturate((Alpha-_cutoff)/(1-_cutoff));
				
				return Alpha;
			}

			//Calculating light, this is a very rough volumetric light effect
			float GetAccumulatedLight(float3 ro, float3 rd, int maxstep, float marchingStep,float randomOffset, float ZBuffer)
			{
			   float LightAmount=0;
			   float3 samplePos=ro;
			   float MarchingDistance=0;
			   for(int i=0;i<maxstep;i++)
			   {
			      if(i==0)
				  {
				    MarchingDistance+=randomOffset*marchingStep;
				  }
				 
				  samplePos=ro+rd*MarchingDistance;
				   if(length(samplePos-ro)>ZBuffer)
				   {
				      break;
				   }
				  float _tempDepth;
				  float shadowAmount=GetCloudDensity(samplePos,_WorldSpaceLightPos0,5,15,randomOffset,30,_tempDepth);
		
				     LightAmount+=saturate(1-shadowAmount)/(length(0.01*(samplePos-ro)+1));
				  
				  MarchingDistance+=marchingStep;
				  if(LightAmount>0.6)
				  {
				    return 0.8;
				  }
			   }
			   return LightAmount;
			}