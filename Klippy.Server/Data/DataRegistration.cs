using RepoDb;

namespace Klippy.Server.Data;

public static class DataRegistration
{
    /// <summary>
    /// Registers the connection factory and initialises RepoDb for Npgsql. This is the
    /// only shared data plumbing: each slice owns its own entities and repository.
    /// </summary>
    public static IServiceCollection AddKlippyData(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<KlippyDatabaseOptions>(
            configuration.GetSection(KlippyDatabaseOptions.SectionName));

        services.AddSingleton<IDbConnectionFactory, NpgsqlConnectionFactory>();
        services.AddSingleton<DatabaseMigrator>();

        // Teaches RepoDb the Npgsql dialect: statement builder, DB setting, type maps.
        GlobalConfiguration.Setup().UsePostgreSql();

        return services;
    }
}
