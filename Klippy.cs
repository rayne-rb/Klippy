using Godot;

public partial class Klippy : Node2D
{
    private const float Gravity = 2200f;
    private const float BounceDamping = 0.45f;
    private const float RestSpeed = 80f;
    private const float Friction = 800f;
    private const float RollRadius = 90f;
    private const float AirSpinDamping = 0.1f;
    private const float SpinRecoveryRate = 10f;

    private Sprite2D _sprite;
    private Vector2[] _maskPoints;

    private bool _dragging;
    private Vector2I _dragOffset;
    private Vector2I _lastMousePos;
    private Vector2 _velocity;
    private float _angularVelocity;

    public override void _Ready()
    {
        _sprite = GetNode<Sprite2D>("Sprite2D");
        BuildClickThroughMask();
    }

    private void BuildClickThroughMask()
    {
        var texture = _sprite.Texture;
        if (texture == null)
            return;

        var image = texture.GetImage();
        var bitmap = new Bitmap();
        bitmap.CreateFromImageAlpha(image, 0.1f);

        var polygons = bitmap.OpaqueToPolygons(new Rect2I(Vector2I.Zero, image.GetSize()), 2.0f);
        if (polygons.Count == 0)
            return;

        Vector2[] largest = polygons[0];
        foreach (Vector2[] polygon in polygons)
        {
            if (polygon.Length > largest.Length)
                largest = polygon;
        }

        var center = (Vector2)GetWindow().Size / 2f;
        _maskPoints = new Vector2[largest.Length];
        for (int i = 0; i < largest.Length; i++)
            _maskPoints[i] = largest[i] * _sprite.Scale - center;

        UpdatePassthroughMask(0f);
    }

    private void UpdatePassthroughMask(float rotation)
    {
        if (_maskPoints == null)
            return;

        var center = (Vector2)GetWindow().Size / 2f;
        var region = new Vector2[_maskPoints.Length];
        for (int i = 0; i < _maskPoints.Length; i++)
            region[i] = _maskPoints[i].Rotated(rotation) + center;

        DisplayServer.WindowSetMousePassthrough(region, 0);
    }

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventMouseButton mouseButton && mouseButton.ButtonIndex == MouseButton.Left)
        {
            if (mouseButton.Pressed)
            {
                _dragging = true;
                _velocity = Vector2.Zero;
                _angularVelocity = 0f;
                _lastMousePos = DisplayServer.MouseGetPosition();
                _dragOffset = _lastMousePos - GetWindow().Position;
            }
            else
            {
                _dragging = false;
            }
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        var dt = (float)delta;
        var window = GetWindow();

        if (_dragging)
        {
            var mousePos = DisplayServer.MouseGetPosition();
            window.Position = mousePos - _dragOffset;
            if (dt > 0f)
                _velocity = (Vector2)(mousePos - _lastMousePos) / dt;
            _lastMousePos = mousePos;

            if (_sprite.Rotation != 0f)
            {
                float t = 1f - Mathf.Exp(-SpinRecoveryRate * dt);
                _sprite.Rotation = Mathf.LerpAngle(_sprite.Rotation, 0f, t);
                if (Mathf.Abs(_sprite.Rotation) < 0.001f)
                    _sprite.Rotation = 0f;
                UpdatePassthroughMask(_sprite.Rotation);
            }

            return;
        }

        if (_velocity == Vector2.Zero)
            return;

        _velocity.Y += Gravity * dt;

        var bounds = DisplayServer.ScreenGetUsableRect(window.CurrentScreen);
        var size = (Vector2)window.Size;
        var pos = (Vector2)window.Position + _velocity * dt;

        float minX = bounds.Position.X;
        float maxX = bounds.Position.X + bounds.Size.X - size.X;
        float minY = bounds.Position.Y;
        float floorY = bounds.Position.Y + bounds.Size.Y - size.Y;

        bool directRoll = false;

        if (pos.X < minX)
        {
            pos.X = minX;
            _velocity.X = -_velocity.X * BounceDamping;
            _angularVelocity += -_velocity.Y / RollRadius;
        }
        else if (pos.X > maxX)
        {
            pos.X = maxX;
            _velocity.X = -_velocity.X * BounceDamping;
            _angularVelocity += -_velocity.Y / RollRadius;
        }

        if (pos.Y < minY)
        {
            pos.Y = minY;
            _velocity.Y = -_velocity.Y * BounceDamping;
            _angularVelocity += _velocity.X / RollRadius;
        }
        else if (pos.Y >= floorY)
        {
            pos.Y = floorY;
            if (Mathf.Abs(_velocity.Y) > RestSpeed)
            {
                _velocity.Y = -_velocity.Y * BounceDamping;
                _angularVelocity += _velocity.X / RollRadius;
            }
            else
            {
                _velocity.Y = 0f;
                _velocity.X = Mathf.MoveToward(_velocity.X, 0f, Friction * dt);
                _angularVelocity = _velocity.X / RollRadius;
                directRoll = true;
            }
        }

        if (!directRoll)
            _angularVelocity *= Mathf.Max(0f, 1f - AirSpinDamping * dt);

        if (_angularVelocity != 0f)
        {
            _sprite.Rotation += _angularVelocity * dt;
            UpdatePassthroughMask(_sprite.Rotation);
        }

        window.Position = (Vector2I)pos;
    }
}
