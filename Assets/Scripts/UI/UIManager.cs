using System;
using System.Collections;
using System.Collections.Generic;
using TMPro;
using UnityEditor;
using UnityEngine;
using UnityEngine.UI;
public class UIManager : MonoBehaviour
{
    [Header("UI-Objects with ui elements")]
    public GameObject meshSelectionPanel;
    public GameObject voxelizeMethodPanel;
    public GameObject resolutionPanel;
    public GameObject renderModePanel;
    public GameObject textureSelectionPanel;
    public GameObject ambientOcclusionParentPanel;
    public GameObject ambientOcclusionPanel;


    //Compents of the UI to read back values
    private TMP_Dropdown meshSelection;
    private TMP_Dropdown voxelizeMethodSelection;
    private TMP_InputField resolutionInput;
    private TMP_Dropdown renderModeSelection;
    private TMP_Dropdown textureSelection;
    private Toggle ambientOcclusionToggle;


    [Header("Assigns to Choose From")]
    public Mesh[] meshes;
    public Texture2D[] testTexture;
    public Texture2D[] blockTexture;
    public Shadermanager shadermanager;


    //Internal variables to keep track of selected values
    private RENDER_MODE renderMode;
    private VOXELMETHOD voxelMehtod;
    private Mesh mesh;
    private int resolution;
    private Texture[] textures;
    private bool ambientOcclusion;


    // Start is called before the first frame update
    void Start()
    {
        //Get Gameobject components
        meshSelection = meshSelectionPanel.GetComponent<TMP_Dropdown>();
        voxelizeMethodSelection = voxelizeMethodPanel.GetComponent<TMP_Dropdown>();
        resolutionInput = resolutionPanel.GetComponent<TMP_InputField>();
        renderModeSelection = renderModePanel.GetComponent<TMP_Dropdown>();
        textureSelection = textureSelectionPanel.GetComponent<TMP_Dropdown>();
        ambientOcclusionToggle = ambientOcclusionPanel.GetComponent<Toggle>();


        //Initialize on start settings and update shader manager to match
        Initialize();
    }


    /// <summary>
    /// Initializes all ui options and calls shadermanager to match
    /// </summary>
    private void Initialize()
    {
        //Read back values for voxelizeation
        GetMesh();
        GetVoxleMethod();
        GetResolution();

        //Call the shadermanager to voxelize the mesh
        shadermanager.VoxeliseMesh(mesh, resolution, voxelMehtod);

        //Read back values for render mode
        GetRenderMode();
        GetTextures();
        GetAmbientOcclusion();

        //call shadermanger to update render mode
        shadermanager.UpdateRenderShaderRenderSettings(renderMode, textures, ambientOcclusion);

        //Toggle UI options to match render mode
        ToggleUIOptions();
    }


    /// <summary>
    /// Called when TMP_Dropdown  menu for mesh selection changes value
    /// </summary>
    public void ChangeMeshSelection()
    {
        //Read back mesh selected
        GetMesh();

        //Call the shadermanager to voxelize the mesh
        shadermanager.VoxeliseMesh(mesh, resolution, voxelMehtod);
    }


    /// <summary>
    /// Called when TMP_Dropdown  menu for voxelize method changes value
    /// </summary>
    public void ChangeVoxelizeMethodSelection()
    {
        //Read back method of voxelizeation
        GetVoxleMethod();

        //Call the shadermanager to voxelize the mesh
        shadermanager.VoxeliseMesh(mesh, resolution, voxelMehtod);
    }


    /// <summary>
    /// Called when slider for voxel resolution changes value
    /// </summary>
    public void ChangeVoxelResolution()
    {
        //Read back voxel resoluiton
        GetResolution();

        //Call the shadermanager to voxelize the mesh
        shadermanager.VoxeliseMesh(mesh, resolution, voxelMehtod);
    }


    /// <summary>
    /// Called when  menu for render mode changes value
    /// </summary>
    public void ChangeRenderMode()
    {
        //Read back the Render mode
        GetRenderMode();

        //Toggle UI based on render mode
        ToggleUIOptions();

        //call shadermanger to update render mode
        shadermanager.UpdateRenderShaderRenderSettings(renderMode, textures, ambientOcclusion);
    }


