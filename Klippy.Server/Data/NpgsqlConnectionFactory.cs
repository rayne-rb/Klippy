using System.Data.Common;
using Microsoft.Extensions.Options;
using Npgsql;

namespace Klippy.Server.Data;

public sealed class NpgsqlConnectionFactory : IDbConnectionFactory, IAsyncDisposable
{
    private readonly NpgsqlDataSource _dataSource;

    public NpgsqlConnectionFactory(IOptions<KlippyDatabaseOptions> options)
    {
        _dataSource = new NpgsqlDataSourceBuilder(options.Value.ConnectionString).Build();
    }

    public async Task<DbConnection> OpenAsync(CancellationToken cancellationToken = default) =>
        await _dataSource.OpenConnectionAsync(cancellationToken);

    public ValueTask DisposeAsync() => _dataSource.DisposeAsync();
}
