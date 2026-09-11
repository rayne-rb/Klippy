using Microsoft.Data.Sqlite;
using RepoDb;

namespace Klippy.Mobile.Data;

/// <summary>
/// The phone's local SQLite store. Small on purpose: which server we are paired with,
/// and the last vitals we were told about, so the app has something to show before the
/// socket has connected.
///
/// grate runs the server's Postgres schema, but a mobile app cannot depend on a
/// migration tool being present. Here the schema is a short list of idempotent
/// statements gated on a version number, which is the usual shape on a device.
/// </summary>
public sealed class MobileDatabase
{
    private const int SchemaVersion = 2;

    private readonly string _connectionString;
    private bool _ready;

    public MobileDatabase()
    {
        var path = Path.Combine(FileSystem.AppDataDirectory, "klippy.db");
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadWriteCreate,
        }.ToString();

        GlobalConfiguration.Setup().UseSqlite();
    }

    public async Task<SqliteConnection> OpenAsync(CancellationToken ct = default)
    {
        var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(ct);

        if (!_ready)
        {
            await MigrateAsync(connection, ct);
            _ready = true;
        }

        return connection;
    }

    private static async Task MigrateAsync(SqliteConnection connection, CancellationToken ct)
    {
        var current = Convert.ToInt32(
            await connection.ExecuteScalarAsync("pragma user_version;", cancellationToken: ct));

        if (current >= SchemaVersion)
        {
            return;
        }

        if (current < 1)
        {
            await connection.ExecuteNonQueryAsync(
                """
                create table if not exists paired_server (
                    server_id   text primary key,
                    name        text not null,
                    base_url    text not null,
                    ws_url      text not null,
                    device_id   text not null,
                    token       text not null,
                    paired_at   text not null
                );

                create table if not exists last_pet_stats (
                    id           integer primary key check (id = 1),
                    food         real not null,
                    mood         real not null,
                    health       real not null,
                    is_dead      integer not null,
                    food_status  text,
                    mood_status  text,
                    health_status text,
                    seen_at      text not null
                );
                """,
                cancellationToken: ct);
        }

        if (current < 2)
        {
            // Small key/value bag for user settings. The first is the manually entered
            // server address, used when multicast discovery cannot reach the server.
            await connection.ExecuteNonQueryAsync(
                """
                create table if not exists app_settings (
                    key   text primary key,
                    value text not null
                );
                """,
                cancellationToken: ct);
        }

        await connection.ExecuteNonQueryAsync($"pragma user_version = {SchemaVersion};", cancellationToken: ct);
    }
}
