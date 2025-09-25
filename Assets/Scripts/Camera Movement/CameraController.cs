using UnityEngine;

public class CameraController : MonoBehaviour
{
    private Vector3 pivotPosition; // The point to orbit around (like Blender's 3D cursor)
    public float orbitSpeed = 4f;
    public float panSpeed = 0.5f;
    public float scrollSensitivity = 10f;

    private Vector3 lastMousePosition;

    void Update()
    {
        HandleMouseInput();
        HandleScrollInput();
    }


    /// <summary>
    /// Handles the mouse inputs
    /// </summary>
    void HandleMouseInput()
    {
        if (Input.GetMouseButton(0) || Input.GetMouseButton(1)) // LMB or RMB
        {
            Vector3 delta = Input.mousePosition - lastMousePosition;

            if (Input.GetMouseButton(0))
            {
                // Panning
                PanCamera(delta);
            }
            else
            {
                // Orbiting
                OrbitCamera(delta);
            }
        }

        lastMousePosition = Input.mousePosition;
    }


    /// <summary>
    /// Moves Camera based on scroll input
    /// </summary>
    void HandleScrollInput()
    {
        float scroll = Input.GetAxis("Mouse ScrollWheel");
        if (Mathf.Abs(scroll) > 0.0001f)
        {
            Vector3 move = transform.forward * scroll * scrollSensitivity;
            transform.position += move;
            pivotPosition += move; // Move the pivot with the camera
        }
    }


    /// <summary>
    /// Rotates the Camera
    /// </summary>
    void OrbitCamera(Vector3 delta)
    {
        Vector3 angles = new Vector3(-delta.y, delta.x, 0) * orbitSpeed * Time.deltaTime;

        // Rotate around pivot position
        transform.RotateAround(pivotPosition, transform.right, angles.x);
        transform.RotateAround(pivotPosition, Vector3.up, angles.y);

        // After orbiting, look at pivot again
        transform.LookAt(pivotPosition);
    }


    /// <summary>
    /// Moves the Camera
    /// </summary>
    void PanCamera(Vector3 delta)
    {
        // Move camera and pivot along camera's local axes
        Vector3 right = transform.right;
        Vector3 up = transform.up;
        Vector3 movement = (-right * delta.x + -up * delta.y) * panSpeed * Time.deltaTime;

        transform.position += movement;
        pivotPosition += movement;
    }

    /// <summary>
    /// Updates the Camera Pivot point
    /// </summary>
    public void SetCameraPivot(Vector3 centerPoint)
    {
        pivotPosition = centerPoint;
        transform.LookAt(pivotPosition);
    }
}
