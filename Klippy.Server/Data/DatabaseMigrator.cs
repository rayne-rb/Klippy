using grate.Configuration;
using grate.Migration;
using grate.postgresql.DependencyInjection;
using Microsoft.Extensions.Options;

namespace Klippy.Server.Data;

/// <summary>
/// Applies the SQL in <c>db/</c> with grate before the app serves its first request.
/// Scripts in <c>db/up</c> run exactly once and are checksummed, so an already-applied
/// file that changes is reported rather than silently re-run.
/// </summary>
public sealed class DatabaseMigrator(
    IOptions<KlippyDatabaseOptions> options,
    IHostEnvironment environment,
    ILoggerFactory loggerFactory,
    ILogger<DatabaseMigrator> logger)
{
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
            // Keep grate's per-run log tree inside obj/ rather than dropping an
            // 'output' folder into the project root on every start.
            OutputPath = new DirectoryInfo(Path.Combine(environment.ContentRootPath, "obj", "grate")),
        };

        // grate registers a good deal of its own machinery. Give it a throwaway
        // container so none of that ends up resolvable from the app's.
        var services = new ServiceCollection();
        services.AddSingleton(loggerFactory);
        services.AddLogging();
        services.AddGrateWithPostgreSQL(configuration);

        await using var provider = services.BuildServiceProvider();
        var migrator = provider.GetRequiredService<IGrateMigrator>();

        logger.LogInformation("Running migrations from {Path}", scriptsDirectory.FullName);
        await migrator.Migrate();
        logger.LogInformation("Database schema is up to date.");
    }
}
