namespace Klippy.Server.Data;

public sealed class KlippyDatabaseOptions
{
    public const string SectionName = "Database";

    /// <summary>Connection to the klippy database itself.</summary>
    public string ConnectionString { get; set; } =
        "Host=localhost;Port=55432;Database=klippy;Username=klippy;Password=klippy";

    /// <summary>
    /// Connection grate uses to CREATE the database when it does not exist yet.
    /// Points at the maintenance database, so it cannot be the one being created.
    /// </summary>
    public string AdminConnectionString { get; set; } =
        "Host=localhost;Port=55432;Database=postgres;Username=klippy;Password=klippy";

    /// <summary>Folder holding the grate script folders (up/, views/, ...), relative to the content root.</summary>
    public string MigrationsPath { get; set; } = "db";

    /// <summary>Run migrations during startup. Turn off when a shared database is managed elsewhere.</summary>
    public bool MigrateOnStartup { get; set; } = true;
}
