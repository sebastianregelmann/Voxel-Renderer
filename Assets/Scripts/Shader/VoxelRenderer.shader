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


            struct AABBPoints{
                float3 entryPoint;
                float3 exitPoint;
            };

            struct VoxelHit{
                bool hit;
                uint3 voxelCoordinate;
                float3 hitPoint;
                float depth;
                int hitFace;
            };


            //Calculates the AABB intersection points with a grid
            bool AABBGrid(float3 boundsMin, float3 boundsMax, Ray ray, out AABBPoints aabbPoints)
            {
                // Compute intersection distances (t values) with the bounding box on each axis
                float3 invDir = 1.0 / ray.dir;

                float3 tMin = (boundsMin - ray.origin) * invDir;
                float3 tMax = (boundsMax - ray.origin) * invDir;

                // Ensure tMin is the near side and tMax is the far side per axis
                float3 t1 = min(tMin, tMax);
                float3 t2 = max(tMin, tMax);

                // Find largest entry time and smallest exit time
                float tNear = max(max(t1.x, t1.y), t1.z);
                float tFar = min(min(t2.x, t2.y), t2.z);

                // Check for miss : ray doesn't intersect or intersection is behind the origin
                if (tNear > tFar || tFar < 0)
                {
                    return false;
                }

                // Clamp tNear to 0 to ensure we're not going behind the ray
                float clampedNear = max(tNear, 0.0);

                // Compute the actual entry and exit points
                aabbPoints.entryPoint = ray.origin + clampedNear * ray.dir;
                aabbPoints.exitPoint = ray.origin + tFar * ray.dir;

                //Clamp values to always be in the grid
                aabbPoints.entryPoint = clamp(aabbPoints.entryPoint, boundsMin, boundsMax);
                aabbPoints.exitPoint = clamp(aabbPoints.exitPoint, boundsMin, boundsMax);


                return true;
            }


            AABBPoints NextVoxelAABBPoints(AABBPoints currentVoxelPoints, float3 stepDirection, float3 stepSize, int3 currentVoxel, out int3 nextVoxel)
            {
                AABBPoints nextPoints;
                nextVoxel = currentVoxel;

                // Set entry point to the current exit point
                nextPoints.entryPoint = currentVoxelPoints.exitPoint;
                nextPoints.exitPoint = currentVoxelPoints.exitPoint;

                if (currentVoxelPoints.exitPoint.x < currentVoxelPoints.exitPoint.y)
                {
                    if (currentVoxelPoints.exitPoint.x < currentVoxelPoints.exitPoint.z)
                    {
                        nextVoxel.x += int(stepDirection.x); // Move to next voxel along X
                        nextPoints.exitPoint.x += stepSize.x; // Update exit distance for X
                    }
                    else
                    {
                        nextVoxel.z += int(stepDirection.z); // Move to next voxel along Z
                        nextPoints.exitPoint.z += stepSize.z;
                    }
                }
                else
                {
                    if (currentVoxelPoints.exitPoint.y < currentVoxelPoints.exitPoint.z)
                    {
                        nextVoxel.y += int(stepDirection.y); // Move to next voxel along Y
                        nextPoints.exitPoint.y += stepSize.y;
                    }
                    else
                    {
                        nextVoxel.z += int(stepDirection.z); // Move to next voxel along Z
                        nextPoints.exitPoint.z += stepSize.z;
                    }
                }

                return nextPoints;
            }



            bool RayMarchVoxel(Ray ray, out uint3 voxelCoord)
            {
                AABBPoints aabbPoints;

                // Early out if the ray doesn't intersect the voxel grid bounds
                if (! AABBGrid(_BoundsMin, _BoundsMax, ray, aabbPoints))
                return false;

                // Compute step direction (+ 1 or - 1 for each axis)
                float3 stepDirection = sign(ray.dir);

                // Distance required to cross one voxel along each axis
                float3 stepSize = abs(_VoxelSize / ray.dir);

                // Starting voxel index from entry point
                int3 voxel = int3(clamp(floor((aabbPoints.entryPoint - _BoundsMin) / _VoxelSize), 0, _Resolution - 1));

                // Compute the exit point of the first voxel by intersecting voxel boundaries
                float3 voxelBoundary = _BoundsMin + (float3(voxel) + stepDirection) * _VoxelSize;
                float3 tMaxNext = (voxelBoundary - ray.origin) / ray.dir;

                // Use tMaxNext to build the initial AABBPoints.exitPoint
                aabbPoints.exitPoint = tMaxNext;

                // Start ray marching
                for (uint i = 0; i < _Resolution * 3; ++ i)
                {
                    // Bounds check
                    if (all(voxel >= 0) && all(voxel < int(_Resolution)))
                    {
                        if (_VoxelTexture[voxel].r > 0)
                        {
                            voxelCoord = uint3(voxel);
                            return true;
                        }
                    }
                    else
                    {
                        break; // Exit if outside grid
                    }

                    // Step to next voxel using your helper
                    aabbPoints = NextVoxelAABBPoints(aabbPoints, stepDirection, stepSize, voxel, voxel);
                }

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
