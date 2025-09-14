Shader "Custom/VoxelRenderer_Optimized"
{
    Properties
    {
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            Texture3D<int> _VoxelTexture;
            uint _Resolution;
            float _VoxelSize;
            float3 _BoundsMin;
            float3 _BoundsMax;

            struct Ray {
                float3 origin;
                float3 dir;
            };

            // Ray Marching / 3D DDA algorithm to traverse the voxel grid along a ray
            // Returns true if the ray hits a solid voxel, and outputs the voxel coordinate
            bool RayMarchVoxel(Ray ray, out uint3 voxelCoord)
            {
                // Compute intersection times with the voxel grid bounds along each axis
                float3 tMin = (_BoundsMin - ray.origin) / ray.dir; // distance to min bound per axis
                float3 tMax = (_BoundsMax - ray.origin) / ray.dir; // distance to max bound per axis

                // Ensure t1 is the near intersection, t2 is the far intersection per axis
                float3 t1 = min(tMin, tMax);
                float3 t2 = max(tMin, tMax);

                // tNear = largest entry time, tFar = smallest exit time
                float tNear = max(max(t1.x, t1.y), t1.z);
                float tFar = min(min(t2.x, t2.y), t2.z);

                // If ray misses the bounds, return false
                if (tNear > tFar || tFar < 0) return false;

                // Compute starting position inside the voxel grid
                float3 pos = ray.origin + max(tNear, 0) * ray.dir;

                // Convert world position to voxel indices (int3)
                int3 voxel = int3(clamp(floor((pos - _BoundsMin) / _VoxelSize), 0, _Resolution - 1));

                // Step direction along each axis : + 1 if ray moves positive, - 1 if negative
                float3 step = sign(ray.dir);

                // Distance along ray to cross one voxel along each axis
                float3 tDelta = abs(_VoxelSize / ray.dir);

                // Compute next voxel boundary along each axis
                float3 voxelBorder = _BoundsMin + (voxel + step) * _VoxelSize;
                float3 tMaxNext = (voxelBorder - ray.origin) / ray.dir;

                // Loop through voxels along the ray
                // Safety limit : max 3 * _Resolution steps (for non - cubic grids, adjust as needed)
                for (uint i = 0; i < _Resolution * 3; ++ i)
                {
                    // Check if current voxel is solid
                    if (_VoxelTexture[voxel].r > 0)
                    {
                        voxelCoord = uint3(voxel);
                        return true; // Hit a solid voxel
                    }

                    // Determine which axis the ray exits next
                    if (tMaxNext.x < tMaxNext.y)
                    {
                        if (tMaxNext.x < tMaxNext.z)
                        {
                            voxel.x += int(step.x); // Move to next voxel along X
                            tMaxNext.x += tDelta.x; // Update exit distance for X
                        }
                        else
                        {
                            voxel.z += int(step.z); // Move to next voxel along Z
                            tMaxNext.z += tDelta.z;
                        }
                    }
                    else
                    {
                        if (tMaxNext.y < tMaxNext.z)
                        {
                            voxel.y += int(step.y); // Move to next voxel along Y
                            tMaxNext.y += tDelta.y;
                        }
                        else
                        {
                            voxel.z += int(step.z); // Move to next voxel along Z
                            tMaxNext.z += tDelta.z;
                        }
                    }

                    // Stop if voxel is out of bounds
                    if (voxel.x < 0 || voxel.y < 0 || voxel.z < 0 ||
                    voxel.x >= _Resolution || voxel.y >= _Resolution || voxel.z >= _Resolution)
                    break;
                }

                // Ray exited the voxel grid without hitting a solid voxel
                return false;
            }


            half4 frag(Varyings IN) : SV_Target
            {
                float depth = SampleSceneDepth(IN.texcoord);
                float3 worldPos = ComputeWorldSpacePosition(IN.texcoord, depth, UNITY_MATRIX_I_VP);

                Ray ray;
                ray.origin = _WorldSpaceCameraPos;
                ray.dir = normalize(worldPos - _WorldSpaceCameraPos);

                uint3 voxelCoord;
                if (RayMarchVoxel(ray, voxelCoord))
                {
                    return float4(1, 1, 1, 1); // Hit voxel
                }
                else
                {
                    return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, IN.texcoord);
                }
            }

            ENDHLSL
        }

    }
}
