using Godot;

public partial class Klippy : Node2D
{
    private const float Gravity = 2200f;
    private const float BounceDamping = 0.45f;
    private const float RestSpeed = 80f;
    private const float Friction = 800f;

    private bool _dragging;
    private Vector2I _dragOffset;
    private Vector2I _lastMousePos;
    private Vector2 _velocity;

    public override void _Ready()
    {
        ApplyClickThroughMask();
    }

    private void ApplyClickThroughMask()
    {
        var sprite = GetNode<Sprite2D>("Sprite2D");
        var texture = sprite.Texture;
        if (texture == null)
            return;

        var image = texture.GetImage();
        var bitmap = new BitMap();
        bitmap.CreateFromImageAlpha(image);

        var polygons = bitmap.OpacityToPolygons(new Rect2I(Vector2I.Zero, image.GetSize()));
        if (polygons.Count == 0)
            return;

        Vector2[] largest = polygons[0];
        foreach (Vector2[] polygon in polygons)
        {
            if (polygon.Length > largest.Length)
                largest = polygon;
        }

        var region = new Vector2[largest.Length];
        for (int i = 0; i < largest.Length; i++)
            region[i] = largest[i] * sprite.Scale;

        DisplayServer.WindowSetMousePassthrough(region);
    }

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventMouseButton mouseButton && mouseButton.ButtonIndex == MouseButton.Left)
        {
            if (mouseButton.Pressed)
            {
                _dragging = true;
                _velocity = Vector2.Zero;
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

        if (pos.X < minX)
        {
            pos.X = minX;
            _velocity.X = -_velocity.X * BounceDamping;
        }
        else if (pos.X > maxX)
        {
            pos.X = maxX;
            _velocity.X = -_velocity.X * BounceDamping;
        }

        if (pos.Y < minY)
        {
            pos.Y = minY;
            _velocity.Y = -_velocity.Y * BounceDamping;
        }
        else if (pos.Y >= floorY)
        {
            pos.Y = floorY;
            if (Mathf.Abs(_velocity.Y) > RestSpeed)
            {
                _velocity.Y = -_velocity.Y * BounceDamping;
            }
            else
            {
                _velocity.Y = 0f;
                _velocity.X = Mathf.MoveToward(_velocity.X, 0f, Friction * dt);
            }
        }

        window.Position = (Vector2I)pos;
    }
}
