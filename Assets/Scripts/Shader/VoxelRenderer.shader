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
                float2 hitUV;
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


            AABBPoints NextVoxelAABBPoints(AABBPoints currentVoxelPoints, float3 stepDirection, float3 stepSize, int3 currentVoxel, out int3 nextVoxel, out int lastStepAxis)
            {
                AABBPoints nextPoints;
                nextVoxel = currentVoxel;
                nextPoints.entryPoint = currentVoxelPoints.exitPoint;
                nextPoints.exitPoint = currentVoxelPoints.exitPoint;

                if (currentVoxelPoints.exitPoint.x < currentVoxelPoints.exitPoint.y)
                {
                    if (currentVoxelPoints.exitPoint.x < currentVoxelPoints.exitPoint.z)
                    {
                        nextVoxel.x += int(stepDirection.x);
                        nextPoints.exitPoint.x += stepSize.x;
                        lastStepAxis = 0;
                    }
                    else
                    {
                        nextVoxel.z += int(stepDirection.z);
                        nextPoints.exitPoint.z += stepSize.z;
                        lastStepAxis = 2;
                    }
                }
                else
                {
                    if (currentVoxelPoints.exitPoint.y < currentVoxelPoints.exitPoint.z)
                    {
                        nextVoxel.y += int(stepDirection.y);
                        nextPoints.exitPoint.y += stepSize.y;
                        lastStepAxis = 1;
                    }
                    else
                    {
                        nextVoxel.z += int(stepDirection.z);
                        nextPoints.exitPoint.z += stepSize.z;
                        lastStepAxis = 2;
                    }
                }
                return nextPoints;
            }



            VoxelHit GetVoxelHit(int3 voxelCoordinate, AABBPoints aabbPoints, int lastStepAxis, float3 stepDirection)
            {
                // Calculate the voxel's world bounds
                float3 voxelMin = _BoundsMin + float3(voxelCoordinate) * _VoxelSize;
                float3 voxelMax = voxelMin + _VoxelSize;

                VoxelHit hit;
                hit.hit = true;
                hit.voxelCoordinate = uint3(voxelCoordinate);
                hit.hitPoint = aabbPoints.entryPoint;
                hit.depth = 1.0;

                // Determine the hit face based on the last axis stepped
                // 0 = - X, 1 = + X, 2 = - Y, 3 = + Y, 4 = - Z, 5 = + Z
                hit.hitFace = lastStepAxis * 2 + (stepDirection[lastStepAxis] > 0 ? 1 : 0);

                // UV calculation for the face
                float2 uv;
                float3 p = aabbPoints.entryPoint;

                switch(hit.hitFace)
                {
                    case 0 : case 1 : // X faces → YZ plane
                    uv = (p.yz - voxelMin.yz) / _VoxelSize;
                    break;
                    case 2 : case 3 : // Y faces → XZ plane
                    uv = (p.xz - voxelMin.xz) / _VoxelSize;
                    break;
                    case 4 : case 5 : // Z faces → XY plane
                    uv = (p.xy - voxelMin.xy) / _VoxelSize;
                    break;
                    default :
                    uv = float2(0.0, 0.0);
                    break;
                }

                hit.hitUV = uv;
                return hit;
            }





            bool RayMarchVoxel(Ray ray, out VoxelHit hit)
            {
                AABBPoints aabbPoints;

                // Early out if the ray doesn't intersect the voxel grid
                if (! AABBGrid(_BoundsMin, _BoundsMax, ray, aabbPoints))
                return false;

                // Step direction along each axis
                float3 stepDirection = sign(ray.dir);
                float3 stepSize = abs(_VoxelSize / ray.dir);

                // Starting voxel index from entry point
                int3 voxel = int3(clamp(floor((aabbPoints.entryPoint - _BoundsMin) / _VoxelSize), 0, _Resolution - 1));

                // Compute exit points along each axis for first voxel
                float3 voxelBoundary = _BoundsMin + (float3(voxel) + stepDirection) * _VoxelSize;
                float3 tMaxNext = (voxelBoundary - ray.origin) / ray.dir;
                aabbPoints.exitPoint = tMaxNext;

                // Determine initial lastStepAxis based on which axis the ray hits first
                float3 tEntry = (voxelBoundary - ray.origin) / ray.dir;
                int lastStepAxis;
                if (tEntry.x < tEntry.y && tEntry.x < tEntry.z)
                {
                    lastStepAxis = 0; // X
                }
                else if (tEntry.y < tEntry.z)
                {
                    lastStepAxis = 1; // Y
                }
                else
                {
                    lastStepAxis = 2;
                }
                // Ray march loop
                for (uint i = 0; i < _Resolution * 3; ++ i)
                {
                    // Check if voxel is inside grid
                    if (all(voxel >= 0) && all(voxel < int(_Resolution)))
                    {
                        if (_VoxelTexture[voxel].r > 0)
                        {
                            hit = GetVoxelHit(voxel, aabbPoints, lastStepAxis, stepDirection);
                            return true;
                        }
                    }
                    else
                    {
                        break;
                    }

                    // Step to next voxel
                    aabbPoints = NextVoxelAABBPoints(aabbPoints, stepDirection, stepSize, voxel, voxel, lastStepAxis);
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

                VoxelHit hit;
                if (RayMarchVoxel(ray, hit))
                {
                   // return float4(hit.hitUV.rg, 0, 1);
                    //Rendering Method
                    switch(hit.hitFace)
                    {
                        case 0 :
                        return float4(1, 0.5, 0, 1);
                        case 1 :
                        return float4(1, 0, 0, 1);
                        case 2 :
                        return float4(0, 1, 0.5, 1);
                        case 3 :
                        return float4(0, 1, 0, 1);
                        case 4 :
                        return float4(0.5, 0, 1, 1);
                        case 5 :
                        return float4(0, 0, 1, 1);
                        default :
                        return float4(0.3, .3, .3, 1);
                    }


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
