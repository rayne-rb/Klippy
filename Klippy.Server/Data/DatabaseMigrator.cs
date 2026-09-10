using grate.Configuration;
using grate.Migration;
using grate.postgresql.DependencyInjection;
using Microsoft.Extensions.Options;
using Npgsql;
using RepoDb;

namespace Klippy.Server.Data;

/// <summary>
/// Applies the SQL in <c>db/</c> with grate before the app serves its first request.
/// Scripts in <c>db/up</c> run exactly once and are checksummed, so an already-applied
/// file that changes is reported rather than silently re-run.
/// </summary>
public sealed class DatabaseMigrator(
    IOptions<KlippyDatabaseOptions> options,
    IDbConnectionFactory connections,
    IHostEnvironment environment,
    ILoggerFactory loggerFactory,
    ILogger<DatabaseMigrator> logger)
{
    // Where grate keeps its record of applied scripts. Pinned instead of left to grate's
    // defaults so the count below can never read a different table than grate writes to.
    private const string SchemaName = "grate";
    private const string ScriptsRunTableName = "ScriptsRun";

    private const string ScriptsRunCountSql =
        $"""select count(*) from {SchemaName}."{ScriptsRunTableName}";""";

    public async Task MigrateAsync()
    {
        var settings = options.Value;

        if (!settings.MigrateOnStartup)
        {
            logger.LogInformation("Startup migration disabled; assuming the schema is managed elsewhere.");
            return;
        }

        var scriptsDirectory = new DirectoryInfo(
            Path.Combine(environment.ContentRootPath, settings.MigrationsPath));

        if (!scriptsDirectory.Exists)
        {
            throw new DirectoryNotFoundException(
                $"Migration scripts not found at '{scriptsDirectory.FullName}'. " +
                "Check Database:MigrationsPath, and that db/**/*.sql is being copied to the output.");
        }

        var configuration = new GrateConfiguration
        {
            ConnectionString = settings.ConnectionString,
            AdminConnectionString = settings.AdminConnectionString,
            SqlFilesDirectory = scriptsDirectory,
            CreateDatabase = true,
            Transaction = true,
            NonInteractive = true,
            SchemaName = SchemaName,
            ScriptsRunTableName = ScriptsRunTableName,
            // Keep grate's per-run log tree inside obj/ rather than dropping an
            // 'output' folder into the project root on every start.
            OutputPath = new DirectoryInfo(Path.Combine(environment.ContentRootPath, "obj", "grate")),
        };

        // grate registers a good deal of its own machinery. Give it a throwaway
        // container so none of that ends up resolvable from the app's.
        var services = new ServiceCollection();
        services.AddSingleton<ILoggerFactory>(new WarningsOnlyLoggerFactory(loggerFactory));
        services.AddLogging();
        services.AddGrateWithPostgreSQL(configuration);

        await using var provider = services.BuildServiceProvider();
        var migrator = provider.GetRequiredService<IGrateMigrator>();

        var scriptsBefore = await CountAppliedScriptsAsync();
        await migrator.Migrate();
        var scriptsAfter = await CountAppliedScriptsAsync();

        if (scriptsAfter is null)
        {
            // grate did not throw, so the run succeeded; without a readable count there
            // is nothing to say about how much of it was new.
            logger.LogInformation("Database migrations ran successfully.");
            return;
        }

        // An unreadable count before the run means the database did not exist yet, so
        // everything grate has on record now was applied by this start.
        var applied = scriptsAfter.Value - (scriptsBefore ?? 0);

        if (applied > 0)
        {
            logger.LogInformation("Database migrations ran successfully ({ScriptCount} script(s) applied).", applied);
        }
        else
        {
            logger.LogInformation("No migrations to run; the database schema is up to date.");
        }
    }

    /// <summary>
    /// How many scripts grate has on record as applied, or <c>null</c> when neither the
    /// database nor its bookkeeping table exists yet. Taken either side of the run, this
    /// is what tells the log line whether this start actually applied anything.
    /// </summary>
    private async Task<long?> CountAppliedScriptsAsync()
    {
        try
        {
            await using var connection = await connections.OpenAsync();
            return await connection.ExecuteScalarAsync<long>(ScriptsRunCountSql);
        }
        catch (PostgresException)
        {
            // First ever start: no klippy database (3D000), or no grate schema (42P01).
            return null;
        }
    }

    /// <summary>
    /// Forwards to the app's log providers but drops anything below Warning. grate is a
    /// command line tool at heart and narrates its entire run at Information - a couple
    /// of dozen lines on every start - which this keeps out of the server's log without
    /// hiding anything that actually went wrong.
    /// </summary>
    private sealed class WarningsOnlyLoggerFactory(ILoggerFactory inner) : ILoggerFactory
    {
        public ILogger CreateLogger(string categoryName) =>
            new WarningsOnlyLogger(inner.CreateLogger(categoryName));

        public void AddProvider(ILoggerProvider provider) => inner.AddProvider(provider);

        // The wrapped factory belongs to the host, which disposes it itself.
        public void Dispose()
        {
        }

        private sealed class WarningsOnlyLogger(ILogger inner) : ILogger
        {
            public IDisposable? BeginScope<TState>(TState state) where TState : notnull =>
                inner.BeginScope(state);

            public bool IsEnabled(LogLevel logLevel) =>
                logLevel >= LogLevel.Warning && inner.IsEnabled(logLevel);

            public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
                Func<TState, Exception?, string> formatter)
            {
                if (logLevel >= LogLevel.Warning)
                {
                    inner.Log(logLevel, eventId, state, exception, formatter);
                }
            }
        }
    }
}
