using UnityEngine;
using System.Collections;

[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]
[AddComponentMenu("Effects/Raymarch (Generic)")]
public class CloudRender : SceneViewFilter
{
  

    [SerializeField]
    private Shader _EffectShader;
    [SerializeField]
    private Shader _RenderShader;

    //Noise texture to define the shape of the cloud
    public Texture3D CloudTex3D;

    [Range(0, 1)]
    //Cut off parameter
    public float CutOff;

    //Cloud scale, this affects the size of the cloud
    public float CloudScale;

    //Texture of height gradient
    public Texture2D HeightTex;

    //Altitude of the base of the cloud
    public float CloudBase;

    //This affects the thickness of the cloud
    public float LayerHeight;
    [SerializeField]
    //Using blue noise to add random offset to the marching steps
    public Texture2D BlueNoise;

    //Light source
    public Light SkyLight;

    //Texture for edge detail of the cloud 
    public Texture3D DetailTex;

    //This affects the size of edge detail
    public float EdgeScale;

    [Range(0, 1)]
    //Erode depth
    public float ErodeDepth;

    [Range(0, 1)]
    //Cloud coverage
    public float Coverage;

    //Beer law
    public float BeerLaw;

    //The intensity of the "lighting edge"
    public float SilverIntensity;

    //Spread of the light, similiar to Mie Scattering
    public float SilverSpread;

    //Curl noise texture
    public Texture2D CurlNoise;

    //Weather texture
    public Texture2D WeatherTex;

    //Size of weather Texture
    public float WeatherTexSize;

    public float CurlTile;

    public float CurlStrength;

    public float TopOffset;

    //Max render distance
    public float MaxDistance;

    //public RenderTexture cloudShadowMap;

    public float WindSpeed;

    //Overall density
    public float CloudDensity;

    // shortest render distance
    public float nearestRenderDistance;

    //[HideInInspector]
    //public CloudShadowMap ShadowMapCam;

    public Color SkyColor;

    public RenderTexture cloud;

    public Material EffectMaterial
    {
        get
        {
            if (!_EffectMaterial && _EffectShader)
            {
                _EffectMaterial = new Material(_EffectShader);
                _EffectMaterial.hideFlags = HideFlags.HideAndDontSave;
            }

            return _EffectMaterial;
        }
    }
    private Material _EffectMaterial;

    public Material RenderMaterial
    {
        get
        {
            if (!_RenderMaterial && _RenderShader)
            {
                _RenderMaterial = new Material(_RenderShader);
                _RenderMaterial.hideFlags = HideFlags.HideAndDontSave;
            }

            return _RenderMaterial;
        }
    }
    private Material _RenderMaterial;

    public Camera CurrentCamera
    {
        get
        {
            if (!_CurrentCamera)
                _CurrentCamera = GetComponent<Camera>();
            return _CurrentCamera;
        }
    }
    private Camera _CurrentCamera;
    public Camera _ShadowCamera;

    /// \brief Stores the normalized rays representing the camera frustum in a 4x4 matrix.  Each row is a vector.
    /// 
    /// The following rays are stored in each row (in eyespace, not worldspace):
    /// Top Left corner:     row=0
    /// Top Right corner:    row=1
    /// Bottom Right corner: row=2
    /// Bottom Left corner:  row=3
    private Matrix4x4 GetFrustumCorners(Camera cam)
    {
        float camFov = cam.fieldOfView;
        float camAspect = cam.aspect;

        Matrix4x4 frustumCorners = Matrix4x4.identity;

        float fovWHalf = camFov * 0.5f;

        float tan_fov = Mathf.Tan(fovWHalf * Mathf.Deg2Rad);

        Vector3 toRight = Vector3.right * tan_fov * camAspect;
        Vector3 toTop = Vector3.up * tan_fov;

        Vector3 topLeft = (-Vector3.forward - toRight + toTop);
        Vector3 topRight = (-Vector3.forward + toRight + toTop);
        Vector3 bottomRight = (-Vector3.forward + toRight - toTop);
        Vector3 bottomLeft = (-Vector3.forward - toRight - toTop);

        frustumCorners.SetRow(0, topLeft);
        frustumCorners.SetRow(1, topRight);
        frustumCorners.SetRow(2, bottomRight);
        frustumCorners.SetRow(3, bottomLeft);

        return frustumCorners;
    }

    [ExecuteInEditMode]
    private void Start()
    {
        //cloud = new RenderTexture(cloudResolutionWidth, cloudResolutionHeight, 24, RenderTextureFormat.Default);
    }

