using UnityEngine;

public class CameraController : MonoBehaviour
{
    public float normalSpeed = 5.0f;
    public float fastSpeed = 15.0f;
    public float mouseSensitivity = 2.0f;
    public float climbSpeed = 5.0f;

    private float rotationX = 0.0f;
    private float rotationY = 0.0f;

    private bool cursorLocked = false;

    void Start()
    {
        Vector3 rot = transform.localRotation.eulerAngles;
        rotationX = rot.y;
        rotationY = rot.x;
    }

    void Update()
    {
        HandleMouseLook();
        HandleMovementInput();
    }

    void HandleMouseLook()
    {
        if (Input.GetMouseButtonDown(1))
        {
            LockCursor(true);
        }
        else if (Input.GetMouseButtonUp(1))
        {
            LockCursor(false);
        }

        if (!cursorLocked) return;

        float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
        float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity;

        rotationX += mouseX;
        rotationY -= mouseY;
        rotationY = Mathf.Clamp(rotationY, -89f, 89f);

        transform.rotation = Quaternion.Euler(rotationY, rotationX, 0.0f);
    }

    void HandleMovementInput()
    {
        float speed = Input.GetKey(KeyCode.LeftShift) ? fastSpeed : normalSpeed;

        Vector3 direction = new Vector3();

        if (Input.GetKey(KeyCode.W))
            direction += transform.forward;
        if (Input.GetKey(KeyCode.S))
            direction -= transform.forward;
        if (Input.GetKey(KeyCode.A))
            direction -= transform.right;
        if (Input.GetKey(KeyCode.D))
            direction += transform.right;
        if (Input.GetKey(KeyCode.E))
            direction += Vector3.up;
        if (Input.GetKey(KeyCode.Q))
            direction -= Vector3.up;

        transform.position += direction.normalized * speed * Time.deltaTime;
    }

    void LockCursor(bool isLocked)
    {
        cursorLocked = isLocked;
        Cursor.lockState = isLocked ? CursorLockMode.Locked : CursorLockMode.None;
        Cursor.visible = !isLocked;
    }
}
