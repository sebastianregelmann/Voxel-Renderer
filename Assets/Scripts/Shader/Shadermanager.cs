using UnityEngine;
using UnityEngine.Experimental.Rendering;
using SysDebug = System.Diagnostics;
using UnityEngine.Rendering;

public class Shadermanager : MonoBehaviour
{
    [Header("References")]
    public ComputeShader shader;
    public Material renderMaterial;


    //Compute Buffers
    private ComputeBuffer vertexPositionsBuffer;
    private ComputeBuffer triangleIndicesBuffer;
    private RenderTexture voxelTexture;


    //Kernel Indexes
    private int kernelVoxelize;
    private int kernelVoxelizeShell;


    //Helper variables to keep track of mesh data and voxel settings
    private Mesh mesh;
    private int triangleCount;
    private int vertexCount;
    private float voxelSize;
    private Vector3 boundsMin;
    private Vector3 boundsMax;
    private int resolution = 1;



    // Start is called before the first frame update
    void Start()
    {
        GetKernelIDs();
    }


    /// <summary>
    /// Get's the kernel size from the shader
    /// </summary>
    private Vector3Int GetThreadGroupSize(int kernelID)
    {
        uint x, y, z;

        shader.GetKernelThreadGroupSizes(kernelID, out x, out y, out z);

        return new Vector3Int((int)x, (int)y, (int)z);
    }


    /// <summary>
    /// Gets the kernel IDs from the shader
    /// </summary>
    private void GetKernelIDs()
    {
        kernelVoxelize = shader.FindKernel("Voxelize");
        kernelVoxelizeShell = shader.FindKernel("VoxelizeShell");
    }

    private void SetMeshRelatedVariables()
    {
        triangleCount = mesh.triangles.Length;
        vertexCount = mesh.vertices.Length;
        boundsMin = mesh.bounds.min;
        boundsMax = mesh.bounds.max;
        voxelSize = Mathf.Max(Mathf.Max(mesh.bounds.size.x, mesh.bounds.size.y), mesh.bounds.size.z) / resolution;
    }

    private void DispatchVoxelizeVolume()
    {
        if (mesh == null)
        {
            throw new System.Exception("No Mesh Asigned");
        }

        //Release buffer if old one exists
        triangleIndicesBuffer?.Release();
        vertexPositionsBuffer?.Release();
        voxelTexture?.Release();
        triangleIndicesBuffer = null;
        vertexPositionsBuffer = null;
        voxelTexture = null;

        SetMeshRelatedVariables();

        //Create the Buffers
        triangleIndicesBuffer = new ComputeBuffer(triangleCount, sizeof(int));
        vertexPositionsBuffer = new ComputeBuffer(vertexCount, sizeof(float) * 3);
        voxelTexture = CreateInt3DTexture(resolution, resolution, resolution);


        //Set data to the Buffers
        triangleIndicesBuffer.SetData(mesh.triangles);
        vertexPositionsBuffer.SetData(mesh.vertices);

        //Assing Buffers for shader
        shader.SetBuffer(kernelVoxelize, "_TriangleIndicesIn", triangleIndicesBuffer);
        shader.SetBuffer(kernelVoxelize, "_VertexPositionsIn", vertexPositionsBuffer);
        shader.SetTexture(kernelVoxelize, "_VoxelTexture", voxelTexture);

        //Assing Variables for the Shader
        shader.SetInt("_TriangleCount", mesh.triangles.Length);
        shader.SetInt("_Resolution", resolution);
        shader.SetFloat("_VoxelSize", voxelSize);
        shader.SetVector("_BoundsMin", boundsMin);
        shader.SetVector("_BoundsMax", boundsMax);

        //Calculate the number of threads dispatched
        Vector3Int threadGroupSize = GetThreadGroupSize(kernelVoxelize);
        Vector3Int threadCount = new Vector3Int(Mathf.CeilToInt((float)resolution / threadGroupSize.x), Mathf.CeilToInt((float)resolution / threadGroupSize.y), Mathf.CeilToInt((float)resolution / threadGroupSize.z));

        //Dispatch the shader
        shader.Dispatch(kernelVoxelize, threadCount.x, threadCount.y, threadCount.z);
    }