    /// \brief Custom version of Graphics.Blit that encodes frustum corner indices into the input vertices.
    /// 
    /// In a shader you can expect the following frustum cornder index information to get passed to the z coordinate:
    /// Top Left vertex:     z=0, u=0, v=0
    /// Top Right vertex:    z=1, u=1, v=0
    /// Bottom Right vertex: z=2, u=1, v=1
    /// Bottom Left vertex:  z=3, u=1, v=0
    /// 
    /// \warning You may need to account for flipped UVs on DirectX machines due to differing UV semantics
    ///          between OpenGL and DirectX.  Use the shader define UNITY_UV_STARTS_AT_TOP to account for this.
    static void CustomGraphicsBlit(RenderTexture source, RenderTexture dest, Material fxMaterial, int passNr)
    {
        RenderTexture.active = dest;

        fxMaterial.SetTexture("_MainTex", source);

        GL.PushMatrix();
        GL.LoadOrtho(); // Note: z value of vertices don't make a difference because we are using ortho projection

        fxMaterial.SetPass(passNr);

        GL.Begin(GL.QUADS);

        // Here, GL.MultitexCoord2(0, x, y) assigns the value (x, y) to the TEXCOORD0 slot in the shader.
        // GL.Vertex3(x,y,z) queues up a vertex at position (x, y, z) to be drawn.  Note that we are storing
        // our own custom frustum information in the z coordinate.
        GL.MultiTexCoord2(0, 0.0f, 0.0f);
        GL.Vertex3(0.0f, 0.0f, 3.0f); // BL

        GL.MultiTexCoord2(0, 1.0f, 0.0f);
        GL.Vertex3(1.0f, 0.0f, 2.0f); // BR

        GL.MultiTexCoord2(0, 1.0f, 1.0f);
        GL.Vertex3(1.0f, 1.0f, 1.0f); // TR

        GL.MultiTexCoord2(0, 0.0f, 1.0f);
        GL.Vertex3(0.0f, 1.0f, 0.0f); // TL

        GL.End();
        GL.PopMatrix();
    }



    [ImageEffectOpaque]
    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (!EffectMaterial)
        {
            Graphics.Blit(source, destination); // do nothing
            return;
        }
        //if (!RenderMaterial)
        //{
        //    Graphics.Blit(source, destination); // do nothing
        //    return;
        //}
        
        // pass frustum rays to shader
        EffectMaterial.SetMatrix("_FrustumCornersES", GetFrustumCorners(CurrentCamera));
        EffectMaterial.SetMatrix("_CameraInvViewMatrix", CurrentCamera.cameraToWorldMatrix);
        EffectMaterial.SetVector("_cameraWS", CurrentCamera.transform.position);
        EffectMaterial.SetTexture("_cloudNoise3D", CloudTex3D);
        EffectMaterial.SetFloat("_cutoff", CutOff);
        EffectMaterial.SetFloat("_cloudScale", CloudScale);
        EffectMaterial.SetTexture("_heightTex", HeightTex);
        EffectMaterial.SetFloat("_cloudBase", CloudBase);
        EffectMaterial.SetFloat("_layerHeight", LayerHeight);
        EffectMaterial.SetTexture("_randomNoiseTex", BlueNoise);
        //EffectMaterial.SetVector("_lightDir", SkyLight.transform.forward);
        EffectMaterial.SetTexture("_detailTex", DetailTex);
        EffectMaterial.SetFloat("_edgeScale", EdgeScale);
        EffectMaterial.SetFloat("_erodeDepth", ErodeDepth);
        EffectMaterial.SetFloat("_coverage", Coverage);
        EffectMaterial.SetFloat("_BeerLaw", BeerLaw);
        EffectMaterial.SetFloat("_SilverIntensity", SilverIntensity);
        EffectMaterial.SetFloat("_SilverSpread", SilverSpread);
        EffectMaterial.SetTexture("_CurlNoise", CurlNoise);
        EffectMaterial.SetFloat("_CurlTile", CurlTile);
        EffectMaterial.SetFloat("_CurlStrength", CurlStrength);
        EffectMaterial.SetFloat("_CloudTopOffset", TopOffset);
        EffectMaterial.SetFloat("_MaxDistance", MaxDistance);

        EffectMaterial.SetTexture("_WeatherTex", WeatherTex);
        EffectMaterial.SetFloat("_WeatherTexSize", WeatherTexSize);
        EffectMaterial.SetFloat("_nearestRenderDistance", nearestRenderDistance);
        Matrix4x4 projectionMatrix = GL.GetGPUProjectionMatrix(_CurrentCamera.projectionMatrix, false);
        projectionMatrix = GL.GetGPUProjectionMatrix(_ShadowCamera.projectionMatrix, false);
        EffectMaterial.SetMatrix("_inverseVP", Matrix4x4.Inverse(projectionMatrix * _CurrentCamera.worldToCameraMatrix));
        EffectMaterial.SetMatrix("_WorldToShadow", projectionMatrix * _ShadowCamera.worldToCameraMatrix);
        EffectMaterial.SetFloat("_WindSpeed", WindSpeed);
        EffectMaterial.SetFloat("_cloudDensity", CloudDensity);

    
        CustomGraphicsBlit(null, cloud, EffectMaterial, 0); 
        RenderMaterial.SetTexture("cloudTexture", cloud);
        Graphics.Blit(source, destination, RenderMaterial);

    }

    public void SetCoverage(float i)
    {
        Coverage = i;
    }

    public void SetBeerLaw(float i)
    {
        BeerLaw = i;
    }

    public void SetLightIntensity(float i)
    {
        SkyLight.intensity = i;
    }

    public void SetCloudBase(float i)
    {
        CloudBase = i;
    }

    public void SetLayerHeight(float i)
    {
        LayerHeight = i;
    }

    public void SetSilverIntensity(float i)
    {
        SilverIntensity = i;
    }

    public void SetSilverSpread(float i)
    {
        SilverSpread = i;
    }

    public void SetCameraHeight(float i)
    {
        Vector3 CurrentPosition = CurrentCamera.transform.position;
        CurrentPosition.y = i;
        CurrentCamera.transform.position= CurrentPosition;
    }

    public void SetWindSpeed(float i)
    {
        WindSpeed = i;
    }
}

