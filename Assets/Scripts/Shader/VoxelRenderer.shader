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

            #define AXIS_X 0
            #define AXIS_Y 1
            #define AXIS_Z 2

            #define SOLID 0
            #define POSITION 1
            #define DEPTH 2
            #define FACE 3
            #define UV 4
            #define TEXTURE 5


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
            uint _RenderMode;
            int _AmbientOcclusion;

            TEXTURE2D(_FaceTexture); // Declare the texture
            SAMPLER(sampler_FaceTexture); // Declare the sampler

            struct Ray {
                float3 origin;
                float3 dir;
            };


            struct AABBPoints{
                float3 entryPoint;
                float3 exitPoint;
            };

            struct DDAInfo {
                float3 entryPoint; //Entry point to voxel in worldspace
                float3 exitPoint; //exit point of voxel in worldspace
                float3 stepDirection; //DDA Step direction
                float3 stepSize; //Step size to travel one voxel in that direction
                float3 t_Max;
                int lastStepAxis; //0 -> X, 1 -> y, 2 -> z axis
                int3 voxel;
            };


            struct VoxelHit{
                bool hit;
                uint3 voxel;
                float3 hitPoint;
                float2 hitUV;
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



            //DDA the grid
            bool DDA(inout DDAInfo ddaInfo, Ray ray)
            {
                //DDA the Voxel Grid
                for (uint i = 0; i < _Resolution * 3; ++ i)
                {
                    // Check if voxel is inside grid
                    if (all(ddaInfo.voxel >= 0) && all(ddaInfo.voxel < int(_Resolution)))
                    {
                        if (_VoxelTexture[ddaInfo.voxel].r > 0)
                        {
                            return true;
                        }
                    }
                    else
                    {
                        // Ray has exited the grid bounds
                        return false;
                    }

                    // Step to next voxel
                    // Step to next voxel
                    if (ddaInfo.t_Max.x < ddaInfo.t_Max.y)
                    {
                        if (ddaInfo.t_Max.x < ddaInfo.t_Max.z)
                        {
                            ddaInfo.voxel.x += int(ddaInfo.stepDirection.x);
                            ddaInfo.lastStepAxis = AXIS_X;
                            ddaInfo.entryPoint = ray.origin + ddaInfo.t_Max.x * ray.dir;
                            ddaInfo.t_Max.x += ddaInfo.stepSize.x;
                        }
                        else
                        {
                            ddaInfo.voxel.z += int(ddaInfo.stepDirection.z);
                            ddaInfo.lastStepAxis = AXIS_Z;
                            ddaInfo.entryPoint = ray.origin + ddaInfo.t_Max.z * ray.dir;
                            ddaInfo.t_Max.z += ddaInfo.stepSize.z;
                        }
                    }
                    else
                    {
                        if (ddaInfo.t_Max.y < ddaInfo.t_Max.z)
                        {
                            ddaInfo.voxel.y += int(ddaInfo.stepDirection.y);
                            ddaInfo.lastStepAxis = AXIS_Y;
                            ddaInfo.entryPoint = ray.origin + ddaInfo.t_Max.y * ray.dir;
                            ddaInfo.t_Max.y += ddaInfo.stepSize.y;
                        }
                        else
                        {
                            ddaInfo.voxel.z += int(ddaInfo.stepDirection.z);
                            ddaInfo.lastStepAxis = AXIS_Z;
                            ddaInfo.entryPoint = ray.origin + ddaInfo.t_Max.z * ray.dir;
                            ddaInfo.t_Max.z += ddaInfo.stepSize.z;
                        }
                    }

                    // Compute exit point of current voxel
                    ddaInfo.exitPoint = ddaInfo.entryPoint + ddaInfo.stepDirection * _VoxelSize;
                }

                return false;
            }


            float2 GetHitUV(int3 voxelCoordinate, float3 entryPoint, int hitFace)
            {
                // Voxel min corner in world space
                float3 voxelMin = _BoundsMin + float3(voxelCoordinate) * _VoxelSize;

                // Normalize hit point to voxel - local space [0, 1]
                float3 localPos = (entryPoint - voxelMin) / _VoxelSize;

                float2 uv;

                switch (hitFace)
                {
                    case POS_X : // Looking along + X → YZ plane
                    uv = float2(localPos.z, localPos.y);
                    break;

                    case NEG_X : // Looking along - X → YZ plane
                    uv = float2(1 - localPos.z, localPos.y);
                    break;

                    case POS_Y : // Looking along + Y → XZ plane
                    uv = float2(localPos.x, localPos.z);
                    break;

                    case NEG_Y : // Looking along - Y → XZ plane
                    uv = float2(1 - localPos.x, localPos.z);
                    break;

                    case POS_Z : // Looking along + Z → XY plane
                    uv = float2(1 - localPos.x, localPos.y);
                    break;

                    case NEG_Z : // Looking along - Z → XY plane
                    uv = float2(localPos.x, localPos.y);
                    break;

                    default :
                    uv = float2(0.0, 0.0);
                    break;
                }

                return clamp(uv, 0.0, 1.0);
            }



            //Converts the DDA info into a Hit info
            VoxelHit GetHitInfo(DDAInfo ddaInfo)
            {
                VoxelHit hit;

                hit.hit = true;
                hit.voxel = uint3(ddaInfo.voxel.xyz);
                hit.hitPoint = ddaInfo.entryPoint;
                hit.hitFace = ddaInfo.lastStepAxis + (ddaInfo.stepDirection[ddaInfo.lastStepAxis] >= 0 ? 3 : 0);

                hit.hitUV = GetHitUV(ddaInfo.voxel, ddaInfo.entryPoint, hit.hitFace);

                return hit;
            }


            bool RayMarchVoxel(Ray ray, AABBPoints boundsAABBPoints, out VoxelHit hit)
            {
                // Step direction and step size along each axis
                float3 stepDirection = sign(ray.dir);
                float3 stepSize = abs(_VoxelSize / ray.dir);

                //Voxel index of the entry voxel
                int3 voxel = int3(clamp(floor((boundsAABBPoints.entryPoint - _BoundsMin) / _VoxelSize), 0, _Resolution - 1));

                // Voxel bounds
                float3 voxelMin = _BoundsMin + float3(voxel) * _VoxelSize;
                float3 voxelMax = voxelMin + _VoxelSize;

                // -- - FIX : Correct exit point of the first voxel -- -
                float3 invDir = 1.0 / ray.dir;
                float3 t1 = (voxelMin - ray.origin) * invDir;
                float3 t2 = (voxelMax - ray.origin) * invDir;
                float tNear = max(max(min(t1.x, t2.x), min(t1.y, t2.y)), min(t1.z, t2.z));
                float tFar = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z));
                boundsAABBPoints.exitPoint = ray.origin + tFar * ray.dir;

                // Compute tMax for DDA
                float3 tMax;
                for(int i = 0; i < 3; i ++)
                tMax[i] = stepDirection[i] > 0 ? (voxelMax[i] - ray.origin[i]) / ray.dir[i] : (voxelMin[i] - ray.origin[i]) / ray.dir[i];

                //Compute the entry axis for the first voxel
                int lastStepAxis = GetEntryAxis(ray);



                DDAInfo ddaInfo;
                ddaInfo.entryPoint = boundsAABBPoints.entryPoint;
                ddaInfo.exitPoint = boundsAABBPoints.exitPoint;
                ddaInfo.stepDirection = stepDirection;
                ddaInfo.stepSize = stepSize;
                ddaInfo.t_Max = tMax;
                ddaInfo.lastStepAxis = lastStepAxis;
                ddaInfo.voxel = voxel;


                //Make the DDA Ray traversal
                if(DDA(ddaInfo, ray))
                {
                    hit = GetHitInfo(ddaInfo);
                    return true;
                }
                hit = (VoxelHit)0;
                return false;
            }


            //Calculates the depth of a hit inside the bounding box of the voxel grid
            float GetHitDepth(VoxelHit hit, AABBPoints boundsAABBPoints)
            {
                float totalDistance = distance(boundsAABBPoints.entryPoint, boundsAABBPoints.exitPoint);
                float hitDistance = distance(boundsAABBPoints.entryPoint, hit.hitPoint);

                //Normalize to 0 - 1
                return 1.0 - saturate(hitDistance / totalDistance);
            }

            //Calculates how much of effect the ambient occlusion has
            float GetAmbientOcclusion(VoxelHit hit)
            {
                int3 voxel = hit.voxel;
                int3 voxelsToCheck[4];

                switch(hit.hitFace)
                {
                    case POS_X :

                    voxelsToCheck[0] = int3(voxel.x + 1, voxel.y + 1, voxel.z);
                    voxelsToCheck[1] = int3(voxel.x + 1, voxel.y - 1, voxel.z);
                    voxelsToCheck[2] = int3(voxel.x + 1, voxel.y, voxel.z + 1);
                    voxelsToCheck[3] = int3(voxel.x + 1, voxel.y, voxel.z - 1);
                    break;

                    case NEG_X :
                    voxelsToCheck[0] = int3(voxel.x - 1, voxel.y + 1, voxel.z);
                    voxelsToCheck[1] = int3(voxel.x - 1, voxel.y - 1, voxel.z);
                    voxelsToCheck[2] = int3(voxel.x - 1, voxel.y, voxel.z + 1);
                    voxelsToCheck[3] = int3(voxel.x - 1, voxel.y, voxel.z - 1);
                    break;

                    case POS_Y :
                    voxelsToCheck[0] = int3(voxel.x + 1, voxel.y + 1, voxel.z);
                    voxelsToCheck[1] = int3(voxel.x - 1, voxel.y + 1, voxel.z);
                    voxelsToCheck[2] = int3(voxel.x, voxel.y + 1, voxel.z + 1);
                    voxelsToCheck[3] = int3(voxel.x, voxel.y + 1, voxel.z - 1);
                    break;

                    case NEG_Y :
                    voxelsToCheck[0] = int3(voxel.x + 1, voxel.y - 1, voxel.z);
                    voxelsToCheck[1] = int3(voxel.x - 1, voxel.y - 1, voxel.z);
                    voxelsToCheck[2] = int3(voxel.x, voxel.y - 1, voxel.z + 1);
                    voxelsToCheck[3] = int3(voxel.x, voxel.y - 1, voxel.z - 1);
                    break;


                    case POS_Z :
                    voxelsToCheck[0] = int3(voxel.x + 1, voxel.y, voxel.z + 1);
                    voxelsToCheck[1] = int3(voxel.x - 1, voxel.y, voxel.z + 1);
                    voxelsToCheck[2] = int3(voxel.x, voxel.y + 1, voxel.z + 1);
                    voxelsToCheck[3] = int3(voxel.x, voxel.y - 1, voxel.z + 1);
                    break;

                    case NEG_Z :
                    voxelsToCheck[0] = int3(voxel.x + 1, voxel.y, voxel.z - 1);
                    voxelsToCheck[1] = int3(voxel.x - 1, voxel.y, voxel.z - 1);
                    voxelsToCheck[2] = int3(voxel.x, voxel.y + 1, voxel.z - 1);
                    voxelsToCheck[3] = int3(voxel.x, voxel.y - 1, voxel.z - 1);
                    break;
                }

                float distanceToEdge[4];

                // Convert the world - space hit point to local normalized voxel coordinates
                float3 voxelMin = _BoundsMin + float3(voxel) * _VoxelSize;
                float3 localPos = (hit.hitPoint - voxelMin) / _VoxelSize;

                // Calculate the normalized distance to the edge for each neighbor
                switch(hit.hitFace)
                {
                    case POS_X : // YZ plane
                    distanceToEdge[0] = 1.0 - localPos.y; // Distance to top edge
                    distanceToEdge[1] = localPos.y; // Distance to bottom edge
                    distanceToEdge[2] = 1.0 - localPos.z; // Distance to front edge
                    distanceToEdge[3] = localPos.z; // Distance to back edge
                    break;

                    case NEG_X : // YZ plane
                    distanceToEdge[0] = 1.0 - localPos.y; // Distance to top edge
                    distanceToEdge[1] = localPos.y; // Distance to bottom edge
                    distanceToEdge[2] = 1.0 - localPos.z; // Distance to front edge
                    distanceToEdge[3] = localPos.z; // Distance to back edge
                    break;

                    case POS_Y : // XZ plane
                    distanceToEdge[0] = 1.0 - localPos.x; // Distance to right edge
                    distanceToEdge[1] = localPos.x; // Distance to left edge
                    distanceToEdge[2] = 1.0 - localPos.z; // Distance to front edge
                    distanceToEdge[3] = localPos.z; // Distance to back edge
                    break;

                    case NEG_Y : // XZ plane
                    distanceToEdge[0] = 1.0 - localPos.x; // Distance to right edge
                    distanceToEdge[1] = localPos.x; // Distance to left edge
                    distanceToEdge[2] = 1.0 - localPos.z; // Distance to front edge
                    distanceToEdge[3] = localPos.z; // Distance to back edge
                    break;

                    case POS_Z : // XY plane
                    distanceToEdge[0] = 1.0 - localPos.x; // Distance to right edge
                    distanceToEdge[1] = localPos.x; // Distance to left edge
                    distanceToEdge[2] = 1.0 - localPos.y; // Distance to top edge
                    distanceToEdge[3] = localPos.y; // Distance to bottom edge
                    break;

                    case NEG_Z : // XY plane
                    distanceToEdge[0] = 1.0 - localPos.x; // Distance to right edge
                    distanceToEdge[1] = localPos.x; // Distance to left edge
                    distanceToEdge[2] = 1.0 - localPos.y; // Distance to top edge
                    distanceToEdge[3] = localPos.y; // Distance to bottom edge
                    break;
                }


                float occlusion = 0;

                for(int i = 0; i < 4; i ++)
                {
                    if (all(voxelsToCheck[i] >= 0) && all(voxelsToCheck[i] < int(_Resolution)))
                    {
                        // Check if the neighbor voxel exists
                        if (_VoxelTexture[voxelsToCheck[i]].r > 0)
                        {
                            float effect = 0;
                            // The effective occlusion distance is one quarter of the voxel's size
                            float occlusionDistance = _VoxelSize * 0.4;

                            // Check if the point is within the occlusion distance from the edge
                            if (distanceToEdge[i] * _VoxelSize <= occlusionDistance)
                            {
                                // Invert the normalized distance to create a fade from the edge
                                effect = 1.0 - (distanceToEdge[i] * _VoxelSize) / occlusionDistance;
                            }

                            //Multiply effect by 0.5 because only two voxels can add to the occlusion at the same time
                            occlusion += effect * 0.5;
                        }
                    }
                }
                return 1 - occlusion;
            }



            float4 RenderColor(VoxelHit hit, AABBPoints boundsAABBPoints)
            {
                float4 color = (0, 0, 0, 1);

                switch (_RenderMode)
                {
                    case SOLID :
                    color = (1, 1, 1, 1);
                    break;

                    case POSITION :
                    color = float4((float3(hit.voxel.xyz) / _Resolution).xyz, 1);
                    break;

                    case DEPTH :
                    float depth = GetHitDepth(hit, boundsAABBPoints);
                    color = float4(depth, depth, depth, 1);
                    break;

                    case FACE :
                    switch(hit.hitFace)
                    {
                        case POS_X :
                        color = float4(1, 0, 0, 1);
                        break;
                        case POS_Y :
                        color = float4(0, 1, 0, 1);
                        break;
                        case POS_Z :
                        color = float4(0, 0, 1, 1);
                        break;
                        case NEG_X :
                        color = float4(1, 1, 0, 1);
                        break;
                        case NEG_Y :
                        color = float4(0, 1, 1, 1);
                        break;
                        case NEG_Z :
                        color = float4(1, 0, 1, 1);
                        break;
                        default :
                        color = float4(0, 0, 0, 1);
                        break;
                    }
                    break;

                    case UV :
                    color = float4(hit.hitUV.rg, 0, 1);
                    break;

                    case TEXTURE :
                    float3 textureColor;
                    switch(hit.hitFace)
                    {
                        case POS_X :
                        textureColor = SAMPLE_TEXTURE2D(_FaceTexture, sampler_FaceTexture, hit.hitUV).rgb;
                        color = float4(textureColor.rgb, 1.0);
                        break;
                        case POS_Y :
                        textureColor = SAMPLE_TEXTURE2D(_FaceTexture, sampler_FaceTexture, hit.hitUV).rgb;
                        color = float4(textureColor.rgb, 1.0);
                        break;
                        case POS_Z :
                        textureColor = SAMPLE_TEXTURE2D(_FaceTexture, sampler_FaceTexture, hit.hitUV).rgb;
                        color = float4(textureColor.rgb, 1.0);
                        break;
                        case NEG_X :
                        textureColor = SAMPLE_TEXTURE2D(_FaceTexture, sampler_FaceTexture, hit.hitUV).rgb;
                        color = float4(textureColor.rgb, 1.0);
                        break;
                        case NEG_Y :
                        textureColor = SAMPLE_TEXTURE2D(_FaceTexture, sampler_FaceTexture, hit.hitUV).rgb;
                        color = float4(textureColor.rgb, 1.0);
                        break;
                        case NEG_Z :
                        textureColor = SAMPLE_TEXTURE2D(_FaceTexture, sampler_FaceTexture, hit.hitUV).rgb;
                        color = float4(textureColor.rgb, 1.0);
                        break;
                        default :
                        color = float4(0, 0, 0, 1);
                        break;
                    }
                    break;

                    default :
                    color = float4(0, 0, 0, 1);
                    break;
                }

                if(_AmbientOcclusion > 0 && _RenderMode != DEPTH)
                {
                    float occlusion = GetAmbientOcclusion(hit);
                    color = color - ((1 - float4(occlusion, occlusion, occlusion, 0)) * .7);
                }

                return color;
            }




            half4 frag(Varyings IN) : SV_Target
            {
                float depth = SampleSceneDepth(IN.texcoord);
                float3 worldPos = ComputeWorldSpacePosition(IN.texcoord, depth, UNITY_MATRIX_I_VP);

                Ray ray;
                ray.origin = _WorldSpaceCameraPos;
                ray.dir = normalize(worldPos - _WorldSpaceCameraPos);



                AABBPoints boundsAABBPoints;
                if(! AABBGrid(_BoundsMin, _BoundsMax, ray, boundsAABBPoints))
                {
                    //Ray misses Bounding Boxes
                    return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, IN.texcoord);
                }

                //Raymarch through voxel grid
                VoxelHit hit;
                if (RayMarchVoxel(ray, boundsAABBPoints, hit))
                {
                    //Retunrs a color based on the render Mode
                    return RenderColor(hit, boundsAABBPoints);
                }
                //Return scene color when ray does not hit a voxel
                else
                {
                    return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, IN.texcoord);
                }
            }

            ENDHLSL
        }

    }
}
