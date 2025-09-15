using UnityEngine;

public class CameraController : MonoBehaviour
{
    public Transform target;               // The origin of your coordinate system
    public float distance = 10.0f;
    public float zoomSpeed = 2.0f;
    public float minDistance = 2f;
    public float maxDistance = 50f;

    public float rotationSpeed = 5.0f;
    public float panSpeed = 0.5f;

    public float minYAngle = 5f;
    public float maxYAngle = 85f;

    public float maxPanDistance = 20f;     // 🔒 Max distance allowed for panning

    private float currentX = 0f;
    private float currentY = 45f;

    private Vector3 targetOffset = Vector3.zero;

    void Update()
    {
        // Rotate around target
        if (Input.GetMouseButton(1)) // Right mouse
        {
            currentX += Input.GetAxis("Mouse X") * rotationSpeed;
            currentY -= Input.GetAxis("Mouse Y") * rotationSpeed;
            currentY = Mathf.Clamp(currentY, minYAngle, maxYAngle);
        }

        // Zoom
        float scroll = Input.GetAxis("Mouse ScrollWheel");
        distance -= scroll * zoomSpeed;
        distance = Mathf.Clamp(distance, minDistance, maxDistance);

        // Pan (Middle Mouse Button)
        if (Input.GetMouseButton(2))
        {
            float panX = -Input.GetAxis("Mouse X") * panSpeed;
            float panY = -Input.GetAxis("Mouse Y") * panSpeed;

            // Pan in camera's local space
            Vector3 right = transform.right;
            Vector3 up = transform.up;

            Vector3 panMovement = right * panX + up * panY;
            Vector3 newOffset = targetOffset + panMovement;

            // Clamp the new offset to stay within max pan distance
            if (newOffset.magnitude <= maxPanDistance)
            {
                targetOffset = newOffset;
            }
            else
            {
                targetOffset = newOffset.normalized * maxPanDistance;
            }
        }
    }

    void LateUpdate()
    {
        Quaternion rotation = Quaternion.Euler(currentY, currentX, 0);
        Vector3 direction = rotation * new Vector3(0, 0, -distance);

        Vector3 finalTargetPosition = target.position + targetOffset;

        transform.position = finalTargetPosition + direction;
        transform.LookAt(finalTargetPosition);
    }
}