    /// <summary>
    /// Called when TMP_Dropdown  menu for Texture selection changes value
    /// </summary>
    public void ChangeTextureSelection()
    {
        //Read back the Textures selected
        GetTextures();

        //call shadermanger to update render mode
        shadermanager.UpdateRenderShaderRenderSettings(renderMode, textures, ambientOcclusion);
    }


    /// <summary>
    /// Called when toggle for ambient occlusion changes value
    /// </summary>
    public void ChangeAmbientOcclusion()
    {
        //Read back the Textures selected
        GetAmbientOcclusion();

        //call shadermanger to update render mode
        shadermanager.UpdateRenderShaderRenderSettings(renderMode, textures, ambientOcclusion);
    }


    /// <summary>
    /// Reads back the render mode currently selected
    /// </summary>
    private void GetRenderMode()
    {
        int index = renderModeSelection.value;
        switch (index)
        {
            case 0:
                renderMode = RENDER_MODE.SOLID;
                break;
            case 1:
                renderMode = RENDER_MODE.POSITION;
                break;
            case 2:
                renderMode = RENDER_MODE.DEPTH;
                break;
            case 3:
                renderMode = RENDER_MODE.FACE;
                break;
            case 4:
                renderMode = RENDER_MODE.UV;
                break;
            case 5:
                renderMode = RENDER_MODE.TEXTURE;
                break;
        }
    }


    /// <summary>
    /// Reads back the method to voxelize
    /// </summary>
    private void GetVoxleMethod()
    {
        int index = voxelizeMethodSelection.value;
        switch (index)
        {
            case 0:
                voxelMehtod = VOXELMETHOD.VOLUME;
                break;
            case 1:
                voxelMehtod = VOXELMETHOD.VOLUME_COMPRESSED;
                break;
            case 2:
                voxelMehtod = VOXELMETHOD.SHELL;
                break;
            case 3:
                voxelMehtod = VOXELMETHOD.SHELL_COMPRESSED;
                break;
        }
    }


    /// <summary>
    /// Reads back the mesh selected
    /// </summary>
    private void GetMesh()
    {
        int index = meshSelection.value;
        mesh = meshes[index];
    }


    /// <summary>
    /// Reads back resolution selected
    /// </summary>
    private void GetResolution()
    {
        //Check if input field has a value
        if (string.IsNullOrEmpty(resolutionInput.text))
        {
            //Assign min value if input is empty
            resolution = 1;
            resolutionInput.text = "1";
            return;
        }

        int value = Int32.Parse(resolutionInput.text);

        //Check if value is smaller than min value
        if (value < 1)
        {
            //Assign min value if input is empty
            resolution = 1;
            resolutionInput.text = "1";
            return;
        }
        //Check if value is bigger than maximum allowed texture size
        else if (value > 2048)
        {
            //Assign max value if input is empty
            resolution = 2048;
            resolutionInput.text = "2048";
            return;
        }
        else
        {
            //Assign actual value to resolution
            resolution = value;
        }
    }


    /// <summary>
    /// Reads back Textures selected
    /// </summary>
    private void GetTextures()
    {
        int index = textureSelection.value;

        switch (index)
        {
            case 0:
                textures = testTexture;
                break;
            case 1:
                textures = blockTexture;
                break;
        }
    }


    /// <summary>
    /// Reads back if ambient occlusion is selected
    /// </summary>
    private void GetAmbientOcclusion()
    {
        ambientOcclusion = ambientOcclusionToggle.isOn;
    }


    /// <summary>
    /// Toggles the UI Options based on the render mode selected
    /// </summary>
    private void ToggleUIOptions()
    {
        //Enable Texture selection only when texture mode is selected
        if (renderMode == RENDER_MODE.TEXTURE)
        {
            textureSelectionPanel.SetActive(true);
        }
        else
        {
            textureSelectionPanel.SetActive(false);
        }

        //Disable Ambient Occlusion option if Render mode Depth is selected
        if (renderMode == RENDER_MODE.DEPTH)
        {
            ambientOcclusionParentPanel.SetActive(false);
        }
        else
        {
            ambientOcclusionParentPanel.SetActive(true);
        }
    }
}
