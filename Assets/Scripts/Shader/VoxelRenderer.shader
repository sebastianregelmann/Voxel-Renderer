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

            #define POS_X 0
            #define POS_Y 1
            #define POS_Z 2
            #define NEG_X 3
            #define NEG_Y 4
            #define NEG_Z 5


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


            int GetEntryAxis(Ray ray)
            {
                float3 invDir = 1.0 / ray.dir;
                float3 tMin = (_BoundsMin - ray.origin) * invDir;
                float3 tMaxGrid = (_BoundsMax - ray.origin) * invDir;
                float3 t1 = min(tMin, tMaxGrid);
                float tNear = max(max(t1.x, t1.y), t1.z);

                if (tNear == t1.x) {
                    return 0;
                } else if (tNear == t1.y) {
                    return 1;
                } else {
                    return 2;
                }
            }

            float2 GetHitUV(int3 voxelCoordinate, float3 entryPoint, int hitFace)
            {
                // Voxel min corner
                float3 voxelMin = _BoundsMin + float3(voxelCoordinate) * _VoxelSize;

                float3 localPos = (entryPoint - voxelMin) / _VoxelSize; // normalized to 0..1 within voxel

                float2 uv;

                switch(hitFace)
                {
                    case POS_X : // + X face → YZ plane
                    uv = localPos.yz;
                    break;
                    case NEG_X : // - X face → YZ plane
                    uv = float2(localPos.y, 1.0 - localPos.z); // flip V
                    break;
                    case POS_Y : // + Y face → XZ plane
                    uv = float2(localPos.x, localPos.z);
                    break;
                    case NEG_Y : // - Y face → XZ plane
                    uv = float2(1.0 - localPos.x, localPos.z); // flip U
                    break;
                    case POS_Z : // + Z face → XY plane
                    uv = localPos.xy;
                    break;
                    case NEG_Z : // - Z face → XY plane
                    uv = float2(1.0 - localPos.x, localPos.y); // flip U
                    break;
                    default :
                    uv = float2(0, 0);
                    break;
                }

                return clamp(uv, 0.0, 1.0);
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
                int direction = stepDirection[lastStepAxis];
                hit.hitFace = lastStepAxis + (direction < 0 ? 3 : 0);



                // UV calculation for the face
                hit.hitUV = GetHitUV(voxelCoordinate, aabbPoints.entryPoint, hit.hitFace);
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


                // Voxel bounds
                float3 voxelMin = _BoundsMin + float3(voxel) * _VoxelSize;
                float3 voxelMax = voxelMin + _VoxelSize;

                // -- - FIX : Correct exit point of the first voxel -- -
                float3 invDir = 1.0 / ray.dir;
                float3 t1 = (voxelMin - ray.origin) * invDir;
                float3 t2 = (voxelMax - ray.origin) * invDir;
                float tNear = max(max(min(t1.x, t2.x), min(t1.y, t2.y)), min(t1.z, t2.z));
                float tFar = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z));
                aabbPoints.exitPoint = ray.origin + tFar * ray.dir;

                // Compute tMax for DDA
                float3 tMax;
                for(int i = 0; i < 3; i ++)
                tMax[i] = stepDirection[i] > 0 ? (voxelMax[i] - ray.origin[i]) / ray.dir[i] : (voxelMin[i] - ray.origin[i]) / ray.dir[i];

                int lastStepAxis = GetEntryAxis(ray);

                // float3 voxelMin = _BoundsMin + float3(voxel) * _VoxelSize;
                // float3 voxelMax = voxelMin + _VoxelSize;
                // AABBGrid(voxelMin, voxelMax, ray, aabbPoints);

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

                   // return float4((float3(pos.xyz) / _Resolution).xyz, 1);

                    // if(all(pos.xyz) == 0 || all(pos.xyz) >= _Resolution - 1)
                    // {
                        // return float4(0, 0, 0, 1);
                    // }

                    //return float4(hit.hitUV.rg, 0, 1);
                    //Rendering Method
                    switch(hit.hitFace)
                    {
                        case POS_X :
                        return float4(1, 0, 0, 1);
                        case POS_Y :
                        return float4(0, 1, 0, 1);
                        case POS_Z :
                        return float4(0, 0, 1, 1);
                        case NEG_X :
                        return float4(1, 1, 0, 1);
                        case NEG_Y :
                        return float4(0, 1, 1, 1);
                        case NEG_Z :
                        return float4(1, 0, 1, 1);
                        default :
                        return float4(0, 0, 0, 1);
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
