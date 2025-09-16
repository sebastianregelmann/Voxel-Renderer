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


            AABBPoints NextVoxelAABBPoints(AABBPoints currentPoints, Ray ray, inout float3 tMax, float3 stepSize, inout int3 currentVoxel, float3 stepDirection, out int lastStepAxis)
            {
                AABBPoints nextPoints;

                // Find the smallest tMax component → that's the axis we're stepping
                if (tMax.x < tMax.y)
                {
                    if (tMax.x < tMax.z)
                    {
                        // Step in X
                        currentVoxel.x += int(stepDirection.x);
                        nextPoints.exitPoint = ray.origin + tMax.x * ray.dir;
                        tMax.x += stepSize.x;
                        lastStepAxis = 0;
                    }
                    else
                    {
                        // Step in Z
                        currentVoxel.z += int(stepDirection.z);
                        nextPoints.exitPoint = ray.origin + tMax.z * ray.dir;
                        tMax.z += stepSize.z;
                        lastStepAxis = 2;
                    }
                }
                else
                {
                    if (tMax.y < tMax.z)
                    {
                        // Step in Y
                        currentVoxel.y += int(stepDirection.y);
                        nextPoints.exitPoint = ray.origin + tMax.y * ray.dir;
                        tMax.y += stepSize.y;
                        lastStepAxis = 1;
                    }
                    else
                    {
                        // Step in Z
                        currentVoxel.z += int(stepDirection.z);
                        nextPoints.exitPoint = ray.origin + tMax.z * ray.dir;
                        tMax.z += stepSize.z;
                        lastStepAxis = 2;
                    }
                }

                // New entry point is old exit point
                nextPoints.entryPoint = currentPoints.exitPoint;

                return nextPoints;
            }


            int GetEntryAxis(int3 voxel, AABBPoints aabbPoints, float3 rayDir)
            {
                float epsilon = 0.0001;

                float3 backstep = aabbPoints.entryPoint - rayDir * epsilon;
                int3 prevVoxel = int3(floor((backstep - _BoundsMin) / _VoxelSize));
                prevVoxel = clamp(prevVoxel, 0, int(_Resolution) - 1);

                int3 delta = voxel - prevVoxel;

                if (abs(delta.x) != 0) return 0;
                if (abs(delta.y) != 0) return 1;
                if (abs(delta.z) != 0) return 2;

                // If still nothing changed, default to something (probably error)
                return 0;
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
                {
                    hit = (VoxelHit)0; // Initialize hit to avoid compiler errors
                    return false;
                }

                // Step direction along each axis
                float3 stepDirection = sign(ray.dir);
                float3 stepSize = abs(_VoxelSize / ray.dir);

                int3 voxel = int3(clamp(floor((aabbPoints.entryPoint - _BoundsMin) / _VoxelSize), 0, _Resolution - 1));


                float3 voxelBoundary = _BoundsMin + (float3(voxel) + stepDirection * 0.5 + 0.5) * _VoxelSize;
                float3 tMax = (voxelBoundary - ray.origin) / ray.dir;


                // Determine initial lastStepAxis based on which axis the ray hits first
                int lastStepAxis = GetEntryAxis(voxel, aabbPoints, ray.dir);

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
                        // Ray has exited the grid bounds
                        break;
                    }

                    // Step to next voxel
                    aabbPoints = NextVoxelAABBPoints(aabbPoints, ray, tMax, stepSize, voxel, stepDirection, lastStepAxis);
                }


                hit = (VoxelHit)0; // Initialize hit to avoid compiler errors
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

                    uint3 pos = hit.voxelCoordinate;

                    //return float4((float3(pos.xyz) / _Resolution).xyz, 1);

                    if(all(pos.xyz) == 0 || all(pos.xyz) >= _Resolution - 1)
                    {
                        return float4(0, 0, 0, 1);
                    }

                    //return float4(hit.hitUV.rg, 0, 1);
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
