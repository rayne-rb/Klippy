using Klippy.Server.Features.Link;

namespace Klippy.Server.Features.PetState;

public static class PetStateRegistration
{
    public static IServiceCollection AddPetStateFeature(this IServiceCollection services)
    {
        services.AddSingleton<PetStateStore>();
        services.AddScoped<IKlippyEventHandler, PetStateEventHandler>();
        return services;
    }
}
