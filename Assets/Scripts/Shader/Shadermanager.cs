using UnityEngine;
using UnityEngine.Experimental.Rendering;
using SysDebug = System.Diagnostics;
using UnityEngine.Rendering;

public class Shadermanager : MonoBehaviour
{
    [Header("References")]

    public ComputeShader shader;
    public Material renderMaterial;
    public Mesh mesh;


    [Header("Settings")]
    [Min(1)]
    public int resolution = 1;
    [Min(2)]
    public int chunkLimit = 100;

    public Texture2D faceTexture;


    //Compute Buffers
    private ComputeBuffer vertexPositionsBuffer;
    private ComputeBuffer triangleIndicesBuffer;
    private RenderTexture voxelTexture;


    //Kernel Indexes
    private int kernelVoxelize;
    private int kernelVoxelizeChunk;
    private int kernelReadBack;

    //Helper variables
    private int triangleCount;
    private int vertexCount;
    private float voxelSize;
    private Vector3 boundsMin;
    private Vector3 boundsMax;

    //Helper variables to check changed Variabes
    private int lastReslolution;


    //Debug Variables
    [Header("Debug")]
    public bool drawVoxelGizmos = false;
    private int[] debugData;
    private SysDebug.Stopwatch stopwatch = new SysDebug.Stopwatch();
    private float timeVoxelize = 0;

    // Start is called before the first frame update
    void Start()
    {
        GetKernelIDs();
        DispatchVoxelize();
        AssingValuesToRenderer();
        if (drawVoxelGizmos)
        {
            DebugReadBackRenderTexture();
        }
    }