    private void DispatchVoxelizeShell()
    {
        if (mesh == null)
        {
            throw new System.Exception("No Mesh Asigned");
        }

        //Release buffer if old one exists
        triangleIndicesBuffer?.Release();
        vertexPositionsBuffer?.Release();
        voxelTexture?.Release();
        triangleIndicesBuffer = null;
        vertexPositionsBuffer = null;
        voxelTexture = null;

        SetMeshRelatedVariables();

        //Create the Buffers
        triangleIndicesBuffer = new ComputeBuffer(triangleCount, sizeof(int));
        vertexPositionsBuffer = new ComputeBuffer(vertexCount, sizeof(float) * 3);
        voxelTexture = CreateInt3DTexture(resolution, resolution, resolution);


        //Set data to the Buffers
        triangleIndicesBuffer.SetData(mesh.triangles);
        vertexPositionsBuffer.SetData(mesh.vertices);

        //Assing Buffers for shader
        shader.SetBuffer(kernelVoxelizeShell, "_TriangleIndicesIn", triangleIndicesBuffer);
        shader.SetBuffer(kernelVoxelizeShell, "_VertexPositionsIn", vertexPositionsBuffer);
        shader.SetTexture(kernelVoxelizeShell, "_VoxelTexture", voxelTexture);

        //Assing Variables for the Shader
        shader.SetInt("_TriangleCount", triangleCount);
        shader.SetInt("_Resolution", resolution);
        shader.SetFloat("_VoxelSize", voxelSize);
        shader.SetVector("_BoundsMin", boundsMin);
        shader.SetVector("_BoundsMax", boundsMax);

        //Calculate the number of threads dispatched
        Vector3Int threadGroupSize = GetThreadGroupSize(kernelVoxelizeShell);
        Vector3Int threadCount = new Vector3Int(Mathf.CeilToInt(triangleCount / threadGroupSize.x), 1, 1);

        //Dispatch the shader
        shader.Dispatch(kernelVoxelizeShell, threadCount.x, threadCount.y, threadCount.z);
    }


    /// <summary>
    /// Creates a 3D RWTexture
    /// </summary>
    RenderTexture CreateInt3DTexture(int width, int height, int depth)
    {
        RenderTexture rt = new RenderTexture(width, height, 0);
        rt.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        rt.volumeDepth = depth;
        rt.enableRandomWrite = true;
        rt.wrapMode = TextureWrapMode.Clamp;
        rt.filterMode = FilterMode.Point;
        rt.graphicsFormat = GraphicsFormat.R32_SInt;
        rt.Create();
        return rt;
    }



    /// <summary>
    /// Creates a 3D voxel Texture based on the parameter
    /// </summary>
    public void VoxeliseMesh(Mesh mesh, int resolution, VOXELMETHOD voxelMethod)
    {
        //Updates internal mesh settings based on the given paramete
        this.mesh = mesh;
        this.resolution = resolution;

        //Dispatches the shader based on the voxelize method
        switch (voxelMethod)
        {
            case VOXELMETHOD.VOLUME:
                DispatchVoxelizeVolume();
                break;
            case VOXELMETHOD.VOLUME_COMPRESSED:
                DispatchVoxelizeVolume();
                break;
            case VOXELMETHOD.SHELL:
                DispatchVoxelizeShell();
                break;
            case VOXELMETHOD.SHELL_COMPRESSED:
                DispatchVoxelizeShell();
                break;
        }
        //Update settings in the render shader based on the new voxelization
        UpdateRenderShaderVoxelSettings();
    }


    /// <summary>
    /// Updates voxel settings variables in the Render Shader
    /// </summary>
    private void UpdateRenderShaderVoxelSettings()
    {
        if (voxelTexture == null)
        {
            Debug.LogError("No Voxel Texture Ready");
            return;
        }

        //Internal values from the Voxelize shader
        renderMaterial.SetTexture("_VoxelTexture", voxelTexture);
        renderMaterial.SetInt("_Resolution", resolution);
        renderMaterial.SetFloat("_VoxelSize", voxelSize);
        renderMaterial.SetVector("_BoundsMin", boundsMin);
        renderMaterial.SetVector("_BoundsMax", boundsMax);
    }

    public void UpdateRenderShaderRenderSettings(RENDER_MODE renderMode, Texture[] textures, bool ambientOcclusion)
    {
        renderMaterial.SetInt("_RenderMode", (int)renderMode);

        for (int i = 0; i < textures.Length; i++)
        {
            renderMaterial.SetTexture("_FaceTexture_" + i.ToString(), textures[i]);
        }

        //Disable Ambient Occlusion if render mode is set to DEPTH
        renderMaterial.SetInt("_AmbientOcclusion", ambientOcclusion && !(renderMode == RENDER_MODE.DEPTH) ? 1 : 0);
    }



    void OnDestroy()
    {
        voxelTexture?.Release();
        voxelTexture = null;

        triangleIndicesBuffer?.Release();
        triangleIndicesBuffer = null;

        vertexPositionsBuffer?.Release();
        vertexPositionsBuffer = null;
    }
}


public enum RENDER_MODE
{
    SOLID = 0,
    POSITION = 1,
    DEPTH = 2,
    FACE = 3,
    UV = 4,
    TEXTURE = 5,
    LOCAL_POS = 6
}


public enum VOXELMETHOD
{
    VOLUME = 0,
    VOLUME_COMPRESSED = 1,
    SHELL = 2,
    SHELL_COMPRESSED = 3
}