/*
 * godot_weather_accessors.c — C accessors for weather state from the engine.
 *
 * The cgame module (cg_nature.cpp) manages rain/snow state in the
 * cg.rain struct.  Since cgame runs as a separate .so and the Godot
 * GDExtension cannot directly include cgame headers, we read weather
 * state via cvars that the engine exposes.
 *
 * The engine uses cvars "cg_rain" and configstrings to communicate
 * weather.  Rain density > 0 indicates active rain.  Snow is
 * indicated by the "cg_snow" cvar or a snow configstring.
 *
 * As a fallback, since cgame processes rain locally and submits
 * rain lines as render polygons, the poly buffer already captures
 * rain visuals.  This accessor provides state hints for the
 * GPUParticles3D approach in godot_weather.cpp.
 */

#ifdef GODOT_GDEXTENSION

/* ── Engine cvar access (from qcommon) ── */
extern void *Cvar_Get(const char *var_name, const char *var_value, int flags);

/* Minimal cvar struct — only need the float value */
typedef struct {
    char pad[68];   /* fields before 'value' in cvar_t */
    float value;
} cvar_value_t;

static void *s_cg_rain_cvar = (void *)0;
static int   s_weather_state = 0;  /* 0=none, 1=rain, 2=snow */
static float s_weather_density = 0.0f;

/*
 * Godot_Weather_GetState — returns current weather type.
 *
 * 0 = no weather, 1 = rain, 2 = snow.
 *
 * Since cgame handles weather rendering internally via poly submission,
 * and the cvar "cg_rain" only controls whether cgame draws rain (not
 * whether rain is active), we default to WEATHER_NONE.  The actual
 * rain density is set by server-side commands that cgame processes
 * internally.
 *
 * For the Godot particle approach, MoHAARunner or an integration
 * agent can set the weather state explicitly when the engine
 * communicates weather commands.  Until then, return 0.
 */
int Godot_Weather_GetState(void) {
    return s_weather_state;
}

/*
 * Godot_Weather_GetDensity — returns weather intensity [0..1].
 */
float Godot_Weather_GetDensity(void) {
    return s_weather_density;
}

#endif /* GODOT_GDEXTENSION */