    // Update is called once per frame
    void Update()
    {
        if (lastReslolution != resolution)
        {
            DispatchVoxelize();
            AssingValuesToRenderer();
            if (drawVoxelGizmos)
            {
                DebugReadBackRenderTexture();
            }
        }

        lastReslolution = resolution;

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

    private void GetKernelIDs()
    {
        kernelVoxelize = shader.FindKernel("Voxelize");
        kernelVoxelizeChunk = shader.FindKernel("VoxelizeChunk");

        kernelReadBack = shader.FindKernel("ReadBackTexture");

    }

    private void SetMeshRelatedVariables()
    {
        triangleCount = mesh.triangles.Length;
        vertexCount = mesh.vertices.Length;
        boundsMin = mesh.bounds.min;
        boundsMax = mesh.bounds.max;
        voxelSize = Mathf.Max(Mathf.Max(mesh.bounds.size.x, mesh.bounds.size.y), mesh.bounds.size.z) / resolution;
    }

    private void DispatchVoxelize()
    {
        if (mesh == null)
        {
            throw new System.Exception("No Mesh Asigned");
        }


        stopwatch.Start();

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

        if (resolution >= chunkLimit)
        {
            DispatchVoxelizeChunks();
            return;
        }

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


        // Insert a fence and wait for GPU to finish
        GraphicsFence fence = Graphics.CreateGraphicsFence(GraphicsFenceType.AsyncQueueSynchronisation, SynchronisationStageFlags.ComputeProcessing);
        Graphics.WaitOnAsyncGraphicsFence(fence); // CPU blocks here until GPU completes

        stopwatch.Stop();
        timeVoxelize = stopwatch.ElapsedMilliseconds;
        Debug.Log("Time Voxilaze: " + timeVoxelize + "ms");
    }



    private void DispatchVoxelizeChunks()
    {
        // Set buffers once (they don't change per chunk)
        shader.SetBuffer(kernelVoxelizeChunk, "_TriangleIndicesIn", triangleIndicesBuffer);
        shader.SetBuffer(kernelVoxelizeChunk, "_VertexPositionsIn", vertexPositionsBuffer);
        shader.SetTexture(kernelVoxelizeChunk, "_VoxelTexture", voxelTexture);

        // Set constant variables
        shader.SetInt("_TriangleCount", mesh.triangles.Length);
        shader.SetInt("_Resolution", resolution);
        shader.SetFloat("_VoxelSize", voxelSize);
        shader.SetVector("_BoundsMin", boundsMin);
        shader.SetVector("_BoundsMax", boundsMax);

        // Decide chunk size (e.g., 32x32x32) to avoid huge dispatches
        int chunkSize = Mathf.Min(chunkLimit, resolution);
        Vector3Int threadGroupSize = GetThreadGroupSize(kernelVoxelizeChunk);

        // Loop over all chunks
        for (int x = 0; x < resolution; x += chunkSize)
        {
            for (int y = 0; y < resolution; y += chunkSize)
            {
                for (int z = 0; z < resolution; z += chunkSize)
                {
                    // Set the current chunk start and size
                    Vector3Int currentChunkSize = new Vector3Int(
                        Mathf.Min(chunkSize, resolution - x),
                        Mathf.Min(chunkSize, resolution - y),
                        Mathf.Min(chunkSize, resolution - z)
                    );

                    shader.SetInts("_ChunkStart", x, y, z);
                    shader.SetInts("_ChunkSize", currentChunkSize.x, currentChunkSize.y, currentChunkSize.z);

                    // Compute number of thread groups for this chunk
                    Vector3Int threadCount = new Vector3Int(
                        Mathf.CeilToInt((float)currentChunkSize.x / threadGroupSize.x),
                        Mathf.CeilToInt((float)currentChunkSize.y / threadGroupSize.y),
                        Mathf.CeilToInt((float)currentChunkSize.z / threadGroupSize.z)
                    );

                    // Dispatch this chunk
                    shader.Dispatch(kernelVoxelizeChunk, threadCount.x, threadCount.y, threadCount.z);
                }
            }
        }

        // Insert a fence and wait for GPU to finish
        GraphicsFence fence = Graphics.CreateGraphicsFence(GraphicsFenceType.AsyncQueueSynchronisation, SynchronisationStageFlags.ComputeProcessing);
        Graphics.WaitOnAsyncGraphicsFence(fence);

        stopwatch.Stop();
        timeVoxelize = stopwatch.ElapsedMilliseconds;
        Debug.Log("Time Voxelize Chunks: " + timeVoxelize + "ms");
    }



    RenderTexture CreateInt3DTexture(int width, int height, int depth)
    {
        RenderTexture rt = new RenderTexture(width, height, 0);
        rt.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        rt.volumeDepth = depth;
        rt.enableRandomWrite = true;
        rt.wrapMode = TextureWrapMode.Clamp;
        rt.filterMode = FilterMode.Point;
        rt.graphicsFormat = GraphicsFormat.R32_SInt; // <- CRITICAL LINE
        rt.Create();
        return rt;
    }



    private void DebugReadBackRenderTexture()
    {
        int totalVoxels = (int)Mathf.Pow(resolution, 3);
        ComputeBuffer intBuffer = new ComputeBuffer(totalVoxels, sizeof(int));
        shader.SetBuffer(kernelReadBack, "_ReadBackBuffer", intBuffer);
        shader.SetTexture(kernelReadBack, "_VoxelTexture", voxelTexture);

        //Calculate the number of threads dispatched
        Vector3Int threadGroupSize = GetThreadGroupSize(kernelReadBack);
        Vector3Int threadCount = new Vector3Int(Mathf.CeilToInt((float)resolution / threadGroupSize.x), Mathf.CeilToInt((float)resolution / threadGroupSize.y), Mathf.CeilToInt((float)resolution / threadGroupSize.z));


        //Dispatch the shader
        shader.Dispatch(kernelReadBack, threadCount.x, threadCount.y, threadCount.z);

        debugData = new int[totalVoxels];
        intBuffer.GetData(debugData);

        intBuffer.Release();
        intBuffer = null;
    }


    private void AssingValuesToRenderer()
    {
        //Check if texture exists
        if (voxelTexture == null)
        {
            throw new System.Exception("No Voxel Texture");
        }


        //Set the texture
        renderMaterial.SetTexture("_VoxelTexture", voxelTexture);

        //Set the shader Variables
        renderMaterial.SetInt("_Resolution", resolution);
        renderMaterial.SetFloat("_VoxelSize", voxelSize);
        renderMaterial.SetVector("_BoundsMin", boundsMin);
        renderMaterial.SetVector("_BoundsMax", boundsMax);
        renderMaterial.SetTexture("_FaceTexture", faceTexture);
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



    void OnDrawGizmos()
    {
        if (debugData != null && debugData.Length > 0 && drawVoxelGizmos)
        {
            Gizmos.color = Color.white;

            for (int x = 0; x < resolution; x++)
            {
                for (int y = 0; y < resolution; y++)
                {
                    for (int z = 0; z < resolution; z++)
                    {
                        Vector3 center = new Vector3(x * voxelSize, y * voxelSize, z * voxelSize) + new Vector3(voxelSize / 2, voxelSize / 2, voxelSize / 2);
                        if (debugData[(int)(x + y * resolution + z * resolution * resolution)] > 0)
                        {
                            Gizmos.DrawCube(center, new Vector3(voxelSize, voxelSize, voxelSize));
                        }
                    }
                }
            }
        }
    }
}
