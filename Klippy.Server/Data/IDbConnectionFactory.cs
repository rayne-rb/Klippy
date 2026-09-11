using System.Data.Common;

namespace Klippy.Server.Data;

/// <summary>
/// Hands out open connections. Slices take this rather than a connection string so
/// they never own pooling or lifetime decisions.
/// </summary>
public interface IDbConnectionFactory
{
    Task<DbConnection> OpenAsync(CancellationToken cancellationToken = default);
}
